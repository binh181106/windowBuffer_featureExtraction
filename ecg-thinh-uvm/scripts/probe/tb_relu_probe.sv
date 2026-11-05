`timescale 1ns/1ps
// Probe: does the MLP ReLU actually clamp a negative FC1 neuron to 0?
// Drive a known feature + negative fc1 weight, observe fc1_out_raw vs
// hidden_out vs fc1_out at S_DONE. Distinguishes "ReLU clamps" from a bug.
module tb_relu_probe;
    reg clk, rst_n, start, enable, soft_reset;
    wire [1:0] class_code; wire done; wire overflow;
    wire signed [31:0] fc1_out [0:7];
    wire signed [31:0] fc2_out [0:3];
    wire signed [15:0] features [0:11];
    reg signed [15:0] features_int [0:11];
    genvar g;
    generate
        for (g=0; g<12; g=g+1) begin : genf
            assign features[g] = features_int[g];
        end
    endgenerate

    ai_classifier #(.FEATURE_WIDTH(16),.HIDDEN_NEURONS(8),.OUTPUT_NEURONS(4)) dut (
        .clk(clk),.rst_n(rst_n),.soft_reset(soft_reset),
        .start(start),.enable(enable),.features(features),
        .class_code(class_code),.done(done),.overflow(overflow),
        .fc1_out(fc1_out),.fc2_out(fc2_out)
    );

    initial begin clk=0; forever #9.92 clk=~clk; end
    integer i;

    initial begin
        rst_n=0; start=0; enable=0; soft_reset=0;
        for (i=0;i<12;i=i+1) features_int[i]=16'd0;
        for (i=0;i<96;i=i+1) dut.fc1_weights[i]=16'd0;
        for (i=0;i<8;i=i+1)  dut.fc1_biases[i]=16'd0;
        for (i=0;i<32;i=i+1) dut.fc2_weights[i]=16'd0;
        for (i=0;i<4;i=i+1)  dut.fc2_biases[i]=16'd0;
        for (i=0;i<12;i=i+1) begin dut.mean_vals[i]=16'd0; dut.inv_scale[i]=16'd4096; end
        #100; rst_n=1; #100; enable=1;

        // fc1_w[0] = -1 raw: hidden0 = (8*4096)*(-1)>>>12 = -8 -> ReLU should clamp to 0
        dut.fc1_weights[0] = 16'hFFFF;
        features_int[0] = 16'd8;
        start=1; @(posedge clk); start=0;
        wait(done); @(posedge clk); @(posedge clk);

        $display("fc1_out_raw[0] = %d  (expect -8)", dut.fc1_out_raw[0]);
        $display("hidden_out[0]  = %d  (ReLU clamped -> expect 0)", dut.hidden_out[0]);
        $display("fc1_out[0]     = %d  (expect 0 if ReLU clamps)", dut.fc1_out[0]);
        $display("class_code     = %b  (all-zero FC2 tie -> expect 00)", class_code);
        $finish;
    end
endmodule
