`timescale 1ns / 1ps

module feature_engine (
    input  wire              clk,            
    input  wire              rst_n,          
    input  wire              start_compute,  
    
    input  wire signed [15:0] sample_in,     
    output reg               read_enable,    
    
    output reg signed  [15:0] f_rms,          
    output reg signed  [15:0] f_var,          
    output reg signed  [15:0] f_peak,         
    output reg         [15:0] f_zc,           
    output reg signed  [15:0] f_ptp,          
    output reg signed  [15:0] f_crest,        
    output reg signed  [15:0] f_half_ratio,   
    output reg signed  [15:0] f_max,          
    output reg         [15:0] f_rr,           
    output reg         [15:0] f_rr_prev,      
    output reg signed  [15:0] f_rr_ratio,     
    output reg signed  [15:0] f_rr_diff,      
    output reg               feature_valid   
);

    // =============================================================================
    // 1. FSM STATES
    // =============================================================================
    localparam S_IDLE         = 4'd0;
    localparam S_ACCUMULATE   = 4'd1;
    localparam S_CALC_BASE    = 4'd2; 
    localparam S_CALC_VAR     = 4'd3; 
    localparam S_START_MATH_1 = 4'd4; 
    localparam S_WAIT_MATH_1  = 4'd5; 
    localparam S_START_MATH_2 = 4'd6; 
    localparam S_WAIT_MATH_2  = 4'd7; 
    localparam S_DONE         = 4'd8;

    reg [3:0] state;
    
    // =============================================================================
    // 2. DATAPATH REGISTERS
    // =============================================================================
    reg [8:0]         cnt;
    reg signed [31:0] sum;
    reg signed [47:0] sum_square;     
    reg signed [15:0] peak_reg;
    reg signed [15:0] min_reg;
    reg        [15:0] zcr_cnt;
    reg               prev_sign;
    reg        [15:0] positive_sample_cnt;

    reg [15:0] rr_timer;
    reg [15:0] current_rr_reg;
    reg [15:0] previous_rr_reg;

    reg signed [47:0] mean_calc;
    reg signed [47:0] var_calc;

    // =============================================================================
    // 3. MATH MODULE INTERFACES
    // =============================================================================
    reg         div_start;
    reg  [31:0] div_dividend;
    reg  [15:0] div_divisor;
    wire [31:0] div_quotient;
    wire [15:0] div_remainder;
    wire        div_done;

    restoring_divider u_divider (
        .clk(clk),
        .rst_n(rst_n),
        .start(div_start),
        .dividend(div_dividend),
        .divisor(div_divisor),
        .quotient(div_quotient),
        .remainder(div_remainder),
        .done(div_done)
    );

    reg         sqrt_start;
    reg  [31:0] sqrt_radicand;
    wire [15:0] sqrt_root;
    wire        sqrt_done;

    iterative_sqrt u_sqrt (
        .clk(clk),
        .rst_n(rst_n),
        .start(sqrt_start),
        .radicand(sqrt_radicand),
        .root(sqrt_root),
        .done(sqrt_done)
    );

    // =============================================================================
    // MAIN FSM & DATAPATH
    // =============================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            read_enable <= 1'b0; feature_valid <= 1'b0;
            cnt <= 9'd0; sum <= 32'd0; sum_square <= 48'd0;
            peak_reg <= 16'sh8000; min_reg <= 16'sh7FFF;
            zcr_cnt <= 16'd0; prev_sign <= 1'b0; positive_sample_cnt <= 16'd0;
            rr_timer <= 16'd0; current_rr_reg <= 16'd0; previous_rr_reg <= 16'd0;
            
            f_rms <= 16'd0; f_var <= 16'd0; f_peak <= 16'd0; f_zc <= 16'd0;
            f_ptp <= 16'd0; f_crest <= 16'd0; f_half_ratio <= 16'd0; f_max <= 16'd0;
            f_rr <= 16'd0; f_rr_prev <= 16'd0; f_rr_ratio <= 16'd0; f_rr_diff <= 16'd0;

            div_start <= 1'b0; sqrt_start <= 1'b0;
        end 
        else begin
            case (state)
                // ---------------------------------------------------------------------
                // TRẠNG THÁI: S_IDLE
                // CHỨC NĂNG: Chờ lệnh bắt đầu, reset toàn bộ các thanh ghi tích lũy.
                // [INPUT] : start_compute (từ tổng FSM)
                // [OUTPUT]: Các thanh ghi nội bộ (cnt, sum, peak, min...) bị xóa về 0.
                // ---------------------------------------------------------------------
                S_IDLE: begin
                    read_enable <= 1'b0; feature_valid <= 1'b0;
                    cnt <= 9'd0; sum <= 32'd0; sum_square <= 48'd0;
                    peak_reg <= 16'sh8000; min_reg <= 16'sh7FFF;
                    zcr_cnt <= 16'd0; positive_sample_cnt <= 16'd0;
                    div_start <= 1'b0; sqrt_start <= 1'b0;
                    
                    if (start_compute) state <= S_ACCUMULATE;
                end

                // ---------------------------------------------------------------------
                // TRẠNG THÁI: S_ACCUMULATE
                // CHỨC NĂNG: Thu thập 500 mẫu dữ liệu, tìm đỉnh/đáy, đếm các biến cố.
                // [INPUT] : sample_in (từ Window Buffer), các biến nội bộ (cnt, rr_timer)
                // [OUTPUT]: sum, sum_square, peak_reg, min_reg, zcr_cnt, positive_sample_cnt, 
                //           current_rr_reg, previous_rr_reg, read_enable
                // ---------------------------------------------------------------------
                S_ACCUMULATE: begin
                    read_enable <= 1'b1;
                    cnt <= cnt + 9'd1;
                    rr_timer <= rr_timer + 16'd1;

                    sum <= sum + sample_in;
                    sum_square <= sum_square + (sample_in * sample_in);
                    
                    if (sample_in > peak_reg) begin
                        peak_reg <= sample_in;
                        previous_rr_reg <= current_rr_reg;
                        current_rr_reg  <= rr_timer;
                        rr_timer        <= 16'd0; 
                    end
                    if (sample_in < min_reg) begin
                        min_reg <= sample_in;
                    end
                        
                    if (cnt > 9'd0) begin
                        if (prev_sign ^ sample_in[15]) zcr_cnt <= zcr_cnt + 16'd1;
                    end
                    prev_sign <= sample_in[15];

                    if (sample_in >= 16'd0) positive_sample_cnt <= positive_sample_cnt + 16'd1;

                    if (cnt == 9'd499) state <= S_CALC_BASE;
                end

                // ---------------------------------------------------------------------
                // TRẠNG THÁI: S_CALC_BASE
                // CHỨC NĂNG: Tính mean và các đặc trưng không cần chia/căn phức tạp.
                // [INPUT] : sum, positive_sample_cnt, peak_reg, min_reg, zcr_cnt, 
                //           current_rr_reg, previous_rr_reg
                // [OUTPUT]: mean_calc, f_half_ratio, f_peak, f_max, f_ptp, f_zc, 
                //           f_rr, f_rr_prev, f_rr_diff
                // ---------------------------------------------------------------------
                S_CALC_BASE: begin
                    read_enable <= 1'b0;
                    mean_calc <= sum * 32'd33554; 
                    
                    f_half_ratio <= (positive_sample_cnt * 32'd33554) >>> 12;
                    f_peak       <= peak_reg <<< 12;
                    f_max        <= peak_reg <<< 12; 
                    f_ptp        <= (peak_reg - min_reg) <<< 12;
                    f_zc         <= zcr_cnt;
                    f_rr         <= current_rr_reg;
                    f_rr_prev    <= previous_rr_reg;
                    f_rr_diff    <= (current_rr_reg - previous_rr_reg) <<< 12;

                    state <= S_CALC_VAR;
                end

                // ---------------------------------------------------------------------
                // TRẠNG THÁI: S_CALC_VAR
                // CHỨC NĂNG: Tính toán phương sai (Cần đợi mean_calc từ state trước).
                // [INPUT] : sum_square, mean_calc
                // [OUTPUT]: var_calc
                // ---------------------------------------------------------------------
                S_CALC_VAR: begin
                    var_calc <= (sum_square * 32'd33554) - ((mean_calc[27:12] * mean_calc[27:12]) <<< 12);
                    state <= S_START_MATH_1;
                end

                // ---------------------------------------------------------------------
                // TRẠNG THÁI: S_START_MATH_1
                // CHỨC NĂNG: Chốt f_var và đẩy data vào module Divider và Sqrt lần 1.
                // [INPUT] : var_calc, current_rr_reg, previous_rr_reg
                // [OUTPUT]: f_var, sqrt_start, sqrt_radicand, div_start, div_dividend, div_divisor
                // ---------------------------------------------------------------------
                S_START_MATH_1: begin
                    f_var <= var_calc[27:12];

                    sqrt_radicand <= {var_calc[27:12], 12'd0}; 
                    sqrt_start    <= 1'b1;

                    if (previous_rr_reg > 16'd0) begin
                        div_dividend <= (current_rr_reg <<< 12);
                        div_divisor  <= previous_rr_reg;
                        div_start    <= 1'b1;
                    end else begin
                        f_rr_ratio   <= 16'h1000; 
                    end

                    state <= S_WAIT_MATH_1;
                end

                // ---------------------------------------------------------------------
                // TRẠNG THÁI: S_WAIT_MATH_1
                // CHỨC NĂNG: Chờ phần cứng toán học tính xong RMS và tỷ lệ RR.
                // [INPUT] : sqrt_done, sqrt_root, div_done, div_quotient
                // [OUTPUT]: f_rms, f_rr_ratio, tắt lệnh start (sqrt_start, div_start = 0)
                // ---------------------------------------------------------------------
                S_WAIT_MATH_1: begin
                    sqrt_start <= 1'b0;
                    div_start  <= 1'b0;

                    if (sqrt_done && (div_done || previous_rr_reg == 16'd0)) begin
                        f_rms <= sqrt_root;
                        if (previous_rr_reg > 16'd0) f_rr_ratio <= div_quotient[15:0];
                        
                        state <= S_START_MATH_2;
                    end
                end

                // ---------------------------------------------------------------------
                // TRẠNG THÁI: S_START_MATH_2
                // CHỨC NĂNG: Đẩy data vào module Divider lần 2 để tính Crest Factor.
                // [INPUT] : f_peak, f_rms
                // [OUTPUT]: div_start, div_dividend, div_divisor (hoặc chốt f_crest bằng 0)
                // ---------------------------------------------------------------------
                S_START_MATH_2: begin
                    if (f_rms > 16'd0) begin
                        div_dividend <= (f_peak <<< 12);
                        div_divisor  <= f_rms;
                        div_start    <= 1'b1;
                        state        <= S_WAIT_MATH_2;
                    end else begin
                        f_crest <= 16'd0; 
                        state   <= S_DONE;
                    end
                end

                // ---------------------------------------------------------------------
                // TRẠNG THÁI: S_WAIT_MATH_2
                // CHỨC NĂNG: Chờ phần cứng Divider tính xong Crest Factor.
                // [INPUT] : div_done, div_quotient
                // [OUTPUT]: f_crest, tắt lệnh start (div_start = 0)
                // ---------------------------------------------------------------------
                S_WAIT_MATH_2: begin
                    div_start <= 1'b0;
                    if (div_done) begin
                        f_crest <= div_quotient[15:0];
                        state   <= S_DONE;
                    end
                end

                // ---------------------------------------------------------------------
                // TRẠNG THÁI: S_DONE
                // CHỨC NĂNG: Báo hiệu tính toán hoàn tất, AI có thể đọc 12 features.
                // [INPUT] : (Không có tín hiệu logic phụ thuộc, tự động chuyển về S_IDLE)
                // [OUTPUT]: feature_valid = 1
                // ---------------------------------------------------------------------
                S_DONE: begin
                    feature_valid <= 1'b1; 
                    state <= S_IDLE;
                end
                
                default: state <= S_IDLE;
            endcase
        end
    end
endmodule