`timescale 1ns / 1ps

// =============================================================================
// tb_ai_classifier_math - Deterministic MLP behavior checker
//
// The default tb_ai_classifier only proves the pipeline RUNS (placeholder
// zero weights -> every test just checks "classification completed"). That
// does NOT validate the math. This TB forces a KNOWN, deterministic weight
// configuration so the expected output is independent of any trained data:
//
//   - mean_vals=0, inv_scale=4096 (1.0), fc1/fc2 weights=0  (default already)
//   - With all FC1/FC2 weights 0, the only non-zero path is:
//         FC1_raw = fc1_biases(=0) -> ReLU(0)=0 -> FC2_raw=0 -> FC2 = fc2_biases
//     so  class_code == argmax(forced fc2_biases), ties -> LOWEST index.
//   - We then force distinct fc2_biases vectors and check the exact class,
//     plus a tie-break case and a saturation/overflow-latch case.
//
// This is an INDEPENDENT expected-value check (argmax of a known constant
// vector), not a mirror of the RTL.
// =============================================================================
module tb_ai_classifier_math;

    reg clk;
    reg rst_n;
    reg start;
    reg enable;
    reg soft_reset;

    wire [1:0]  class_code;
    wire        done;
    wire        overflow;
    // Debug outputs (connect them so the test can assert on intermediate
    // values, not just the final class code).
    wire signed [31:0] fc1_out [0:7];
    wire signed [31:0] fc2_out [0:3];

    // Feature ports: drive via a wire array assigned from internal regs
    // (mirrors tb_ai_classifier; register arrays can't connect to a port
    //  of type "reg signed [15:0] features[0:11]" in this toolchain).
    wire signed [15:0] features [0:11];
    reg signed [15:0] features_int [0:11];
    genvar g;
    generate
        for (g = 0; g < 12; g = g + 1) begin : gen_feat
            assign features[g] = features_int[g];
        end
    endgenerate

    ai_classifier #(
        .FEATURE_WIDTH(16),
        .HIDDEN_NEURONS(8),
        .OUTPUT_NEURONS(4)
    ) dut (
        .clk(clk), .rst_n(rst_n), .soft_reset(soft_reset),
        .start(start), .enable(enable),
        .features(features),
        .class_code(class_code), .done(done), .overflow(overflow),
        .fc1_out(fc1_out), .fc2_out(fc2_out)
    );

    initial begin
        clk = 0;
        forever #9.92 clk = ~clk;   // 50.4 MHz
    end

    integer test_count;
    integer pass_count;
    integer i;

    // Force a known fc2_biases vector, run inference, return the class code.
    // (force is released so the next test can re-force cleanly.)
    task run_with_fc2_bias;
        input [15:0] b0; input [15:0] b1; input [15:0] b2; input [15:0] b3;
        begin
            force dut.fc2_biases[0] = b0;
            force dut.fc2_biases[1] = b1;
            force dut.fc2_biases[2] = b2;
            force dut.fc2_biases[3] = b3;

            for (i = 0; i < 12; i = i + 1) features_int[i] = 16'h0000;

            start = 1;
            @(posedge clk);
            start = 0;
            wait(done);
            @(posedge clk);
            @(posedge clk);

            release dut.fc2_biases[0];
            release dut.fc2_biases[1];
            release dut.fc2_biases[2];
            release dut.fc2_biases[3];
        end
    endtask

    // Deterministic non-zero MLP test: set mean/inv_scale/weights/biases via
    // hierarchical assignment into the ROM registers (they are not ports;
    // this is the intended test hook, and does NOT bypass the MAC/ReLU/
    // argmax datapath, which still executes in the FSM). Then drive a known
    // feature vector and check the exact class + intermediate values.
    task set_deterministic_weights;
        begin
            // mean_vals = 0 (default), inv_scale[0]=4096 (1.0), rest = 4096.
            // Only feature[0] carries value; weights connect feature[0] only.
            for (i = 0; i < 12; i = i + 1) begin
                dut.mean_vals[i] = 16'd0;
                dut.inv_scale[i] = 16'd4096;   // 1.0 Q4.12
            end
            // FC1: only feature[0] -> fc1_weight[0] feeds hidden neuron 0.
            // fc1_weight[j*12+feat_idx? no: index = cnt-1 where
            //   neuron=(cnt-1)/12, feature=(cnt-1)%12).
            // So weight index for (neuron0, feature0) = 0*12+0 = 0.
            for (i = 0; i < 96; i = i + 1) dut.fc1_weights[i] = 16'd0;
            dut.fc1_weights[0] = 16'd4096;      // 1.0 -> hidden0 = f0*1.0
            for (i = 0; i < 8; i = i + 1) dut.fc1_biases[i] = 16'd0;
            // FC2: hidden neuron0 -> all 4 outputs (index = out*8 + hidden).
            for (i = 0; i < 32; i = i + 1) dut.fc2_weights[i] = 16'd0;
            dut.fc2_weights[0]  = 16'd1024;  // out0 = h0*0.25
            dut.fc2_weights[8]  = 16'd2048;  // out1 = h0*0.5
            dut.fc2_weights[16] = 16'd3072;  // out2 = h0*0.75
            dut.fc2_weights[24] = 16'd4096;  // out3 = h0*1.0
            for (i = 0; i < 4; i = i + 1) dut.fc2_biases[i] = 16'd0;
        end
    endtask

    task run_inference;
        begin
            start = 1;
            @(posedge clk);
            start = 0;
            wait(done);
            @(posedge clk);
            @(posedge clk);
        end
    endtask

    initial begin
        $display("========================================");
        $display("AI Classifier Math Testbench (deterministic)");
        $display("========================================");

        test_count = 0; pass_count = 0;

        rst_n = 0; start = 0; enable = 0; soft_reset = 0;
        for (i = 0; i < 12; i = i + 1) features_int[i] = 16'h0000;
        #100; rst_n = 1; #100;
        enable = 1;    // MLP requires start && enable (IDLE -> LOAD)

        // ---------------------------------------------------------------
        // Test 1: argmax of a known vector -> highest bias wins
        // fc2 = {4096, 8192, 12288, 6144}  -> index 2 is max -> class 10
        // ---------------------------------------------------------------
        $display("\n[Test 1] argmax known vector -> expect class 10 (idx2)");
        test_count = test_count + 1;
        run_with_fc2_bias(16'h1000, 16'h2000, 16'h3000, 16'h1800);
        $display("  class_code = %b (expected 2'b10)", class_code);
        if (class_code == 2'b10) begin
            $display("  PASS"); pass_count = pass_count + 1;
        end else $display("  FAIL");

        // ---------------------------------------------------------------
        // Test 2: tie-break -> all equal biases -> LOWEST index (0 = Normal)
        // ---------------------------------------------------------------
        $display("\n[Test 2] tie-break all-equal -> expect class 00 (idx0)");
        test_count = test_count + 1;
        run_with_fc2_bias(16'h2000, 16'h2000, 16'h2000, 16'h2000);
        $display("  class_code = %b (expected 2'b00)", class_code);
        if (class_code == 2'b00) begin
            $display("  PASS"); pass_count = pass_count + 1;
        end else $display("  FAIL");

        // ---------------------------------------------------------------
        // Test 3: negative biases -> ReLU keeps FC1 at 0; FC2 = biases (neg)
        // argmax of { -4096,-2048,-8192,-1024 } = index1 -> class 01
        // ---------------------------------------------------------------
        $display("\n[Test 3] negative-bias argmax -> expect class 01 (idx1)");
        test_count = test_count + 1;
        run_with_fc2_bias(16'hFFF0, 16'hFFF8, 16'hFFC0, 16'hFFF4);
        $display("  class_code = %b (expected 2'b01)", class_code);
        if (class_code == 2'b01) begin
            $display("  PASS"); pass_count = pass_count + 1;
        end else $display("  FAIL");

        // ---------------------------------------------------------------
        // Test 4: Full deterministic non-zero path
        //   f0 = 8 (Q4.12 8/4096 raw = 8.0), all other features = 0.
        //   mean=0, inv_scale=1.0.
        //   FC1: only w[0]=1.0 to neuron0, feat0 -> fc1raw0 = (8*4096)*4096>>>12
        //        = 32768 (Q4.12 of 8.0). ReLU: hidden0 = 32768 (positive).
        //   FC2: out_n = h0 * w >>> 12:
        //     w={1024,2048,3072,4096} (Q4.12 {0.25,0.5,0.75,1.0}), h0=32768
        //     -> {8192,16384,24576,32768} = Q4.12 {2,4,6,8}
        //   Argmax = index 3 -> class 11 (Abnormal).
        //   Expected values are hand-computed from the documented Q4.12
        //   formulas (independent of the DUT): scaling is /4096 per MAC.
        // ---------------------------------------------------------------
        $display("\n[Test 4] full non-zero MLP path -> expect class 11, fc2={8192,16384,24576,32768}");
        test_count = test_count + 1;
        set_deterministic_weights;
        for (i = 0; i < 12; i = i + 1) features_int[i] = 16'd0;
        features_int[0] = 16'd8;          // 8.0 after normalization
        run_inference;

        $display("  fc2_out[0..3] = %d %d %d %d (Q4.12 of 2,4,6,8 -> 8192,16384,24576,32768)",
                 dut.fc2_out[0], dut.fc2_out[1], dut.fc2_out[2], dut.fc2_out[3]);
        $display("  class_code = %b (expected 2'b11)", class_code);
        if (class_code == 2'b11 &&
            dut.fc2_out[0] == 32'sd8192 && dut.fc2_out[1] == 32'sd16384 &&
            dut.fc2_out[2] == 32'sd24576 && dut.fc2_out[3] == 32'sd32768) begin
            $display("  PASS (argmax + FC2 MAC + ReLU + normalization all verified)");
            pass_count = pass_count + 1;
        end else begin
            $display("  FAIL: class=%b fc2=%d %d %d %d",
                     class_code, dut.fc2_out[0], dut.fc2_out[1],
                     dut.fc2_out[2], dut.fc2_out[3]);
        end

        // ---------------------------------------------------------------
        // Test 5: ReLU clamp path
        //   fc1_w[0] = -1.0 -> fc1raw0 = -8 -> ReLU clamps hidden0 to 0.
        //   FC2 outputs all = 0*h0*w + bias(0) = 0 -> tie -> lowest index 0.
        //   class 00, and fc1_out[0] must be 0 (ReLU active).
        // ---------------------------------------------------------------
        $display("\n[Test 5] ReLU clamp (negative neuron) -> expect class 00, fc1_out[0]=0");
        test_count = test_count + 1;
        set_deterministic_weights;
        dut.fc1_weights[0] = 16'hFFFF;     // -1.0 Q4.12
        for (i = 0; i < 12; i = i + 1) features_int[i] = 16'd0;
        features_int[0] = 16'd8;
        run_inference;

        $display("  fc1_out[0] = %d (expected 0, ReLU clamped from -8)", dut.fc1_out[0]);
        $display("  class_code = %b (expected 2'b00, all-zero tie -> lowest)", class_code);
        if (dut.fc1_out[0] == 32'sd0 && class_code == 2'b00) begin
            $display("  PASS (ReLU clamp + tie-break verified)");
            pass_count = pass_count + 1;
        end else begin
            $display("  FAIL: fc1_out[0]=%d class=%b", dut.fc1_out[0], class_code);
        end

        $display("\n========================================");
        $display("Test Summary: %d/%d PASSED", pass_count, test_count);
        $display("========================================");
        $finish;
    end

    initial begin
        $dumpfile("tb_ai_classifier_math.vcd");
        $dumpvars(0, tb_ai_classifier_math);
    end

endmodule
