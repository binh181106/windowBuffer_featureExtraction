`timescale 1ns / 1ps

// =============================================================================
// Control FSM - 10-State Master Controller
// =============================================================================
// Function: Orchestrates the entire PPG classification pipeline
// States: IDLE -> LOAD -> NORMALIZE -> FC1 -> FC1_B -> RELU -> FC2 -> FC2_B -> ARGMAX -> DONE_S
// Critical: Explicit clear at IDLE to eliminate mathematical residue
// =============================================================================

module control_fsm (
    // Clock and Reset
    input  wire              clk,
    input  wire              rst_n,

    // Control Inputs
    input  wire              start,          // Start classification
    input  wire              feat_valid,      // Features ready from Feature Engine
    input  wire              apb_enable,      // Enable from APB CSR

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

    // =============================================================================
    // State Registers
    // =============================================================================
    reg [3:0] state;
    reg [3:0] next_state;

    // Counter for multi-cycle operations
    reg [9:0] cnt;           // 10-bit counter for timing
    reg       cnt_enable;     // Counter enable

    // =============================================================================
    // FSM Sequential Logic
    // =============================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state          <= S_IDLE;
            cnt            <= 10'd0;
            cnt_enable     <= 1'b0;
            current_state  <= S_IDLE;

            // Clear all control signals
            fsm_idle        <= 1'b1;
            window_en       <= 1'b0;
            feature_start   <= 1'b0;
            feature_read_en <= 1'b0;
            mlp_start       <= 1'b0;
            mlp_valid      <= 1'b0;
            uart_send      <= 1'b0;
            done           <= 1'b0;

        end else begin
            current_state <= state;

            // Counter logic
            if (cnt_enable) begin
                cnt <= cnt + 10'd1;
            end else begin
                cnt <= 10'd0;
            end

            // State transition
            state <= next_state;

            // Default outputs
            fsm_idle        <= 1'b0;
            feature_start   <= 1'b0;
            feature_read_en <= 1'b0;
            uart_send      <= 1'b0;
            cnt_enable     <= 1'b0;

            case (state)
                // =============================================================
                // IDLE: Wait for start, clear all registers
                // =============================================================
                S_IDLE: begin
                    fsm_idle        <= 1'b1;
                    window_en       <= 1'b0;
                    mlp_start       <= 1'b0;
                    mlp_valid       <= 1'b0;
                    done            <= 1'b0;
                    cnt_enable      <= 1'b0;

                    if (start && apb_enable) begin
                        next_state <= S_LOAD;
                    end else begin
                        next_state <= S_IDLE;
                    end
                end

                // =============================================================
                // LOAD: Load features from Feature Engine
                // =============================================================
                S_LOAD: begin
                    window_en       <= 1'b1;
                    feature_start   <= 1'b1;
                    cnt_enable      <= 1'b1;

                    if (cnt == 10'd1) begin
                        feature_start <= 1'b0;
                    end

                    // Wait for features to be ready
                    if (feat_valid) begin
                        next_state <= S_NORM;
                        cnt_enable <= 1'b0;
                    end else begin
                        next_state <= S_LOAD;
                    end
                end

                // =============================================================
                // NORMALIZE: Normalize features with mean and scale
                // =============================================================
                S_NORM: begin
                    mlp_valid <= 1'b1;   // Features are valid for MLP
                    cnt_enable <= 1'b1;

                    // Normalization takes 1 cycle per feature (12 features)
                    if (cnt == 10'd12) begin
                        next_state <= S_FC1;
                        cnt_enable <= 1'b0;
                    end else begin
                        next_state <= S_NORM;
                    end
                end

                // =============================================================
                // FC1: Fully Connected Layer 1 (12 inputs -> 8 outputs)
                // MAC operations: 96 cycles
                // =============================================================
                S_FC1: begin
                    mlp_start   <= 1'b1;
                    cnt_enable  <= 1'b1;

                    if (cnt == 10'd96) begin
                        next_state <= S_FC1_B;
                        cnt_enable <= 1'b0;
                    end else begin
                        next_state <= S_FC1;
                    end
                end

                // =============================================================
                // FC1_B: Add biases to FC1 outputs
                // =============================================================
                S_FC1_B: begin
                    cnt_enable <= 1'b1;

                    if (cnt == 10'd8) begin
                        next_state <= S_RELU;
                        cnt_enable <= 1'b0;
                    end else begin
                        next_state <= S_FC1_B;
                    end
                end

                // =============================================================
                // RELU: Apply ReLU activation
                // =============================================================
                S_RELU: begin
                    cnt_enable <= 1'b1;

                    if (cnt == 10'd8) begin
                        next_state <= S_FC2;
                        cnt_enable <= 1'b0;
                    end else begin
                        next_state <= S_RELU;
                    end
                end

                // =============================================================
                // FC2: Fully Connected Layer 2 (8 inputs -> 4 outputs)
                // MAC operations: 32 cycles
                // =============================================================
                S_FC2: begin
                    cnt_enable <= 1'b1;

                    if (cnt == 10'd32) begin
                        next_state <= S_FC2_B;
                        cnt_enable <= 1'b0;
                    end else begin
                        next_state <= S_FC2;
                    end
                end

                // =============================================================
                // FC2_B: Add biases to FC2 outputs
                // =============================================================
                S_FC2_B: begin
                    cnt_enable <= 1'b1;

                    if (cnt == 10'd4) begin
                        next_state <= S_ARGMAX;
                        cnt_enable <= 1'b0;
                    end else begin
                        next_state <= S_FC2_B;
                    end
                end

                // =============================================================
                // ARGMAX: Find maximum output
                // =============================================================
                S_ARGMAX: begin
                    cnt_enable <= 1'b1;

                    if (cnt == 10'd4) begin
                        next_state <= S_DONE;
                        cnt_enable <= 1'b0;
                    end else begin
                        next_state <= S_ARGMAX;
                    end
                end

                // =============================================================
                // DONE: Classification complete, send result
                // =============================================================
                S_DONE: begin
                    done       <= 1'b1;
                    uart_send  <= 1'b1;

                    // Return to IDLE after done is acknowledged
                    if (!start) begin
                        next_state <= S_IDLE;
                    end else begin
                        next_state <= S_DONE;
                    end
                end

                default: next_state <= S_IDLE;
            endcase
        end
    end

    // =============================================================================
    // Read Address Generation (for Window Buffer)
    // =============================================================================
    assign read_addr = (state == S_LOAD) ? cnt[8:0] : 9'd0;

    // =============================================================================
    // Next State Debug Output
    // =============================================================================
    always @(posedge clk) begin
        next_state_debug <= next_state;
    end

endmodule
