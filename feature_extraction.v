`timescale 1ns / 1ps

module feature_engine (
    input  wire              clk,            
    input  wire              rst_n,          
    input  wire              start_compute,  
    
    // Giao tiếp với khối Window Buffer (Chuẩn 512 mẫu)
    input  wire signed [15:0] sample_in,     
    output reg               read_enable,    
    
    // Giao tiếp với khối hạ nguồn AI của T.Bình (Đầu ra 32-bit rộng rãi)
    output reg signed  [31:0] f_rms,          
    output reg signed  [31:0] f_var,          
    output reg signed  [31:0] f_peak,         
    output reg         [31:0] f_zc,           
    output reg signed  [31:0] f_ptp,          
    output reg signed  [31:0] f_crest,        
    output reg signed  [31:0] f_half_ratio,   
    output reg signed  [31:0] f_max,          
    output reg         [31:0] f_rr,           
    output reg         [31:0] f_rr_prev,      
    output reg signed  [31:0] f_rr_ratio,     
    output reg signed  [31:0] f_rr_diff,      
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
    reg [8:0]         cnt; // Đủ để đếm từ 0 đến 511 (Chuẩn 512 mẫu)
    reg signed [31:0] sum;
    reg signed [47:0] sum_square;     
    reg signed [15:0] peak_reg;
    reg signed [15:0] min_reg;
    reg        [15:0] zcr_cnt;
    reg               prev_sign;
    reg        [15:0] positive_sample_cnt;

    // Các thanh ghi quản lý thời gian đo khoảng cách RR
    reg signed [15:0] sample_in_delayed;
    reg        [15:0] rr_timer;
    reg        [15:0] current_rr_reg;
    reg        [15:0] previous_rr_reg;

    reg signed [31:0] mean_calc; 
    reg signed [52:0] var_calc; 

    // =============================================================================
    // 3. MATH MODULE INTERFACES
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
            sample_in_delayed <= 16'd0;
            
            f_rms <= 32'd0; f_var <= 32'd0; f_peak <= 32'd0; f_zc <= 32'd0;
            f_ptp <= 32'd0; f_crest <= 32'd0; f_half_ratio <= 32'd0; f_max <= 32'd0;
            f_rr <= 32'd0; f_rr_prev <= 32'd0; f_rr_ratio <= 32'd0; f_rr_diff <= 32'd0;

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
                    
                    // SỬA LỖI LẬP TRÌNH ĐỘ TRỄ RAM: Đòi hàng trước 1 chu kỳ ngay tại IDLE
                    if (start_compute) begin
                        read_enable <= 1'b1;
                        state       <= S_ACCUMULATE;
                    end
                end

                S_ACCUMULATE: begin
                    cnt               <= cnt + 9'd1;
                    rr_timer          <= rr_timer + 16'd1;
                    sample_in_delayed <= sample_in;

                    // Tích lũy dữ liệu đồng bộ 100% không dính rác RAM
                    sum        <= sum + $signed(sample_in);
                    sum_square <= sum_square + ($signed(sample_in) * $signed(sample_in));
                    
                    // Mạch tìm đỉnh/đáy toàn cục
                    if (sample_in > peak_reg) peak_reg <= sample_in;
                    if (sample_in < min_reg)  min_reg  <= sample_in;
                        
                    // Mạch dò đỉnh cục bộ thực tế để tính khoảng cách RR
                    if ((sample_in_delayed > 16'd15000) && (sample_in < sample_in_delayed)) begin
                        if (rr_timer > 16'd50) begin
                            previous_rr_reg <= current_rr_reg;
                            current_rr_reg  <= rr_timer;
                            rr_timer        <= 16'd0; 
                        end
                    end

                    // Đếm Zero Crossing và Half Ratio
                    if (cnt > 9'd0) begin
                        if (prev_sign ^ sample_in[15]) zcr_cnt <= zcr_cnt + 16'd1;
                    end
                    prev_sign <= sample_in[15];

                    if (sample_in >= 16'sd0) positive_sample_cnt <= positive_sample_cnt + 16'd1;

                    // Khóa đường dây đòi hàng sớm 1 chu kỳ khi sắp chạm đỉnh 511
                    if (cnt == 9'd510) begin
                        read_enable <= 1'b0;
                    end

                    // SỬA LỖI 1: Đếm chuẩn khít khao đủ 512 mẫu (từ 0 đến 511)
                    if (cnt == 9'd511) begin
                        state <= S_CALC_BASE;
                    end
                end

                S_CALC_BASE: begin
                    // SỬA LỖI 2: Áp dụng toán dịch bit siêu nhẹ của cấu trúc 512 mẫu
                    mean_calc    <= $signed(sum) <<< 3; // Lấy Sum * 4096 / 512 = Sum * 8
                    f_half_ratio <= $signed({16'd0, positive_sample_cnt} <<< 3);
                    
                    f_peak       <= $signed({{16{peak_reg[15]}}, peak_reg}) <<< 12;
                    f_max        <= $signed({{16{peak_reg[15]}}, peak_reg}) <<< 12; 
                    f_ptp        <= $signed(({{16{peak_reg[15]}}, peak_reg} - {{16{min_reg[15]}}, min_reg}) <<< 12);
                    f_zc         <= {16'd0, zcr_cnt};
                    
                    // Nhóm đặc trưng thời gian RR tiền xử lý thu nhỏ nhân 8
                    f_rr         <= {16'd0, current_rr_reg} <<< 3;
                    f_rr_prev    <= {16'd0, previous_rr_reg} <<< 3;
                    f_rr_diff    <= $signed(({16'd0, current_rr_reg} - {16'd0, previous_rr_reg}) <<< 3);

                    state <= S_CALC_VAR;
                end

                S_CALC_VAR: begin
                    // SỬA LỖI TOÁN HỌC: Cân bằng tuyệt đối hai vế về chuẩn Q24 rồi trừ thẳng hàng
                    var_calc <= (sum_square <<< 3) - ((mean_calc * mean_calc) >>> 12);
                    state    <= S_START_MATH_1;
                end

                S_START_MATH_1: begin
                    // Trích xuất f_var chuẩn xác từ vùng bit Q24 hạ cấp về Q12
                    f_var <= $signed(var_calc[43:12]);

                    // Đầu vào RMS chính xác là căn bậc hai của Tổng bình phương trung bình
                    sqrt_radicand <= { (sum_square <<< 3), 12'd0 }; // Đẩy lên Q36 để khai căn ra chuẩn Q18
                    sqrt_start    <= 1'b1;

                    if (previous_rr_reg > 16'd0) begin
                        div_dividend <= $signed({{16{current_rr_reg[15]}}, current_rr_reg}) <<< 12;
                        div_divisor  <= {16'd0, previous_rr_reg};
                        div_start    <= 1'b1;
                    end else begin
                        f_rr_ratio   <= 32'h1000; 
                    end

                    state <= S_WAIT_MATH_1;
                end

                S_WAIT_MATH_1: begin
                    sqrt_start <= 1'b0;
                    div_start  <= 1'b0;

                    if (sqrt_done && (div_done || previous_rr_reg == 16'd0)) begin
                        f_rms <= $signed(sqrt_root[29:14]); 
                        if (previous_rr_reg > 16'd0) f_rr_ratio <= $signed(div_quotient);
                        
                        state <= S_START_MATH_2;
                    end
                end

                S_START_MATH_2: begin
                    if (f_rms > 32'd0) begin
                        div_dividend <= f_peak;
                        div_divisor  <= f_rms;
                        div_start    <= 1'b1;
                        state        <= S_WAIT_MATH_2;
                    end else begin
                        f_crest      <= 32'd0; 
                        state        <= S_DONE;
                    end
                end

                S_WAIT_MATH_2: begin
                    div_start <= 1'b0; 
                    if (div_done) begin
                        f_crest <= $signed(div_quotient);
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