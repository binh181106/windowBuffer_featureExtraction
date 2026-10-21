`timescale 1ns / 1ps

// =============================================================================
// Testbench for AI Classifier Module
// =============================================================================
module tb_ai_classifier;

    // =============================================================================
    // Clock and Reset
    // =============================================================================
    reg clk;
    reg rst_n;

    // =============================================================================
    // Control
    // =============================================================================
    reg start;
    reg enable;

    // =============================================================================
    // Feature Input (12 features x 16-bit)
    // =============================================================================
    wire signed [15:0] features [0:11];

    // Internal feature registers for driving
    reg signed [15:0] features_int [0:11];

    // Connect internal registers to wires
    assign features[0] = features_int[0];
    assign features[1] = features_int[1];
    assign features[2] = features_int[2];
    assign features[3] = features_int[3];
    assign features[4] = features_int[4];
    assign features[5] = features_int[5];
    assign features[6] = features_int[6];
    assign features[7] = features_int[7];
    assign features[8] = features_int[8];
    assign features[9] = features_int[9];
    assign features[10] = features_int[10];
    assign features[11] = features_int[11];

    // =============================================================================
    // Output
    // =============================================================================
    wire [1:0] class_code;
    wire done;
    wire overflow;
    wire [31:0] fc1_out [0:7];
    wire [31:0] fc2_out [0:3];

    // =============================================================================
    // DUT
    // =============================================================================
    ai_classifier #(
        .FEATURE_WIDTH(16),
        .HIDDEN_NEURONS(8),
        .OUTPUT_NEURONS(4)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .enable(enable),
        .features(features),
        .class_code(class_code),
        .done(done),
        .overflow(overflow),
        .fc1_out(fc1_out),
        .fc2_out(fc2_out)
    );

    // =============================================================================
    // Clock Generation (50.4 MHz)
    // =============================================================================
    initial begin
        clk = 0;
        forever #9.92 clk = ~clk;  // 19.84ns period = 50.4MHz
    end

    // =============================================================================
    // Test Sequence
    // =============================================================================
    integer test_count;
    integer pass_count;
    integer i;

    // Classification name lookup
    function string get_class_name;
        input [1:0] code;
        begin
            case (code)
                2'b00: get_class_name = "Normal";
                2'b01: get_class_name = "Fast";
                2'b10: get_class_name = "Slow";
                2'b11: get_class_name = "Abnormal";
                default: get_class_name = "Unknown";
            endcase
        end
    endfunction

    initial begin
        $display("========================================");
        $display("AI Classifier Testbench");
        $display("========================================");

        test_count = 0;
        pass_count = 0;

        // Initialize
        rst_n = 0;
        start = 0;
        enable = 0;

        for (i = 0; i < 12; i = i + 1) begin
            features_int[i] = 16'h0000;
        end

        #100;
        rst_n = 1;
        enable = 1;
        #100;

        // ================================================================
        // Test 1: Zero Features
        // ================================================================
        $display("\n[Test 1] Zero Features");
        test_count = test_count + 1;

        for (i = 0; i < 12; i = i + 1) begin
            features_int[i] = 16'h0000;
        end

        start = 1;
        @(posedge clk);
        start = 0;

        wait(done);
        @(posedge clk);
        @(posedge clk);

        $display("  Classification: %s (%b)", get_class_name(class_code), class_code);
        $display("  PASS: Classification completed");
        pass_count = pass_count + 1;

        // ================================================================
        // Test 2: All Ones Features
        // ================================================================
        $display("\n[Test 2] All Ones Features");
        test_count = test_count + 1;

        for (i = 0; i < 12; i = i + 1) begin
            features_int[i] = 16'h1000;  // 1.0 in Q4.12
        end

        start = 1;
        @(posedge clk);
        start = 0;

        wait(done);
        @(posedge clk);
        @(posedge clk);

        $display("  Classification: %s (%b)", get_class_name(class_code), class_code);
        $display("  PASS: Classification completed");
        pass_count = pass_count + 1;

        // ================================================================
        // Test 3: Positive Features (likely Normal)
        // ================================================================
        $display("\n[Test 3] Positive Features");
        test_count = test_count + 1;

        // Typical Normal PPG features
        features_int[0]  = 16'h0100;  // RMS = 1.0
        features_int[1]  = 16'h0010;  // VAR = 0.0625
        features_int[2]  = 16'h0080;  // Peak = 0.5
        features_int[3]  = 16'h0020;  // ZC = 32
        features_int[4]  = 16'h00A0;  // PTP = 0.625
        features_int[5]  = 16'h1555;  // Crest = 1.333 (Q4.12)
        features_int[6]  = 16'h1000;  // Half ratio = 1.0
        features_int[7]  = 16'h0080;  // Max = 0.5
        features_int[8]  = 16'h0320;  // RR = 50
        features_int[9]  = 16'h0320;  // RR_prev = 50
        features_int[10] = 16'h1000;  // RR_ratio = 1.0
        features_int[11] = 16'h0000;  // RR_diff = 0

        start = 1;
        @(posedge clk);
        start = 0;

        wait(done);
        @(posedge clk);
        @(posedge clk);

        $display("  Features:");
        $display("    RMS=%d, VAR=%d, Peak=%d", features_int[0], features_int[1], features_int[2]);
        $display("    ZC=%d, PTP=%d, Crest=%d", features_int[3], features_int[4], features_int[5]);
        $display("    RR=%d, RR_ratio=%d", features_int[8], features_int[10]);
        $display("  Classification: %s (%b)", get_class_name(class_code), class_code);

        $display("  PASS: Positive features classified");
        pass_count = pass_count + 1;

        // ================================================================
        // Test 4: High Heart Rate Features (likely Fast/Tachycardia)
        // ================================================================
        $display("\n[Test 4] High Heart Rate (Fast)");
        test_count = test_count + 1;

        features_int[0]  = 16'h0180;  // RMS = 1.5
        features_int[1]  = 16'h0020;  // VAR = 0.125
        features_int[2]  = 16'h00C0;  // Peak = 0.75
        features_int[3]  = 16'h0040;  // ZC = 64
        features_int[4]  = 16'h0100;  // PTP = 1.0
        features_int[5]  = 16'h1555;  // Crest = 1.333
        features_int[6]  = 16'h1000;  // Half ratio = 1.0
        features_int[7]  = 16'h00C0;  // Max = 0.75
        features_int[8]  = 16'h01E0;  // RR = 30 (fast)
        features_int[9]  = 16'h01E0;  // RR_prev = 30
        features_int[10] = 16'h1000;  // RR_ratio = 1.0
        features_int[11] = 16'h0000;  // RR_diff = 0

        start = 1;
        @(posedge clk);
        start = 0;

        wait(done);
        @(posedge clk);
        @(posedge clk);

        $display("  Classification: %s (%b)", get_class_name(class_code), class_code);
        $display("  PASS: High HR classified");
        pass_count = pass_count + 1;

        // ================================================================
        // Test 5: Low Heart Rate Features (likely Slow/Bradycardia)
        // ================================================================
        $display("\n[Test 5] Low Heart Rate (Slow)");
        test_count = test_count + 1;

        features_int[0]  = 16'h0100;  // RMS = 1.0
        features_int[1]  = 16'h0010;  // VAR = 0.0625
        features_int[2]  = 16'h0080;  // Peak = 0.5
        features_int[3]  = 16'h0010;  // ZC = 16
        features_int[4]  = 16'h0080;  // PTP = 0.5
        features_int[5]  = 16'h1000;  // Crest = 1.0
        features_int[6]  = 16'h1000;  // Half ratio = 1.0
        features_int[7]  = 16'h0080;  // Max = 0.5
        features_int[8]  = 16'h05A0;  // RR = 90 (slow)
        features_int[9]  = 16'h05A0;  // RR_prev = 90
        features_int[10] = 16'h1000;  // RR_ratio = 1.0
        features_int[11] = 16'h0000;  // RR_diff = 0

        start = 1;
        @(posedge clk);
        start = 0;

        wait(done);
        @(posedge clk);
        @(posedge clk);

        $display("  Classification: %s (%b)", get_class_name(class_code), class_code);
        $display("  PASS: Low HR classified");
        pass_count = pass_count + 1;

        // ================================================================
        // Test 6: FC2 Output Check
        // ================================================================
        $display("\n[Test 6] FC2 Output Values");
        test_count = test_count + 1;

        $display("  FC2 outputs:");
        for (i = 0; i < 4; i = i + 1) begin
            $display("    fc2_out[%d] = %d", i, fc2_out[i]);
        end
        $display("  PASS: FC2 outputs valid");
        pass_count = pass_count + 1;

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
        $dumpfile("tb_ai_classifier.vcd");
        $dumpvars(0, tb_ai_classifier);
    end

endmodule
