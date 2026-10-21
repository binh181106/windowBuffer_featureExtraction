`timescale 1ns / 1ps

// =============================================================================
// Testbench for Feature Extraction Module
// =============================================================================
module tb_feature_extraction;

    reg clk;
    reg rst_n;
    reg start_compute;
    reg [15:0] ecg_threshold;
    reg read_enable;
    wire [8:0] sample_addr;
    reg [7:0] sample_in;

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
        .start_compute(start_compute), .ecg_threshold(ecg_threshold),
        .read_enable(read_enable), .sample_addr(sample_addr),
        .sample_in(sample_in),
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

    integer test_count;
    integer pass_count;
    integer i;

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

        #100;
        rst_n = 1;
        #100;

        // ================================================================
        // Test 1: Linear Pattern 0-7
        // ================================================================
        $display("\n[Test 1] Linear Pattern 0-7");
        test_count = test_count + 1;

        start_compute = 1;
        #10 start_compute = 0;

        wait(state == 4'd1);

        for (i = 0; i < 8; i = i + 1) begin
            @(posedge clk);
            sample_in = i[7:0];
        end

        wait(state == 4'd6);
        @(posedge clk);
        @(posedge clk);

        $display("  PEAK:   %d (expected 7)", f_peak);
        $display("  PTP:    %d (expected 7)", f_ptp);

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

        start_compute = 1;
        #10 start_compute = 0;

        wait(state == 4'd1);

        for (i = 0; i < 8; i = i + 1) begin
            @(posedge clk);
            sample_in = 8'd0;
        end

        wait(state == 4'd6);
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

        start_compute = 1;
        #10 start_compute = 0;

        wait(state == 4'd1);

        for (i = 0; i < 8; i = i + 1) begin
            @(posedge clk);
            sample_in = 8'hFF;
        end

        wait(state == 4'd6);
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
