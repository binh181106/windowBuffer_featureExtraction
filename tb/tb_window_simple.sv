`timescale 1ns / 1ps

// =============================================================================
// Simple Testbench for Window Buffer - Debug
// =============================================================================
module tb_window_simple;

    reg clk;
    reg rst_n;
    reg enable;
    reg soft_reset;
    reg [7:0] sample_in;
    reg sample_valid;
    reg read_en;
    reg [8:0] read_addr;
    wire [7:0] frame_out;
    wire window_ready;
    wire [31:0] samples_collected;
    wire ready_bank;

    window_buffer #(
        .DATA_WIDTH(8),
        .WINDOW_SIZE(512),
        .OVERLAP(256)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .enable(enable),
        .soft_reset(soft_reset),
        .sample_in(sample_in),
        .sample_valid(sample_valid),
        .read_en(read_en),
        .read_addr(read_addr),
        .frame_out(frame_out),
        .window_ready(window_ready),
        .samples_collected(samples_collected),
        .ready_bank(ready_bank)
    );

    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    initial begin
        $dumpfile("tb_window_simple.vcd");
        $dumpvars(0, tb_window_simple);
        $dumpvars(0, dut.enable);
        $dumpvars(0, dut.sample_valid);
        $dumpvars(0, dut.write_counter);
        $dumpvars(0, dut.window_ready);
    end

    initial begin
        rst_n = 0;
        enable = 0;
        soft_reset = 0;
        sample_in = 0;
        sample_valid = 0;
        read_en = 0;
        read_addr = 0;

        #100;
        rst_n = 1;
        #50;

        $display("Test: Write 10 samples");
        enable = 1;

        repeat(10) begin
            @(posedge clk);
            sample_in = 8'hAA;
            sample_valid = 1;
            $display("t=%t enable=%b valid=%b counter=%d",
                     $time, enable, sample_valid, dut.write_counter);
            @(posedge clk);
            sample_valid = 0;
        end

        $display("After 10 samples: counter=%d samples=%d",
                 dut.write_counter, samples_collected);

        #100;
        $finish;
    end

endmodule
