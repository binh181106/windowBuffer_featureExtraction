// =============================================================================
// Tên Module: window_buffer (Bản tối ưu hóa 512 mẫu - Sửa lỗi trễ RAM)
// Cấu trúc: 512 mẫu, Overlap 50% (Trượt 256 mẫu mới) [cite: 67, 75, 108-109]
// Tần số hệ thống thích ứng: 256Hz (Bảo toàn khung phân tích tròn 2 giây) [cite: 75, 108]
// =============================================================================

module window_buffer (
    input  wire              clk,            // Xung nhịp hệ thống (50MHz)
    input  wire              rst_n,          // Reset tích cực mức thấp
    
    // Giao tiếp với bộ đổi nguồn ADC (Tần số hệ thống: 256Hz) [cite: 57, 75]
    input  wire signed [15:0] sample_in,     // Dữ liệu mẫu thô 16-bit [cite: 57]
    input  wire              sample_valid,   // Xung báo dữ liệu hợp lệ từ ADC
    
    // Giao tiếp bắt tay với Feature Engine [cite: 69]
    input  wire              read_enable,    // Lệnh cho phép đọc (đòi hàng) [cite: 69]
    output reg signed  [15:0] sample_out,    // Dữ liệu mẫu nhả tuần tự ra đường dây
    
    // Giao tiếp điều khiển hạ nguồn
    output reg               window_ready    // Cờ báo kho đã đủ 512 mẫu [cite: 108]
);

    // 1. Khai báo bộ nhớ RAM nội bộ (Block RAM) [cite: 109]
    reg signed [15:0] mem [0:511]; 

    // 2. Con trỏ 9-bit tự động wrap-around tuần hoàn từ 0 đến 511 tốn 0% logic so sánh
    reg [8:0] wr_ptr;        
    reg [8:0] rd_ptr;        

    // 3. Các bộ đếm quản lý trạng thái trượt [cite: 67, 109]
    reg [9:0] sample_count;     // Bộ đếm cho lần chạy đầu tiên (đủ 512 mẫu) [cite: 108]
    reg [8:0] new_sample_count; // Bộ đếm cho lần trượt tiếp theo (đủ 256 mẫu mới) [cite: 67]
    reg       first_run;        

    // =============================================================================
    // KHỐI LOGIC GHI DỮ LIỆU TỪ ADC VÀO RAM VÒNG TRÒN
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

                // TỐI ƯU ĐỈNH CAO: Tự tăng, tự tràn về 0 khi vượt mốc 511
                wr_ptr <= wr_ptr + 9'd1; 

                // KỊCH BẢN 1: Lần chạy đầu tiên (Cần thu thập đủ 512 mẫu) [cite: 108]
                if (first_run) begin
                    if (sample_count < 10'd512) begin
                        sample_count <= sample_count + 10'd1;
                    end
                    
                    if (sample_count == 10'd511) begin
                        window_ready <= 1'b1;    // Bắn cờ báo đầy kho dữ liệu [cite: 108]
                        first_run    <= 1'b0;    // Chuyển ngay sang chế độ trượt Overlap [cite: 109]
                    end else begin
                        window_ready <= 1'b0;
                    end
                end 
                
                // KỊCH BẢN 2: Chế độ trượt Overlap 50% (Chỉ cần đợi nạp thêm 256 mẫu mới) [cite: 67]
                else begin
                    if (new_sample_count < 9'd256) begin
                        new_sample_count <= new_sample_count + 9'd1;
                    end
                    
                    if (new_sample_count == 9'd255) begin
                        window_ready     <= 1'b1; // Tiếp tục dựng cờ báo cửa sổ mới sẵn sàng
                        new_sample_count <= 9'd0;  // Reset bộ đếm mẫu mới để chờ lượt sau
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
    // KHỐI LOGIC ĐỌC DỮ LIỆU ĐÃ ĐƯỢC VÁ LỖI TRỄ MẠCH (PRE-FETCH PIPELINE)
    // =============================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_ptr     <= 9'd0;
            sample_out <= 16'd0;
        end 
        else begin
            // Trường hợp 1: Khối tính toán chưa đòi hàng (Hệ thống đang nghỉ ngơi hoặc nạp thêm)
            if (!read_enable) begin
                // Con trỏ đọc đi trước 1 bước, trỏ sẵn vào ô dữ liệu tiếp theo
                rd_ptr     <= wr_ptr + 9'd1;   
                // BRAM chủ động lôi mẫu cũ nhất ra phục sẵn trên đường truyền sample_out
                sample_out <= mem[wr_ptr]; 
            end 
            // Trường hợp 2: Khối tính toán kéo read_enable = 1 (Đòi nhả hàng liên tục)
            else begin
                // Các mẫu dữ liệu từ vị trí số 1 đến 511 lần lượt được tuồn ra khít khao từng chu kỳ clk
                sample_out <= mem[rd_ptr]; 
                
                // Con trỏ tự động tịnh tiến vòng tròn
                rd_ptr <= rd_ptr + 9'd1;   
            end
        end
    end

endmodule
