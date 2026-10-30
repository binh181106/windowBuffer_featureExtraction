`timescale 1ns / 1 ps

// =============================================================================
// Control FSM - 10-State Master Controller
// =============================================================================
// Function: Orchestrates the entire ECG classification pipeline
// States: IDLE -> LOAD -> NORMALIZE -> FC1 -> FC1_B -> RELU -> FC2 -> FC2_B -> ARGMAX -> DONE
//
// Fix v3.0 (BƯỚC 2):
//  - window_en: giữ =1 khi hệ thống được enable (SYS_ENABLE) để window_buffer
//    liên tục gom mẫu. Trước đây window_en chỉ =1 trong state LOAD -> buffer
//    không bao giờ đầy 512 mẫu -> window_ready không bao giờ fire.
//  - feature_start chỉ phát khi có window_ready (cửa sổ 512 mẫu đầy), thay vì
//    phát ngay khi start -> feature đọc cửa sổ rỗng.
//  - Thêm handshake mlp_done từ ai_classifier: các state FC1..ARGMAX chờ
//    mlp_done (kèm timeout) -> không deadlock nếu MLP không hoàn tất.
//  - Thêm soft_reset: đưa FSM về IDLE ngay lập tức.
// =============================================================================

module control_fsm (
    // Clock and Reset
    input  wire              clk,
    input  wire              rst_n,

    // Control Inputs
    input  wire              start,          // Start classification
    input  wire              feat_valid,     // Features ready from Feature Engine
    input  wire              apb_enable,     // Enable from APB CSR
    input  wire              window_ready,   // Window buffer has a full 512-sample window
    input  wire              mlp_done,       // AI classifier finished inference
    input  wire              soft_reset,     // Soft reset -> force back to IDLE

    // Control Outputs
    output reg               fsm_idle,        // FSM in IDLE state
    output reg               window_en,        // Enable Window Buffer
    output reg               feature_start,    // Start Feature Extraction
    output reg               feature_read_en,  // Read from Window Buffer
    output reg               mlp_start,        // Start MLP inference
    output reg               mlp_valid,        // Features valid for MLP
    output reg               uart_send,        // Trigger UART TX
    output reg               done,             // Classification complete

    // Feature Buffer Address (to Window Buffer)
    output wire [8:0]       read_addr,        // Address for reading samples

    // Status
    output reg  [3:0]       current_state,    // Debug: current state
    output reg  [3:0]       next_state_debug   // Debug: next state
);

    // =============================================================================
    // FSM States (10 states)
    // =============================================================================
    localparam S_IDLE      = 4'd0;
    localparam S_LOAD      = 4'd1;
    localparam S_NORM      = 4'd2;
    localparam S_FC1       = 4'd3;
    localparam S_FC1_B     = 4'd4;
    localparam S_RELU      = 4'd5;
    localparam S_FC2       = 4'd6;
    localparam S_FC2_B     = 4'd7;
    localparam S_ARGMAX    = 4'd8;
    localparam S_DONE      = 4'd9;

    // Timeout cho state LOAD (đợi window_ready + feat_valid) và state FC1
    // (đợi mlp_done). Giá trị lớn hơn thời gian thực tế để không cắt ngang:
    //   LOAD : 512 mẫu @360Hz ~ 1.42 s = ~71.6e6 chu kỳ -> dùng 100e6 (cần 27 bit)
    //   FC1  : MLP ~161 chu kỳ -> dùng 10000
    localparam [27:0] LOAD_TIMEOUT = 28'd100_000_000;
    localparam [27:0] MLP_TIMEOUT  = 28'd10_000;

    // =============================================================================
    // State Registers
    // =============================================================================
    reg [3:0] state;
    reg [3:0] next_state;

    // Counter for multi-cycle operations
    reg [9:0]  cnt;          // 10-bit counter for timing
    reg        cnt_enable;   // Counter enable
    reg [27:0] timeout_cnt;  // Timeout counter (no deadlock)

    // (fix v3.0) Đã phát feature_start, đang chờ feat_valid -> không re-trigger
    // khi window_ready phát lại (overlap buffer) trong khi feature đang tính.
    reg        feat_started;

    // =============================================================================
    // FSM Sequential Logic
    //
    // (fix v3.1) next_state được tính bằng BLOCKING trong cùng cycle, state
    // được commit NBA MỘT LẦN sau endcase.
    //
    // Trước đây (v3.0): "state <= next_state;" đặt TRƯỚC case, cả 2 đều NBA
    // trong cùng block -> state_k = f(state_{k-2}): FSM trễ 2 chu kỳ so với
    // chính logic của nó. Hậu quả: FSM dao động IDLE<->LOAD mỗi clock và BỎ
    // LỖI pulse 1-chu kỳ (feat_valid, window_ready, mlp_done) -> không bao
    // giờ đến FC1/DONE -> không có IRQ (đã capture bằng trace: LOAD->IDLE
    // xuất hiện dù sft=0, winR=0, featV=0, timeout!=0 - bất hợp lệ theo
    // logic case, chỉ giải thích được bằng trễ 2 chu kỳ).
    // =============================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state          <= S_IDLE;
            next_state     = S_IDLE;
            cnt            <= 10'd0;
            cnt_enable     <= 1'b0;
            timeout_cnt    <= 28'd0;
            feat_started   <= 1'b0;
            current_state  <= S_IDLE;

            // Clear all control signals
            fsm_idle        <= 1'b1;
            window_en       <= 1'b0;
            feature_start   <= 1'b0;
            feature_read_en <= 1'b0;
            mlp_start       <= 1'b0;
            mlp_valid       <= 1'b0;
            uart_send       <= 1'b0;
            done            <= 1'b0;

        end else begin
            current_state <= state;

            // Counter logic
            if (cnt_enable) begin
                cnt <= cnt + 10'd1;
            end else begin
                cnt <= 10'd0;
            end

            // Timeout counter: chỉ chạy ở state đang chờ tín hiệu ngoài
            if (timeout_cnt != 28'd0)
                timeout_cnt <= timeout_cnt - 28'd1;

            // Default outputs
            fsm_idle        <= 1'b0;
            feature_start   <= 1'b0;
            feature_read_en <= 1'b0;
            uart_send       <= 1'b0;
            cnt_enable      <= 1'b0;

            case (state)
                // =============================================================
                // IDLE: Wait for start, clear all registers
                // =============================================================
                S_IDLE: begin
                    fsm_idle        <= 1'b1;
                    mlp_start       <= 1'b0;
                    mlp_valid       <= 1'b0;
                    done            <= 1'b0;
                    cnt_enable      <= 1'b0;

                    // Buffer gom mẫu liên tục khi hệ thống được enable
                    window_en       <= apb_enable;

                    if (soft_reset) begin
                        next_state = S_IDLE;
                    end else if (start && apb_enable) begin
                        timeout_cnt <= LOAD_TIMEOUT;
                        next_state = S_LOAD;
                    end else begin
                        next_state = S_IDLE;
                    end
                end

                // =============================================================
                // LOAD: Wait for a full window, run feature extraction, wait
                //       for features, then hand over to the MLP stage.
                // =============================================================
                S_LOAD: begin
                    window_en     <= 1'b1;   // giữ buffer chạy trong suốt pipeline
                    mlp_valid     <= 1'b0;

                    if (soft_reset) begin
                        next_state = S_IDLE;
                    end else if (!feat_started && window_ready) begin
                        // Cửa sổ 512 mẫu đã đầy -> phát feature_start (1 chu kỳ).
                        // feat_started chặn re-trigger khi window_ready phát lại
                        // (overlap buffer) trong lúc feature đang tính.
                        feature_start <= 1'b1;
                        feat_started  <= 1'b1;
                        timeout_cnt   <= LOAD_TIMEOUT;
                        next_state = S_LOAD;
                    end else if (feat_valid) begin
                        // Features đã sẵn sàng -> sang stage MLP
                        feat_started <= 1'b0;
                        timeout_cnt  <= LOAD_TIMEOUT;
                        next_state = S_NORM;
                    end else if (timeout_cnt == 28'd0) begin
                        // Timeout: không có feature -> quay về IDLE (không deadlock)
                        feat_started <= 1'b0;
                        next_state = S_IDLE;
                    end else begin
                        next_state = S_LOAD;
                    end
                end

                // =============================================================
                // NORMALIZE: features are being normalized inside ai_classifier
                // =============================================================
                S_NORM: begin
                    window_en     <= 1'b1;
                    mlp_valid     <= 1'b1;   // Features are valid for MLP
                    cnt_enable    <= 1'b1;

                    if (soft_reset) begin
                        next_state = S_IDLE;
                    end else if (cnt == 10'd12) begin
                        next_state = S_FC1;
                        cnt_enable <= 1'b0;
                    end else begin
                        next_state = S_NORM;
                    end
                end

                // =============================================================
                // FC1: Start MLP inference and wait for mlp_done
                // =============================================================
                // Ghi chú kiến trúc: ai_classifier có FSM nội bộ riêng thực sự
                // tính toán (LOAD->NORM->FC1->FC1_B->RELU->FC2->FC2_B->ARGMAX).
                // control_fsm giữ đúng chuỗi 10 trạng thái để debug/trace và
                // chỉ dùng mlp_done làm điều kiện thoát -> không deadlock.
                S_FC1: begin
                    window_en     <= 1'b1;
                    mlp_valid     <= 1'b1;

                    if (soft_reset) begin
                        // soft reset: hạ mlp_start để ai_classifier không re-trigger
                        mlp_start  <= 1'b0;
                        next_state = S_IDLE;
                    end else if (mlp_start == 1'b0) begin
                        // Chu kỳ đầu trong S_FC1 (chưa phát start): phát mlp_start.
                        // ai_classifier (đang IDLE) nhận start && enable, chạy FSM
                        // nội bộ ~161 chu kỳ; mlp_done phát 1 chu kỳ khi ai.done.
                        mlp_start  <= 1'b1;
                        next_state = S_FC1;
                    end else if (mlp_done || timeout_cnt == 28'd0) begin
                        // MLP xong (hoặc timeout) -> hạ mlp_start, đi tiếp qua các
                        // state trung gian rồi tới DONE.
                        mlp_start  <= 1'b0;
                        if (mlp_done == 1'b0)
                            $display("[control_fsm] TIMEOUT waiting for mlp_done");
                        next_state = S_FC1_B;
                    end else begin
                        next_state = S_FC1;
                    end
                end

                // =============================================================
                // FC1_B .. ARGMAX: pass-through states (giữ chuỗi 10 trạng thái)
                // =============================================================
                S_FC1_B: begin
                    window_en  <= 1'b1;
                    mlp_valid  <= 1'b1;
                    if (soft_reset) next_state = S_IDLE;
                    else            next_state = S_RELU;
                end

                S_RELU: begin
                    window_en  <= 1'b1;
                    mlp_valid  <= 1'b1;
                    if (soft_reset) next_state = S_IDLE;
                    else            next_state = S_FC2;
                end

                S_FC2: begin
                    window_en  <= 1'b1;
                    mlp_valid  <= 1'b1;
                    if (soft_reset) next_state = S_IDLE;
                    else            next_state = S_FC2_B;
                end

                S_FC2_B: begin
                    window_en  <= 1'b1;
                    mlp_valid  <= 1'b1;
                    if (soft_reset) next_state = S_IDLE;
                    else            next_state = S_ARGMAX;
                end

                S_ARGMAX: begin
                    window_en  <= 1'b1;
                    mlp_valid  <= 1'b1;
                    if (soft_reset) next_state = S_IDLE;
                    else            next_state = S_DONE;
                end

                // =============================================================
                // DONE: Classification complete, send result
                // =============================================================
                S_DONE: begin
                    window_en <= 1'b1;
                    done       <= 1'b1;
                    uart_send  <= 1'b1;

                    // Return to IDLE after done is acknowledged
                    if (soft_reset) begin
                        next_state = S_IDLE;
                    end else if (!start) begin
                        next_state = S_IDLE;
                    end else begin
                        next_state = S_DONE;
                    end
                end

                default: next_state = S_IDLE;
            endcase

            // (fix v3.1) commit state MỘT LẦN, sau khi next_state đã tính bằng
            // blocking (giá trị mới nhất, không trễ) -> state_{k+1} = f(state_k).
            state <= next_state;
        end
    end

    // =============================================================================
    // Read Address Generation (for Window Buffer)
    // =============================================================================
    // Ghi chú: ai_classifier dùng FSM nội bộ riêng, control_fsm không điều khiển
    // địa chỉ đọc. read_addr giữ nguyên để tương thích (luôn 0).
    assign read_addr = 9'd0;

    // =============================================================================
    // Next State Debug Output
    // =============================================================================
    always @(posedge clk) begin
        next_state_debug <= next_state;
    end

endmodule
