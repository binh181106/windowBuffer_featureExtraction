`timescale 1ns / 1ps

module tb_feature_simple;

    reg clk = 0;
    reg rst_n = 0;
    reg start_compute = 0;
    reg [15:0] ecg_threshold = 16'd80;
    reg read_enable = 0;
    wire [8:0] sample_addr;
    reg [7:0] sample_in;
    wire signed [15:0] f_rms, f_var, f_peak, f_zc, f_ptp;
    wire signed [15:0] f_crest, f_half_ratio, f_max;
    wire signed [15:0] f_rr, f_rr_prev, f_rr_ratio, f_rr_diff;
    wire feature_valid;
    wire overflow;
    wire [3:0] state;
    wire signed [7:0] sample_in_dut;

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
    assign sample_in_dut = dut.sample_in;  // Probe DUT's sample_in

    always #9.92 clk = ~clk;  // 19.84ns period = 50.4MHz

    initial begin
        $dumpfile("tb_feature_simple.vcd");
        $dumpvars(0, tb_feature_simple);
    end

    integer i;

    initial begin
        $display("Feature Extraction Test (8 samples)");
        $display("========================================");

        rst_n = 0;
        sample_in = 0;
        #100 rst_n = 1;
        #100;

        start_compute = 1;
        #10 start_compute = 0;

        // Wait for ACCUMULATE state
        wait(state == 4'd1);
        $display("Entered ACCUMULATE");

        // Feed samples and monitor
        for (i = 0; i < 8; i = i + 1) begin
            @(posedge clk);
            sample_in = i[7:0];
            $display("t=%t clk=%b sample_in_tb=%d sample_in_dut=%d state=%d peak=%d",
                     $time, clk, sample_in, sample_in_dut, state, dut.peak_reg);
        end

        // Wait for DONE
        wait(state == 4'd6);
        @(posedge clk);
        @(posedge clk);

        $display("\n=== RESULTS ===");
        $display("peak_reg (final) = %d", dut.peak_reg);
        $display("f_peak = %d", f_peak);
        $display("sum = %d", dut.sum);

        $finish;
    end

endmodule
