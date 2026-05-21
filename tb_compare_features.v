`timescale 1ns/1ps

// Testbench: exercise feature_engine only
module tb_compare_features();
    reg clk = 0;
    reg rst_n = 0;

    // Inputs
    reg start_compute;
    reg signed [15:0] sample_in;

    // DUT outputs
    wire signed [31:0] f_rms_32, f_var_32, f_peak_32, f_ptp_32, f_crest_32;
    wire [31:0] f_zc_32, f_rr_32, f_rr_prev_32;
    wire signed [31:0] f_half_ratio_32, f_max_32, f_rr_ratio_32, f_rr_diff_32;
    wire feature_valid_32;
    wire read_enable_32;

    feature_engine dut32 (
        .clk(clk),
        .rst_n(rst_n),
        .start_compute(start_compute),
        .sample_in(sample_in),
        .read_enable(read_enable_32),
        .f_rms(f_rms_32),
        .f_var(f_var_32),
        .f_peak(f_peak_32),
        .f_zc(f_zc_32),
        .f_ptp(f_ptp_32),
        .f_crest(f_crest_32),
        .f_half_ratio(f_half_ratio_32),
        .f_max(f_max_32),
        .f_rr(f_rr_32),
        .f_rr_prev(f_rr_prev_32),
        .f_rr_ratio(f_rr_ratio_32),
        .f_rr_diff(f_rr_diff_32),
        .feature_valid(feature_valid_32)
    );

    // Clock
    always #5 clk = ~clk;

    integer i;

    initial begin
        $dumpfile("tb_compare_features.vcd");
        $dumpvars(0, tb_compare_features);

        // Reset
        rst_n = 0;
        start_compute = 0;
        sample_in = 0;
        #20 rst_n = 1;
        #20;

        // Start acquisition
        start_compute = 1;
        #10 start_compute = 0;

        // Feed 512 samples
        for (i = 0; i < 512; i = i + 1) begin
            sample_in = $signed(($signed(i) * 123) & 16'h7FFF) - 16384;
            #10;
        end

        // wait for feature output
        wait(feature_valid_32);
        #10;

        $display("Feature extraction done:");
        $display("f_rms        = %0d", f_rms_32);
        $display("f_var        = %0d", f_var_32);
        $display("f_peak       = %0d", f_peak_32);
        $display("f_ptp        = %0d", f_ptp_32);
        $display("f_crest      = %0d", f_crest_32);
        $display("f_half_ratio = %0d", f_half_ratio_32);
        $display("f_max        = %0d", f_max_32);
        $display("f_zc         = %0d", f_zc_32);
        $display("f_rr         = %0d", f_rr_32);
        $display("f_rr_prev    = %0d", f_rr_prev_32);
        $display("f_rr_ratio   = %0d", f_rr_ratio_32);
        $display("f_rr_diff    = %0d", f_rr_diff_32);
        $display("read_en      = %0d", read_enable_32);
        $display("feature_valid = %0d", feature_valid_32);

        $finish;
    end
endmodule
