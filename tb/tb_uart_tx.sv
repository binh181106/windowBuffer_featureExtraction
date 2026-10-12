`timescale 1ns / 1ps

module tb_uart_tx;

    reg clk;
    reg rst_n;
    reg [15:0] baud_div;
    reg [7:0] tx_data;
    reg tx_start;
    reg tx_enable;
    wire tx_busy;
    wire tx_done_tick;
    wire uart_txd;

    uart_tx #(
        .CLKS_PER_BIT(10)  // Fast for simulation
    ) dut (
        .clk(clk), .rst_n(rst_n),
        .baud_div(baud_div), .tx_data(tx_data),
        .tx_start(tx_start), .tx_enable(tx_enable),
        .tx_busy(tx_busy), .tx_done_tick(tx_done_tick),
        .uart_txd(uart_txd)
    );

    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    initial begin
        $dumpfile("tb_uart_tx.vcd");
        $dumpvars(0, tb_uart_tx);
    end

    initial begin
        $display("UART TX Test");

        rst_n = 0;
        baud_div = 16'd10;
        tx_data = 8'h00;
        tx_start = 0;
        tx_enable = 1;

        #100;
        rst_n = 1;
        #100;

        // Test: Send 0x55
        tx_data = 8'h55;
        tx_start = 1;
        #10 tx_start = 0;

        wait(tx_done_tick);
        $display("TX done: 0x55");

        wait(!tx_busy);
        #100;

        $display("Test complete");
        $finish;
    end

endmodule
