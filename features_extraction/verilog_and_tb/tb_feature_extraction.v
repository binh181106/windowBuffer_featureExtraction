`timescale 1ns / 1ps

// =============================================================================
// Testbench: tb_feature_extraction
// Cơ chế:
// 1. Đọc 768 mẫu dữ liệu từ file "input_data.txt"
// 2. Cửa sổ 1: 512 mẫu đầu tiên [0 .. 511] -> tính toán 12 features
// 3. Cửa sổ 2: 256 mẫu cũ [256 .. 511] + 256 mẫu mới [512 .. 767] -> tính 12 features
// 4. Ghi kết quả mỗi lần tính toán ra file "output_features.txt" có đánh STT rõ ràng
// =============================================================================

module tb_feature_extraction;

    // Parameters
    parameter DATA_IN_WIDTH  = 8;
    parameter DATA_OUT_WIDTH = 16;
    parameter NUM_SAMPLES    = 512;
    parameter FS             = 360;
    parameter TOTAL_SAMPLES  = 768;
    parameter CLK_PERIOD     = 20; // 50 MHz (chu kỳ 20ns)

    // Signals điều khiển DUT
    reg                              clk;
    reg                              rst_n;
    reg                              start_compute;
    reg  [15:0]                      ppg_threshold;
    reg                              read_enable;
    wire [8:0]                       sample_addr;
    wire signed [DATA_IN_WIDTH-1:0]  sample_in;

    // Signals đầu ra từ DUT (12 features Q4.12)
    wire signed [DATA_OUT_WIDTH-1:0] f_rms;
    wire signed [DATA_OUT_WIDTH-1:0] f_var;
    wire signed [DATA_OUT_WIDTH-1:0] f_peak;
    wire signed [DATA_OUT_WIDTH-1:0] f_zc;
    wire signed [DATA_OUT_WIDTH-1:0] f_ptp;
    wire signed [DATA_OUT_WIDTH-1:0] f_crest;
    wire signed [DATA_OUT_WIDTH-1:0] f_half_ratio;
    wire signed [DATA_OUT_WIDTH-1:0] f_max;
    wire signed [DATA_OUT_WIDTH-1:0] f_rr;
    wire signed [DATA_OUT_WIDTH-1:0] f_rr_prev;
    wire signed [DATA_OUT_WIDTH-1:0] f_rr_ratio;
    wire signed [DATA_OUT_WIDTH-1:0] f_rr_diff;
    wire                             feature_valid;
    wire                             overflow;

    // Bộ nhớ lưu 768 mẫu đọc từ file
    reg signed [DATA_IN_WIDTH-1:0] memory [0:TOTAL_SAMPLES-1];

    // Quản lý offset dịch cửa sổ (Sliding window hop size = 256)
    reg [9:0] window_offset;

    // Cung cấp sample_in tương ứng với địa chỉ DUT yêu cầu trong cửa sổ hiện tại
    assign sample_in = memory[window_offset + sample_addr];

    // File handles
    integer out_file;

    // Khởi tạo DUT
    feature_extraction #(
        .DATA_IN_WIDTH(DATA_IN_WIDTH),
        .DATA_OUT_WIDTH(DATA_OUT_WIDTH),
        .NUM_SAMPLES(NUM_SAMPLES),
        .FS(FS)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .start_compute(start_compute),
        .ppg_threshold(ppg_threshold),
        .read_enable(read_enable),
        .sample_addr(sample_addr),
        .sample_in(sample_in),
        .f_rms(f_rms),
        .f_var(f_var),
        .f_peak(f_peak),
        .f_zc(f_zc),
        .f_ptp(f_ptp),
        .f_crest(f_crest),
        .f_half_ratio(f_half_ratio),
        .f_max(f_max),
        .f_rr(f_rr),
        .f_rr_prev(f_rr_prev),
        .f_rr_ratio(f_rr_ratio),
        .f_rr_diff(f_rr_diff),
        .feature_valid(feature_valid),
        .overflow(overflow)
    );

    // Tạo xung Clock 50MHz
    always #(CLK_PERIOD / 2) clk = ~clk;

    // =============================================================================
    // Task ghi kết quả ra file và console có đánh số thứ tự rõ ràng
    // =============================================================================
    task write_window_results;
        input integer file_handle;
        input integer win_idx;
        input [9:0]   start_idx;
        input [9:0]   end_idx;
        begin
            // 1. Ghi ra file output_features.txt
            $fdisplay(file_handle, "==========================================================================================================");
            $fdisplay(file_handle, "                               KET QUA TINH TOAN 12 FEATURES - CUA SO %0d", win_idx);
            $fdisplay(file_handle, "==========================================================================================================");
            $fdisplay(file_handle, " Pham vi mau       : [%0d .. %0d] (Tong cong 512 mau)", start_idx, end_idx);
            $fdisplay(file_handle, " Thoi diem (time)  : %0t ns", $time);
            $fdisplay(file_handle, " Co tran (overflow): %0b", overflow);
            $fdisplay(file_handle, " Dinh dang du lieu : 16-bit Fixed-Point Q4.12 (Gia tri Float = Q4.12 / 4096.0)");
            $fdisplay(file_handle, "----------------------------------------------------------------------------------------------------------");
            $fdisplay(file_handle, " STT | Ten Dac Trung  | Hex (16-bit) | Q4.12 Signed | Gia tri Thap phan (Float) | Y nghia / Don vi");
            $fdisplay(file_handle, "-----+----------------+--------------+--------------+---------------------------+---------------------------------");
            $fdisplay(file_handle, "  1  | f_rms          | 16'h%04X     | %12d | %25.4f | Root Mean Square", f_rms, f_rms, $itor(f_rms[15:0]) / 4096.0);
            $fdisplay(file_handle, "  2  | f_var          | 16'h%04X     | %12d | %25.4f | Phuong sai (Variance)", f_var, f_var, $itor(f_var[15:0]) / 4096.0);
            $fdisplay(file_handle, "  3  | f_peak         | 16'h%04X     | %12d | %25.4f | Dinh tuyet doi (|x|max)", f_peak, f_peak, $itor(f_peak[15:0]) / 4096.0);
            $fdisplay(file_handle, "  4  | f_zc           | 16'h%04X     | %12d | %25.4f | Zero Crossing Rate", f_zc, f_zc, $itor(f_zc[15:0]) / 4096.0);
            $fdisplay(file_handle, "  5  | f_ptp          | 16'h%04X     | %12d | %25.4f | Peak-to-Peak (Max - Min)", f_ptp, f_ptp, $itor(f_ptp[15:0]) / 4096.0);
            $fdisplay(file_handle, "  6  | f_crest        | 16'h%04X     | %12d | %25.4f | Crest Factor (Peak/RMS)", f_crest, f_crest, $itor(f_crest[15:0]) / 4096.0);
            $fdisplay(file_handle, "  7  | f_half_ratio   | 16'h%04X     | %12d | %25.4f | Half Ratio (RMS_h1/RMS_h2)", f_half_ratio, f_half_ratio, $itor(f_half_ratio[15:0]) / 4096.0);
            $fdisplay(file_handle, "  8  | f_max          | 16'h%04X     | %12d | %25.4f | Max Value (Co dau)", f_max, f_max, $itor($signed(f_max)) / 4096.0);
            $fdisplay(file_handle, "  9  | f_rr           | 16'h%04X     | %12d | %25.4f | RR Hien tai (Giay)", f_rr, f_rr, $itor(f_rr[15:0]) / 4096.0);
            $fdisplay(file_handle, " 10  | f_rr_prev      | 16'h%04X     | %12d | %25.4f | RR Truoc do (Giay)", f_rr_prev, f_rr_prev, $itor(f_rr_prev[15:0]) / 4096.0);
            $fdisplay(file_handle, " 11  | f_rr_ratio     | 16'h%04X     | %12d | %25.4f | RR Ratio (RR/RR_prev)", f_rr_ratio, f_rr_ratio, $itor(f_rr_ratio[15:0]) / 4096.0);
            $fdisplay(file_handle, " 12  | f_rr_diff      | 16'h%04X     | %12d | %25.4f | RR Diff (RR - RR_prev, Giay)", f_rr_diff, f_rr_diff, $itor($signed(f_rr_diff)) / 4096.0);
            $fdisplay(file_handle, "==========================================================================================================\n");

            // 2. Ghi song song ra man hinh Console Simulation
            $display("\n==========================================================================================================");
            $display("                               KET QUA TINH TOAN 12 FEATURES - CUA SO %0d", win_idx);
            $display("==========================================================================================================");
            $display(" Pham vi mau       : [%0d .. %0d] (Tong cong 512 mau)", start_idx, end_idx);
            $display(" Thoi diem (time)  : %0t ns", $time);
            $display(" Co tran (overflow): %0b", overflow);
            $display(" Dinh dang du lieu : 16-bit Fixed-Point Q4.12 (Gia tri Float = Q4.12 / 4096.0)");
            $display("----------------------------------------------------------------------------------------------------------");
            $display(" STT | Ten Dac Trung  | Hex (16-bit) | Q4.12 Signed | Gia tri Thap phan (Float) | Y nghia / Don vi");
            $display("-----+----------------+--------------+--------------+---------------------------+---------------------------------");
            $display("  1  | f_rms          | 16'h%04X     | %12d | %25.4f | Root Mean Square", f_rms, f_rms, $itor(f_rms[15:0]) / 4096.0);
            $display("  2  | f_var          | 16'h%04X     | %12d | %25.4f | Phuong sai (Variance)", f_var, f_var, $itor(f_var[15:0]) / 4096.0);
            $display("  3  | f_peak         | 16'h%04X     | %12d | %25.4f | Dinh tuyet doi (|x|max)", f_peak, f_peak, $itor(f_peak[15:0]) / 4096.0);
            $display("  4  | f_zc           | 16'h%04X     | %12d | %25.4f | Zero Crossing Rate", f_zc, f_zc, $itor(f_zc[15:0]) / 4096.0);
            $display("  5  | f_ptp          | 16'h%04X     | %12d | %25.4f | Peak-to-Peak (Max - Min)", f_ptp, f_ptp, $itor(f_ptp[15:0]) / 4096.0);
            $display("  6  | f_crest        | 16'h%04X     | %12d | %25.4f | Crest Factor (Peak/RMS)", f_crest, f_crest, $itor(f_crest[15:0]) / 4096.0);
            $display("  7  | f_half_ratio   | 16'h%04X     | %12d | %25.4f | Half Ratio (RMS_h1/RMS_h2)", f_half_ratio, f_half_ratio, $itor(f_half_ratio[15:0]) / 4096.0);
            $display("  8  | f_max          | 16'h%04X     | %12d | %25.4f | Max Value (Co dau)", f_max, f_max, $itor($signed(f_max)) / 4096.0);
            $display("  9  | f_rr           | 16'h%04X     | %12d | %25.4f | RR Hien tai (Giay)", f_rr, f_rr, $itor(f_rr[15:0]) / 4096.0);
            $display(" 10  | f_rr_prev      | 16'h%04X     | %12d | %25.4f | RR Truoc do (Giay)", f_rr_prev, f_rr_prev, $itor(f_rr_prev[15:0]) / 4096.0);
            $display(" 11  | f_rr_ratio     | 16'h%04X     | %12d | %25.4f | RR Ratio (RR/RR_prev)", f_rr_ratio, f_rr_ratio, $itor(f_rr_ratio[15:0]) / 4096.0);
            $display(" 12  | f_rr_diff      | 16'h%04X     | %12d | %25.4f | RR Diff (RR - RR_prev, Giay)", f_rr_diff, f_rr_diff, $itor($signed(f_rr_diff)) / 4096.0);
            $display("==========================================================================================================\n");
        end
    endtask

    // =============================================================================
    // Main Test Sequence
    // =============================================================================
    initial begin
        // 1. Khoi tao cac tin hieu
        clk           = 1'b0;
        rst_n         = 1'b0;
        start_compute = 1'b0;
        ppg_threshold = 16'd2; // Ngưỡng phát hiện đỉnh R/PPG phù hợp biên độ tín hiệu (đỉnh max = 3)
        read_enable   = 1'b1;
        window_offset = 10'd0;

        // 2. Mo file de ghi ket qua
        out_file = $fopen("output_features.txt", "w");
        if (out_file == 0) begin
            $display("[ERROR] Khong the mo file output_features.txt de ghi ket qua!");
            $finish;
        end

        // 3. Doc 768 mau tu file input_data.txt (dinh dang Hex 8-bit bu 2)
        $display("\n[INFO] Dang doc %0d mau tu file input_data.txt...", TOTAL_SAMPLES);
        $readmemh("input_data.txt", memory);
        $display("[INFO] Da doc thanh cong %0d mau vao bo nho.", TOTAL_SAMPLES);

        // 4. Reset DUT
        $display("[INFO] Dang khoi dong va Reset he thong...");
        #(CLK_PERIOD * 5);
        rst_n = 1'b1;
        #(CLK_PERIOD * 2);

        // =========================================================================
        // CHAY CUA SO 1: 512 mau dau tien (Mau 0 den 511)
        // =========================================================================
        $display("\n>>> BAT DAU TINH TOAN CUA SO 1: 512 mau dau tien [0 .. 511] <<<");
        window_offset = 10'd0;

        @(posedge clk);
        start_compute = 1'b1;
        @(posedge clk);
        start_compute = 1'b0;

        // Cho cho den khi DUT hoan thanh (feature_valid len 1)
        @(posedge clk);
        while (!feature_valid) begin
            @(posedge clk);
        end

        // Ghi ket qua Cua so 1 ra file va console
        write_window_results(out_file, 1, 10'd0, 10'd511);

        // =========================================================================
        // CHAY CUA SO 2: 256 mau cu [256..511] + 256 mau moi [512..767]
        // Tong cong: 512 mau [256 .. 767]
        // =========================================================================
        #(CLK_PERIOD * 5); // Cho vai chu ky nghi giua 2 cua so

        $display("\n>>> BAT DAU TINH TOAN CUA SO 2: 512 mau tiep theo [256 .. 767] <<<");
        $display("(Bao gom: 256 mau cu [256-511] + 256 mau moi [512-767])");
        window_offset = 10'd256;

        @(posedge clk);
        start_compute = 1'b1;
        @(posedge clk);
        start_compute = 1'b0;

        // Cho cho den khi DUT hoan thanh (feature_valid len 1)
        @(posedge clk);
        while (!feature_valid) begin
            @(posedge clk);
        end

        // Ghi ket qua Cua so 2 ra file va console
        write_window_results(out_file, 2, 10'd256, 10'd767);

        // 5. Ket thuc mo phong
        #(CLK_PERIOD * 5);
        $fclose(out_file);
        $display("[SUCCESS] Da tinh toan xong 2 cua so va xuat ket qua thanh cong ra file: output_features.txt");
        $finish;
    end

endmodule
