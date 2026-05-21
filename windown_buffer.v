// =============================================================================
// Tên Module: window_buffer (Bản tối ưu hóa 512 mẫu - Chuẩn công nghiệp)
// Chức năng: Lưu trữ 512 mẫu ECG, tự động quay đầu vòng tròn tốn 0% logic so sánh
// Overlap 50%: Lần đầu cần 512 mẫu, các lần sau chỉ cần thêm 256 mẫu mới
// =============================================================================

module window_buffer (
    input  wire              clk,            // Xung nhịp hệ thống (50MHz)
    input  wire              rst_n,          // Reset tích cực mức thấp
    
    // Giao tiếp với ADC (Tần số mới: 256Hz)
    input  wire signed [15:0] sample_in,     // Dữ liệu mẫu thô 16-bit
    input  wire              sample_valid,   // Xung báo có hàng từ ADC
    
    // Giao tiếp với Feature Engine
    input  wire              read_enable,    // Lệnh đòi hàng 
    output reg signed  [15:0] sample_out,    // Nhả hàng tuần tự
    
    // Giao tiếp với FSM tổng của Bảo
    output reg               window_ready    // Cờ báo sẵn sàng cửa sổ dữ liệu
);

    // 1. Khai báo bộ nhớ RAM nội bộ tối ưu cấu trúc phần cứng
    reg signed [15:0] mem [0:511]; 

    // 2. Con trỏ 9-bit tự động quay đầu vòng tròn khi đạt 511 (0 -> 511 -> 0)
    reg [8:0] wr_ptr;        
    reg [8:0] rd_ptr;        

    // 3. Các bộ đếm quản lý trạng thái cửa sổ
    reg [9:0] sample_count;     // Đếm đến 512 mẫu cho lần chạy đầu tiên
    reg [8:0] new_sample_count; // Đếm đến 256 mẫu mới cho các lần trượt tiếp theo
    reg       first_run;        

    // =============================================================================
    // KHỐI LOGIC GHI DỮ LIỆU TỪ ADC VÀO RAM
    // =============================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr           <= 9'd0;
            sample_count     <= 10'd0;
            new_sample_count <= 9'd0;
            window_ready     <= 1'b0;
            first_run        <= 1'b1;
        end 
        else begin
            if (sample_valid) begin
                mem[wr_ptr] <= sample_in; 

                // TỐI ƯU 1: Con trỏ tự cộng tăng, tự quay đầu về 0 khi vượt 511, bỏ hoàn toàn lệnh IF
                wr_ptr <= wr_ptr + 9'd1; 

                // KỊCH BẢN 1: Lần chạy đầu tiên (Cần đủ 512 mẫu)
                if (first_run) begin
                    if (sample_count < 10'd512) begin
                        sample_count <= sample_count + 10'd1;
                    end
                    
                    // Chạm mốc mẫu thứ 511, chu kỳ sau nạp nốt mẫu 512 là kho đầy khít
                    if (sample_count == 10'd511) begin
                        window_ready <= 1'b1;    
                        first_run    <= 1'b0;    // Chuyển sang chế độ trượt Overlap
                    end else begin
                        window_ready <= 1'b0;
                    end
                end 
                
                // KỊCH BẢN 2: Chế độ trượt Overlap 50% (Chỉ đợi thêm 256 mẫu mới)
                else begin
                    if (new_sample_count < 9'd256) begin
                        new_sample_count <= new_sample_count + 9'd1;
                    end
                    
                    // Nhận đủ 256 mẫu mới là chốt cửa sổ tiếp theo ngay
                    if (new_sample_count == 9'd255) begin
                        window_ready     <= 1'b1; 
                        new_sample_count <= 9'd0;  // Reset bộ đếm mẫu mới
                    end else begin
                        window_ready     <= 1'b0;
                    end
                end
            end 
            else begin
                window_ready <= 1'b0;
            end
        end
    end

    // =============================================================================
    // KHỐI LOGIC ĐỌC DỮ LIỆU TỪ RAM RA KHỐI TÍNH TOÁN
    // =============================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_ptr     <= 9'd0;
            sample_out <= 16'd0;
        end 
        else begin
            if (!read_enable) begin
                rd_ptr <= wr_ptr; // Con trỏ đọc luôn bám vị trí cũ nhất để chuẩn bị nhả hàng tuần tự
            end 
            else begin
                sample_out <= mem[rd_ptr]; 
                
                // TỐI ƯU 2: Tự động quay đầu vòng tròn cho con trỏ đọc
                rd_ptr <= rd_ptr + 9'd1;   
            end
        end
    end

endmodule