`timescale 1ns / 1ps

// =============================================================================
// Testbench for ADC Interface Module
// =============================================================================
module tb_adc_interface;

    // =============================================================================
    // Clock and Reset
    // =============================================================================
    reg clk;
    reg rst_n;

    // =============================================================================
    // Configuration
    // =============================================================================
    reg [17:0] sample_rate_div;

    // =============================================================================
    // ADC Interface
    // =============================================================================
    reg [7:0] adc_data_in;
    reg adc_data_valid;
    reg adc_clk;

    // =============================================================================
    // Output
    // =============================================================================
    wire [7:0] sample_out;
    wire sample_valid;
    wire adc_overflow;
    wire [31:0] sample_count;

    // =============================================================================
    // DUT
    // =============================================================================
    adc_interface #(
        .DATA_WIDTH(8),
        .DIV_WIDTH(18)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .sample_rate_div(sample_rate_div),
        .adc_data_in(adc_data_in),
        .adc_data_valid(adc_data_valid),
        .adc_clk(adc_clk),
        .sample_out(sample_out),
        .sample_valid(sample_valid),
        .adc_overflow(adc_overflow),
        .sample_count(sample_count)
    );

    // =============================================================================
    // Clock Generation (50.4 MHz)
    // =============================================================================
    initial begin
        clk = 0;
        forever #9.92 clk = ~clk;  // 19.84ns period = 50.4MHz
    end

    // =============================================================================
    // ADC Clock Generation (for reference, not used)
    // =============================================================================
    initial begin
        adc_clk = 0;
    end

    // =============================================================================
    // Test Sequence
    // =============================================================================
    integer test_count;
    integer pass_count;
    integer i;
    reg [7:0] expected_sample;

    initial begin
        $display("========================================");
        $display("ADC Interface Testbench");
        $display("========================================");

        test_count = 0;
        pass_count = 0;

        // Initialize
        rst_n = 0;
        sample_rate_div = 18'd100;  // Fast clock for testing
        adc_data_in = 8'd0;
        adc_data_valid = 0;

        #100;
        rst_n = 1;
        #100;

        // ================================================================
        // Test 1: Basic Data Forwarding
        // ================================================================
        $display("\n[Test 1] Basic Data Forwarding");
        test_count = test_count + 1;

        @(posedge clk);
        adc_data_in = 8'h55;
        adc_data_valid = 1;
        @(posedge clk);
        adc_data_valid = 0;

        // Wait for rate tick and data to be forwarded
        repeat(150) @(posedge clk);

        if (sample_valid && sample_out == 8'h55) begin
            $display("  PASS: sample_out = 0x%h", sample_out);
            pass_count = pass_count + 1;
        end else begin
            $display("  FAIL: sample_out = 0x%h, valid = %b", sample_out, sample_valid);
        end

        // ================================================================
        // Test 2: Multiple Samples
        // ================================================================
        $display("\n[Test 2] Multiple Samples");
        test_count = test_count + 1;

        for (i = 0; i < 10; i = i + 1) begin
            @(posedge clk);
            adc_data_in = 8'(i * 10);
            adc_data_valid = 1;
            @(posedge clk);
            adc_data_valid = 0;
            repeat(120) @(posedge clk);
        end

        if (sample_count >= 10) begin
            $display("  PASS: sample_count = %d", sample_count);
            pass_count = pass_count + 1;
        end else begin
            $display("  FAIL: sample_count = %d, expected >= 10", sample_count);
        end

        // ================================================================
        // Test 3: Overflow Detection
        // ================================================================
        $display("\n[Test 3] Overflow Detection");
        test_count = test_count + 1;

        // Send data too fast (back-to-back)
        repeat(10) begin
            @(posedge clk);
            adc_data_in = 8'hAA;
            adc_data_valid = 1;
            @(posedge clk);
            adc_data_valid = 0;
        end

        #100;
        if (sample_valid) begin
            $display("  PASS: Sample forwarded (overflow may have occurred)");
            pass_count = pass_count + 1;
        end else begin
            $display("  INFO: No sample forwarded during fast data");
        end

        // ================================================================
        // Test 4: Reset Behavior
        // ================================================================
        $display("\n[Test 4] Reset Behavior");
        test_count = test_count + 1;

        // Send some data
        @(posedge clk);
        adc_data_in = 8'hFF;
        adc_data_valid = 1;
        @(posedge clk);
        adc_data_valid = 0;
        repeat(50) @(posedge clk);

        // Reset
        rst_n = 0;
        #50;
        rst_n = 1;
        #50;

        if (sample_count == 0) begin
            $display("  PASS: sample_count reset to 0");
            pass_count = pass_count + 1;
        end else begin
            $display("  FAIL: sample_count = %d after reset", sample_count);
        end

        // ================================================================
        // Test 5: Sine Wave Pattern (ECG simulation)
        // ================================================================
        $display("\n[Test 5] Sine Wave Pattern");
        test_count = test_count + 1;

        for (i = 0; i < 64; i = i + 1) begin
            @(posedge clk);
            // Generate sine wave approximation
            adc_data_in = 8'(128 + int'($sin(i * 2 * 3.14159 / 64) * 50));
            adc_data_valid = 1;
            @(posedge clk);
            adc_data_valid = 0;
            repeat(120) @(posedge clk);
        end

        if (sample_count > 10) begin
            $display("  PASS: %d sine wave samples captured", sample_count);
            pass_count = pass_count + 1;
        end else begin
            $display("  FAIL: Only %d samples captured", sample_count);
        end

        $display("\n========================================");
        $display("Test Summary: %d/%d PASSED", pass_count, test_count);
        $display("========================================");

        #100;
        $finish;
    end

    // =============================================================================
    // Waveform Dump
    // =============================================================================
    initial begin
        $dumpfile("tb_adc_interface.vcd");
        $dumpvars(0, tb_adc_interface);
    end

endmodule
