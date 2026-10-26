`timescale 1ns / 1ps

// =============================================================================
// Testbench for Feature Extraction Module
// =============================================================================
// Fix v3.0 (BƯỚC 3):
//  - start_compute phải giữ >= 1 chu kỳ clock (trước đây #10 < 19.84/2 ->
//    có xác suất bị bỏ qua -> wait(state==1) treo vô hạn = baseline HANG).
//  - Stimulus "phase-independent": sample_in được nạp từ bảng dữ liệu theo
//    chính địa chỉ sample_addr do RTL phát ra. Đây đúng là quan hệ phụ thuộc
//    thật trong top (window_buffer.frame_out = ram[oldest + sample_addr]) ->
//    không phụ thuộc pha khởi động, giữ được giá trị kỳ vọng gốc.
//  - Mọi wait đều có guard timeout -> không treo testbench.
// =============================================================================
module tb_feature_extraction;

    reg clk;
    reg rst_n;
    reg start_compute;
    reg [15:0] ecg_threshold;
    reg read_enable;
    reg soft_reset;
    wire [8:0] sample_addr;
    reg [7:0] sample_in;
    wire read_en;

    wire signed [15:0] f_rms, f_var, f_peak, f_zc, f_ptp;
    wire signed [15:0] f_crest, f_half_ratio, f_max;
    wire signed [15:0] f_rr, f_rr_prev, f_rr_ratio, f_rr_diff;
    wire feature_valid;
    wire overflow;
    wire [3:0] state;

    feature_extraction #(
        .DATA_IN_WIDTH(8),
        .DATA_OUT_WIDTH(16),
        .NUM_SAMPLES(8)
    ) dut (
        .clk(clk), .rst_n(rst_n),
        .soft_reset(soft_reset),
        .start_compute(start_compute), .ecg_threshold(ecg_threshold),
        .read_enable(read_enable), .sample_addr(sample_addr),
        .sample_in(sample_in),
        .read_en(read_en),
        .f_rms(f_rms), .f_var(f_var), .f_peak(f_peak),
        .f_zc(f_zc), .f_ptp(f_ptp), .f_crest(f_crest),
        .f_half_ratio(f_half_ratio), .f_max(f_max),
        .f_rr(f_rr), .f_rr_prev(f_rr_prev), .f_rr_ratio(f_rr_ratio),
        .f_rr_diff(f_rr_diff), .feature_valid(feature_valid), .overflow(overflow)
    );

    assign state = dut.state;

    initial begin
        clk = 0;
        forever #9.92 clk = ~clk;  // 19.84ns period = 50.4MHz
    end

    // =============================================================================
    // Bảng dữ liệu mẫu: pattern[id] = giá trị mẫu ở chỉ số id.
    // Nạp bằng task load_pattern trước khi start.
    // =============================================================================
    reg [7:0] pattern [0:15];

    task load_pattern;
        input integer n;
        input integer kind;   // 0 = tuần tự 0..n-1, 1 = tất cả 0, 2 = tất cả 0xFF
        integer k;
        begin
            for (k = 0; k < 16; k = k + 1) begin
                case (kind)
                    0:    pattern[k] = k[7:0];
                    1:    pattern[k] = 8'd0;
                    2:    pattern[k] = 8'hFF;
                    default: pattern[k] = 8'd0;
                endcase
            end
        end
    endtask

    // =============================================================================
    // Stimulus: sample_in theo địa chỉ do RTL phát (phase-independent)
    // =============================================================================
    always @(negedge clk) begin
        if (sample_addr < 16)
            sample_in = pattern[sample_addr];
        else
            sample_in = 8'd0;
    end

    // =============================================================================
    // wait_state_reached: chờ state == target trong tối đa max_cycles chu kỳ.
    // Đặt wait_ok = 1 nếu đạt, 0 nếu timeout (chống treo TB).
    // Ghi chú: KHÔNG dùng input "condition" kiểu boolean truyền theo giá trị
    // (được đánh giá 1 lần lúc gọi -> vòng lặp không follow trạng thái).
    // =============================================================================
    reg wait_ok;
    task wait_state_reached;
        input [3:0] target;
        input integer max_cycles;
        integer waited;
        begin
            waited = 0;
            while (state != target && waited < max_cycles) begin
                @(posedge clk);
                waited = waited + 1;
            end
            wait_ok = (state == target);
        end
    endtask

    integer test_count;
    integer pass_count;

    initial begin
        $display("========================================");
        $display("Feature Extraction Testbench");
        $display("========================================");

        test_count = 0;
        pass_count = 0;

        rst_n = 0;
        start_compute = 0;
        ecg_threshold = 16'd80;
        sample_in = 0;
        read_enable = 0;
        soft_reset = 0;

        #100;
        rst_n = 1;
        #100;

        // ================================================================
        // Test 1: Linear Pattern 0-7
        // ================================================================
        $display("\n[Test 1] Linear Pattern 0-7");
        test_count = test_count + 1;

        load_pattern(8, 0);

        // (fix tb) start_compute giữ >= 1 chu kỳ clock.
        @(posedge clk);
        start_compute = 1;
        @(posedge clk);
        start_compute = 0;

        wait_state_reached(4'd1, 100);
        if (!wait_ok) begin
            $display("  FAIL: never reached ACCUMULATE");
            $display("\nTest Summary: %d/%d PASSED", pass_count, test_count);
            $finish;
        end

        wait_state_reached(4'd6, 200);
        if (!wait_ok)
            $display("  FAIL: never reached DONE");
        @(posedge clk);
        @(posedge clk);

        $display("  PEAK:   %d (expected 7)", f_peak);
        $display("  PTP:    %d (expected 7)", f_ptp);
        $display("  ZC:     %d (expected 0)", f_zc);

        if (f_peak == 16'd7 && f_ptp == 16'd7) begin
            $display("  PASS");
            pass_count = pass_count + 1;
        end else begin
            $display("  FAIL");
        end

        // ================================================================
        // Test 2: All Zeros
        // ================================================================
        $display("\n[Test 2] All Zeros");
        test_count = test_count + 1;

        load_pattern(8, 1);

        @(posedge clk);
        start_compute = 1;
        @(posedge clk);
        start_compute = 0;

        wait_state_reached(4'd1, 100);
        if (!wait_ok) begin
            $display("  FAIL: never reached ACCUMULATE");
            $display("\nTest Summary: %d/%d PASSED", pass_count, test_count);
            $finish;
        end

        wait_state_reached(4'd6, 200);
        if (!wait_ok)
            $display("  FAIL: never reached DONE");
        @(posedge clk);
        @(posedge clk);

        $display("  RMS:    %d (expected 0)", f_rms);
        $display("  VAR:    %d (expected ~0)", f_var);
        $display("  PEAK:   %d (expected 0)", f_peak);

        if (f_rms == 0 && f_peak == 0) begin
            $display("  PASS");
            pass_count = pass_count + 1;
        end else begin
            $display("  FAIL");
        end

        // ================================================================
        // Test 3: All Ones (0xFF = 255 unsigned = -1 signed)
        // ================================================================
        $display("\n[Test 3] All Ones (0xFF)");
        test_count = test_count + 1;

        load_pattern(8, 2);

        @(posedge clk);
        start_compute = 1;
        @(posedge clk);
        start_compute = 0;

        wait_state_reached(4'd1, 100);
        if (!wait_ok) begin
            $display("  FAIL: never reached ACCUMULATE");
            $display("\nTest Summary: %d/%d PASSED", pass_count, test_count);
            $finish;
        end

        wait_state_reached(4'd6, 200);
        if (!wait_ok)
            $display("  FAIL: never reached DONE");
        @(posedge clk);
        @(posedge clk);

        $display("  PEAK:   %d (expected -1 = 16'hFFFF in signed)", f_peak);
        $display("  f_peak = 0x%h", f_peak);

        // 0xFF as signed 8-bit = -1, sign-extended to 16-bit = -1
        if (f_peak == -1) begin
            $display("  PASS");
            pass_count = pass_count + 1;
        end else begin
            $display("  FAIL: expected -1");
        end

        // ================================================================
        // Test 4: RR ratio divide-by-zero guard
        // Không có R-peak nào -> rr_previous = 0 -> f_rr_ratio phải = 4096
        // (1.0 trong Q4.12), KHÔNG được chia 0.
        // ================================================================
        $display("\n[Test 4] RR ratio divide-by-zero guard (no R-peak)");
        test_count = test_count + 1;

        load_pattern(8, 1);   // mẫu toàn 0 -> không vượt ngưỡng -> không có RR

        @(posedge clk);
        start_compute = 1;
        @(posedge clk);
        start_compute = 0;

        wait_state_reached(4'd1, 100);
        wait_state_reached(4'd6, 200);
        @(posedge clk);
        @(posedge clk);

        $display("  RR:       %d (expected 0)", f_rr);
        $display("  RR_PREV:  %d (expected 0)", f_rr_prev);
        $display("  RR_RATIO: %d (expected 4096 = 1.0 Q4.12)", f_rr_ratio);

        if (f_rr_ratio == 16'd4096) begin
            $display("  PASS");
            pass_count = pass_count + 1;
        end else begin
            $display("  FAIL: rr_ratio = %d, expected 4096 (division by zero!)", f_rr_ratio);
        end

        $display("\n========================================");
        $display("Test Summary: %d/%d PASSED", pass_count, test_count);
        $display("========================================");

        $finish;
    end

    initial begin
        $dumpfile("tb_feature_extraction.vcd");
        $dumpvars(0, tb_feature_extraction);
    end

endmodule
