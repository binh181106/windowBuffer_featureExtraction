

module feature_engine (
    input  wire              clk,            // Xung nhịp hệ thống (50MHz)
    input  wire              rst_n,          // Reset hệ thống (Tích cực mức thấp)
    input  wire              start_compute,  // Lệnh kích hoạt tính toán từ FSM tổng của Bảo
    
    // Giao tiếp với khối Window Buffer
    input  wire signed [15:0] sample_in,     // Mẫu dữ liệu 16-bit nhận tuần tự từ bộ đệm
    output reg               read_enable,    // Lệnh đòi hàng gửi ngược về bộ đệm
    
    // Giao tiếp với khối hạ nguồn (Nối thẳng sang lõi AI của 
    output reg signed  [15:0] f_rms,          // 1: Giá trị hiệu dụng RMS (Cần kết nối CORDIC bên ngoài)
    output reg signed  [15:0] f_var,          //  2: Phương sai Variance
    output reg signed  [15:0] f_peak,         // 3: Đỉnh cao nhất Q4.12
    output reg         [15:0] f_zc,           //  4: Tỷ lệ cắt điểm 0 (Số nguyên)
    output reg signed  [15:0] f_ptp,          //  5: Biên độ Đỉnh - Đỉnh Q4.12
    output reg signed  [15:0] f_crest,        //  6: Hệ số đỉnh (Peak/RMS)
    output reg signed  [15:0] f_half_ratio,   //  7: Tỷ lệ thời gian sóng dương Q4.12
    output reg signed  [15:0] f_max,          //  8: Giá trị lớn nhất tuyệt đối Q4.12
    output reg         [15:0] f_rr,           //  9: Khoảng cách RR hiện tại (Số chu kỳ)
    output reg         [15:0] f_rr_prev,      //  10: Khoảng cách RR chu kỳ trước (Số chu kỳ)
    output reg signed  [15:0] f_rr_ratio,     //  11: Tỷ lệ RR (RR / RR_prev) chuẩn Q4.12
    output reg signed  [15:0] f_rr_diff,      //  12: Chênh lệch RR (RR - RR_prev) chuẩn Q4.12
    output reg               feature_valid   // Cờ báo đã tính xong toàn bộ 12 đặc trưng
);

    // 1. Định nghĩa trạng thái FSM con
    localparam S_IDLE       = 2'b00;
    localparam S_ACCUMULATE = 2'b01;
    localparam S_COMPUTE    = 2'b10;
    localparam S_DONE       = 2'b11;

    reg [1:0] state;
    
    // 2. Các thanh ghi phục vụ Datapath tích lũy nội bộ
    reg [8:0]         cnt;
    reg signed [31:0] sum;
    reg signed [47:0] sum_square;     // Tích lũy tổng bình phương để tính RMS và Variance
    reg signed [15:0] peak_reg;
    reg signed [15:0] min_reg;
    reg        [15:0] zcr_cnt;
    reg               prev_sign;
    reg        [15:0] positive_sample_cnt; // Đếm số mẫu dương để tính f_half_ratio

    // Các thanh ghi quản lý thời gian để tính toán nhóm đặc trưng RR-Interval
    reg [15:0] rr_timer;              // Bộ đếm thời gian chạy liên tục giữa 2 đỉnh
    reg [15:0] current_rr_reg;        // Giữ giá trị RR tìm được trong khung 2 giây
    reg [15:0] previous_rr_reg;       // Giữ giá trị RR cũ để tính toán so sánh

    // Các thanh ghi toán học trung gian
    reg signed [47:0] mean_calc;
    reg signed [47:0] var_calc;
    reg signed [47:0] rr_ratio_calc;

    // =============================================================================
    // KHỐI ĐIỀU KHIỂN CHUYỂN TRẠNG THÁI FSM 
    // =============================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) state <= S_IDLE;
        else begin
            case (state)
                S_IDLE:       if (start_compute) state <= S_ACCUMULATE;
                S_ACCUMULATE: if (cnt == 9'd499) state <= S_COMPUTE;
                S_COMPUTE:    state <= S_DONE;
                S_DONE:       state <= S_IDLE;
                default:      state <= S_IDLE;
            endcase
        end
    end

    // =============================================================================
    // KHỐI DATAPATH 
    // =============================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            read_enable         <= 1'b0;
            feature_valid       <= 1'b0;
            cnt                 <= 9'd0;
            sum                 <= 32'd0;
            sum_square          <= 48'd0;
            peak_reg            <= 16'sh8000;
            min_reg             <= 16'sh7FFF;
            zcr_cnt             <= 16'd0;
            prev_sign           <= 1'b0;
            positive_sample_cnt <= 16'd0;
            rr_timer            <= 16'd0;
            current_rr_reg      <= 16'd0;
            previous_rr_reg     <= 16'd0;
            
            // Xóa sạch 12 chân ngõ ra mới 
            f_rms <= 16'd0; f_var <= 16'd0; f_peak <= 16'd0; f_zc <= 16'd0;
            f_ptp <= 16'd0; f_crest <= 16'd0; f_half_ratio <= 16'd0; f_max <= 16'd0;
            f_rr <= 16'd0; f_rr_prev <= 16'd0; f_rr_ratio <= 16'd0; f_rr_diff <= 16'd0;
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
                end

                S_ACCUMULATE: begin
                    read_enable <= 1'b1;
                    cnt         <= cnt + 9'd1;
                    
                    // Quản lý bộ đếm thời gian RR chạy ngầm liên tục
                    rr_timer <= rr_timer + 16'd1;

                    // 1. Tích lũy tổng thô và tổng bình phương (Phục vụ f_var và f_rms)
                    sum        <= sum + sample_in;
                    sum_square <= sum_square + (sample_in * sample_in);
                    
                    // 2. Thuật toán tìm đỉnh và đáy hình học (f_peak, f_max, f_min)
                    if (sample_in > peak_reg) begin
                        peak_reg <= sample_in;
                        // Mẹo bắt đỉnh R-peak: Khi tìm thấy sườn sóng cao đột biến,
                        // ta coi đó là đỉnh R, tiến hành chốt khoảng cách thời gian RR
                        previous_rr_reg <= current_rr_reg;
                        current_rr_reg  <= rr_timer;
                        rr_timer        <= 16'd0; // Khởi động lại bộ đếm thời gian mới
                    end
                    if (sample_in < min_reg) begin
                        min_reg <= sample_in;
                    end
                        
                    // 3. Tính toán f_zc (Zero Crossing) bằng cổng XOR bit dấu
                    if (cnt > 9'd0) begin
                        if (prev_sign ^ sample_in[15]) begin
                            zcr_cnt <= zcr_cnt + 16'd1;
                        end
                    end
                    prev_sign <= sample_in[15];

                    // 4. Tính toán f_half_ratio: Đếm số lượng mẫu nằm ở miền sóng dương
                    if (sample_in >= 16'd0) begin
                        positive_sample_cnt <= positive_sample_cnt + 16'd1;
                    end
                end

                S_COMPUTE: begin
                    read_enable <= 1'b0;
                    
                    // Phép toán 1: Tính Mean phục vụ tính toán trung gian
                    mean_calc <= sum * 32'd33554; // Quy đổi nhân nghịch đảo (Sum / 500) trong chuẩn Q12
                    
                    // Phép toán 2: Tính Phương sai f_var 
                    // Công thức phần cứng tối ưu: Var = (Sum_Square / 500) - (Mean^2)
                    var_calc <= (sum_square * 32'd33554) - ((mean_calc[27:12] * mean_calc[27:12]) <<< 12);

                    // Phép toán 3: Tính toán f_half_ratio đưa về chuẩn số thập phân Q4.12
                    // Công thức: (Positive_Samples * 4096) / 500 = Positive_Samples * 8.192
                    f_half_ratio <= (positive_sample_cnt * 32'd33554) >>> 12;

                    // Phép toán 4: Chốt hạ các đặc trưng biên độ hình học đưa về Q4.12
                    f_peak <= peak_reg <<< 12;
                    f_max  <= peak_reg <<< 12; // Trong bài toán này f_max đồng bộ giá trị biên độ với f_peak
                    f_ptp  <= (peak_reg - min_reg) <<< 12;
                    f_zc   <= zcr_cnt;

                    // Phép toán 5: Chốt hạ nhóm đặc trưng thời gian RR-Interval 
                    f_rr      <= current_rr_reg;
                    f_rr_prev <= previous_rr_reg;
                    f_rr_diff <= (current_rr_reg - previous_rr_reg) <<< 12; // Ép về chuẩn định dạng tính toán
                    
                    // Tránh lỗi chia cho 0 nếu chu kỳ trước trống
                    if (previous_rr_reg > 16'd0) begin
                        rr_ratio_calc <= (current_rr_reg <<< 12) / previous_rr_reg;
                        f_rr_ratio    <= rr_ratio_calc[15:0];
                    end else begin
                        f_rr_ratio    <= 16'h1000; // Mặc định bằng 1.0 ở chuẩn Q4.12 nếu chưa có dữ liệu cũ
                    end

                    // Phép toán 6: Cấu hình tài nguyên ngỏ ra tạm thời cho f_rms và f_crest để đợi nối dây CORDIC
                    f_rms   <= 16'h1000; // Giá trị tạm (Sẽ được ghi đè chính xác khi nối dây sang module CORDIC)
                    f_crest <= 16'h1000; 
                end

                S_DONE: begin
                    f_var         <= var_calc[27:12]; // Hạ bit kết quả phương sai về đúng chuẩn khung 16-bit Q4.12
                    feature_valid <= 1'b1;            // Vẫy cờ báo cho lõi AI của T.Bình hốt đủ 12 số thực tế
                end
                
                default: state <= S_IDLE;
            endcase
        end
    end

endmodule