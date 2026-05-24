`timescale 1ns / 1ps

// =============================================================================
// MODULE: feature_engine (Bản chuẩn hóa 16-bit Q4.12 toàn diện)
// Thiết kế: Lê Tôn Thịnh - Nhóm FPTU_ICeek
// Tối ưu hóa: Đồng bộ khít khao 512 mẫu ở tần số 256Hz với Window Buffer
// =============================================================================

module feature_engine (
    input  wire              clk,            
    input  wire              rst_n,          
    input  wire              start_compute,  
    
    // Giao tiếp với khối Window Buffer (Chuẩn 512 mẫu)
    input  wire signed [15:0] sample_in,     
    output reg               read_enable,    
    
    // CHỐT HẠ GIAO TIẾP 16-BIT CHUẨN Q4.12 ĐÚNG THEO PROPOSAL CỦA NHÓM
    output reg signed  [15:0] f_rms,          
    output reg signed  [15:0] f_var,          
    output reg signed  [15:0] f_peak,         
    output reg         [15:0] f_zc,           // Số đếm nguyên không dấu 16-bit
    output reg signed  [15:0] f_ptp,          
    output reg signed  [15:0] f_crest,        
    output reg signed  [15:0] f_half_ratio,   
    output reg signed  [15:0] f_max,          
    output reg         [15:0] f_rr,           // Số chu kỳ mẫu nguyên 16-bit
    output reg         [15:0] f_rr_prev,      // Số chu kỳ mẫu nguyên 16-bit
    output reg signed  [15:0] f_rr_ratio,     
    output reg signed  [15:0] f_rr_diff,      
    output reg               feature_valid   
);

    // =============================================================================
    // 1. FSM STATES (4-bit mã hóa trạng thái)
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
    // 2. INTERNAL DATAPATH REGISTERS (Bảo toàn độ rộng bit lớn để tính toán chống tràn)
    // =============================================================================
    reg [8:0]         cnt; 
    reg signed [31:0] sum;
    reg signed [47:0] sum_square;     
    reg signed [15:0] peak_reg;
    reg signed [15:0] min_reg;
    reg        [15:0] zcr_cnt;
    reg               prev_sign;
    reg        [15:0] positive_sample_cnt;

    // Các thanh ghi quản lý thời gian đo khoảng cách RR giữa các đỉnh tim
    reg signed [15:0] sample_in_delayed;
    reg        [15:0] rr_timer;
    reg        [15:0] current_rr_reg;
    reg        [15:0] previous_rr_reg;

    reg signed [31:0] mean_calc; 
    reg signed [47:0] var_calc;  // Rút gọn từ 52 về 47 bit vì toán dịch bit 512 đã rất sạch

    // =============================================================================
    // 3. MATH MODULE INTERFACES (Giao tiếp lõi tính toán tuần tự)
    // =============================================================================
    reg         div_start;
    reg  [31:0] div_dividend;
    reg  [31:0] div_divisor;
    wire [31:0] div_quotient;
    wire [31:0] div_remainder;
    wire        div_done;

    restoring_divider u_divider (
        .clk(clk), .rst_n(rst_n),
        .start(div_start), .dividend(div_dividend), .divisor(div_divisor),
        .quotient(div_quotient), .remainder(div_remainder), .done(div_done)
    );

    reg         sqrt_start;
    reg  [63:0] sqrt_radicand;
    wire [31:0] sqrt_root;
    wire        sqrt_done;

    iterative_sqrt u_sqrt (
        .clk(clk), .rst_n(rst_n),
        .start(sqrt_start), .radicand(sqrt_radicand),
        .root(sqrt_root), .done(sqrt_done)
    );

    // =============================================================================
    // MAIN FSM & DATAPATH CORRECTION
    // =============================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            read_enable <= 1'b0; feature_valid <= 1'b0;
            cnt <= 9'd0; sum <= 32'd0; sum_square <= 48'd0;
            peak_reg <= 16'sh8000; min_reg <= 16'sh7FFF;
            zcr_cnt <= 16'd0; prev_sign <= 1'b0; positive_sample_cnt <= 16'd0;
            rr_timer <= 16'd0; current_rr_reg <= 16'd0; previous_rr_reg <= 16'd0;
            sample_in_delayed <= 16'd0;
            
            f_rms <= 16'd0; f_var <= 16'd0; f_peak <= 16'd0; f_zc <= 16'd0;
            f_ptp <= 16'd0; f_crest <= 16'd0; f_half_ratio <= 16'd0; f_max <= 16'd0;
            f_rr <= 16'd0; f_rr_prev <= 16'd0; f_rr_ratio <= 16'd0; f_rr_diff <= 16'd0;

            div_start <= 1'b0; sqrt_start <= 1'b0;
            mean_calc <= 32'd0; var_calc <= 48'd0;
        end 
        else begin
            case (state)
                S_IDLE: begin
                    read_enable   <= 1'b0; 
                    feature_valid <= 1'b0;
                    cnt           <= 9'd0; 
                    sum           <= 32'd0; 
                    sum_square    <= 48'd0;
                    peak_reg      <= 16'sh8000; 
                    min_reg       <= 16'sh7FFF;
                    zcr_cnt       <= 16'd0; 
                    positive_sample_cnt <= 16'd0;
                    div_start     <= 1'b0; 
                    sqrt_start    <= 1'b0;
                    
                    if (start_compute) begin
                        read_enable <= 1'b1;
                        state       <= S_ACCUMULATE;
                    end
                end

                S_ACCUMULATE: begin
                    cnt               <= cnt + 9'd1;
                    rr_timer          <= rr_timer + 16'd1;
                    sample_in_delayed <= sample_in;

                    sum        <= sum + $signed(sample_in);
                    sum_square <= sum_square + ($signed(sample_in) * $signed(sample_in));
                    
                    if (sample_in > peak_reg) peak_reg <= sample_in;
                    if (sample_in < min_reg)  min_reg  <= sample_in;
                        
                    if ((sample_in_delayed > 16'd15000) && (sample_in < sample_in_delayed)) begin
                        if (rr_timer > 16'd50) begin
                            previous_rr_reg <= current_rr_reg;
                            current_rr_reg  <= rr_timer;
                            rr_timer        <= 16'd0; 
                        end
                    end

                    if (cnt > 9'd0) begin
                        if (prev_sign ^ sample_in[15]) zcr_cnt <= zcr_cnt + 16'd1;
                    end
                    prev_sign <= sample_in[15];

                    if (sample_in >= 16'sd0) positive_sample_cnt <= positive_sample_cnt + 16'd1;

                    if (cnt == 9'd510) begin
                        read_enable <= 1'b0;
                    end

                    if (cnt == 9'd511) begin
                        state <= S_CALC_BASE;
                    end
                end

                S_CALC_BASE: begin
                    mean_calc    <= $signed(sum) <<< 3; // Q12 format (Sum * 4096 / 512)
                    f_half_ratio <= $signed(positive_sample_cnt <<< 3); // Chốt thẳng về 16-bit Q4.12
                    
                    // Sửa đổi loại bỏ ghép nối phức tạp, ép thẳng số nguyên thô sang chuẩn Q4.12 bằng cách dịch trái 12 bit
                    f_peak       <= peak_reg <<< 12;
                    f_max        <= peak_reg <<< 12; 
                    f_ptp        <= (peak_reg - min_reg) <<< 12;
                    f_zc         <= zcr_cnt;
                    
                    // Nhóm đặc trưng thời gian RR (Hệ số thu nhỏ tiền xử lý nhân 8)
                    f_rr         <= current_rr_reg <<< 3;
                    f_rr_prev    <= previous_rr_reg <<< 3;
                    f_rr_diff    <= (current_rr_reg - previous_rr_reg) <<< 3;

                    state <= S_CALC_VAR;
                end

                S_CALC_VAR: begin
                    // Tính phương sai chuẩn định dạng Q12
                    var_calc <= (sum_square <<< 3) - ((mean_calc * mean_calc) >>> 12);
                    state    <= S_START_MATH_1;
                end

                S_START_MATH_1: begin
                    // SỬA LỖI TRÍCH BIT: var_calc đã là định dạng Q12, lấy thẳng 16-bit thấp [15:0]
                    f_var <= var_calc[15:0];

                    // Chuẩn bị khai căn để tìm f_rms: Đẩy Q12 lên Q24 bằng cách dịch trái 12 bit để kết quả Sqrt nhả ra đúng chuẩn Q12
                    sqrt_radicand <= (sum_square <<< 3) <<< 12; 
                    sqrt_start    <= 1'b1;

                    if (previous_rr_reg > 16'd0) begin
                        // Đẩy số bị chia lên dạng Q12 thập phân trước khi chia cho số nguyên mẫu số
                        div_dividend <= current_rr_reg <<< 12;
                        div_divisor  <= {16'd0, previous_rr_reg};
                        div_start    <= 1'b1;
                    end else begin
                        f_rr_ratio   <= 16'h1000; // Mặc định bằng 1.0 (chuẩn Q4.12) nếu chưa có chu kỳ cũ
                    end

                    state <= S_WAIT_MATH_1;
                end

                S_WAIT_MATH_1: begin
                    sqrt_start <= 1'b0;
                    div_start  <= 1'b0;

                    if (sqrt_done && (div_done || previous_rr_reg == 16'd0)) begin
                        // SỬA LỖI TRÍCH BIT: u_sqrt nhận đầu vào Q24 nên đầu ra sqrt_root đã nằm khít khhao ở chuẩn Q12
                        f_rms <= sqrt_root[15:0]; 
                        
                        if (previous_rr_reg > 16'd0) begin
                            f_rr_ratio <= div_quotient[15:0]; // Lấy 16-bit thương số chuẩn Q12
                        end
                        
                        state <= S_START_MATH_2;
                    end
                end

                S_START_MATH_2: begin
                    if (f_rms > 16'd0) begin
                        // Chia biến số để tìm Crest Factor: Đẩy tử số f_peak (đã là Q12) dịch trái tiếp 12 bit
                        div_dividend <= f_peak <<< 12;
                        div_divisor  <= {16'd0, f_rms}; // Mẫu số là biến số f_rms chuẩn Q12
                        div_start    <= 1'b1;
                        state        <= S_WAIT_MATH_2;
                    end else begin
                        f_crest      <= 16'd0; 
                        state        <= S_DONE;
                    end
                end

                S_WAIT_MATH_2: begin
                    div_start <= 1'b0; 
                    if (div_done) begin
                        f_crest <= div_quotient[15:0]; // Thương số thu được tự động trả về dạng Q12 mượt mà
                        state   <= S_DONE;
                    end
                end

                S_DONE: begin
                    feature_valid <= 1'b1; 
                    state         <= S_IDLE;
                end
                
                default: state <= S_IDLE;
            endcase
        end
    end
endmodule
