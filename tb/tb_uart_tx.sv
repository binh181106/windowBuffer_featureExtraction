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
        forever #9.92 clk = ~clk;  // 19.84ns period = 50.4MHz
    end

    initial begin
        $dumpfile("tb_uart_tx.vcd");
        $dumpvars(0, tb_uart_tx);
    end

    // (fix tb v3.0) Self-checking: decode từng bit trên uart_txd (start +
    // 8 data LSB-first) và so với byte gốc. Trước đây TB chỉ in
    // "TX done" mà không check dữ liệu -> không detect lỗi bit.
    // baud_div ở đây là tham số DUT; task dùng giá trị reg baud_div của TB
    // (khớp DUT sau khi latch). Mỗi bit = baud_div chu kỳ clk.
    integer test_count, pass_count;
    reg [7:0] rx_byte;

    task uart_read_byte;
        output [7:0] data;
        integer bi;
        begin
            data = 8'h00;
            // Chờ start bit (txd giảm từ idle-high)
            wait(uart_txd == 1'b0);
            // Về trung tâm bit start (bỏ nửa bit đầu)
            repeat (baud_div / 2) @(posedge clk);
            // 8 data bits, LSB first, lấy mẫu tại trung tâm mỗi bit
            for (bi = 0; bi < 8; bi = bi + 1) begin
                repeat (baud_div) @(posedge clk);
                data[bi] = uart_txd;
            end
        end
    endtask

    initial begin
        $display("UART TX Test");
        test_count = 0;
        pass_count = 0;

        rst_n = 0;
        baud_div = 16'd10;
        tx_data = 8'h00;
        tx_start = 0;
        tx_enable = 1;

        #100;
        rst_n = 1;
        #100;

        // Test 1: Send 0x55, decode lại (start + 8 bit + stop)
        test_count = test_count + 1;
        tx_data = 8'h55;
        tx_start = 1;
        @(posedge clk); tx_start = 0;

        uart_read_byte(rx_byte);
        if (rx_byte == 8'h55) begin
            $display("  PASS: decoded byte = 0x%h (expected 0x55)", rx_byte);
            pass_count = pass_count + 1;
        end else begin
            $display("  FAIL: decoded byte = 0x%h, expected 0x55", rx_byte);
        end
        wait(tx_done_tick);

        // Test 2: Send byte có pattern LSB/MSB khác nhau (0x81: bit0=1, bit7=1)
        test_count = test_count + 1;
        tx_data = 8'h81;
        tx_start = 1;
        @(posedge clk); tx_start = 0;

        uart_read_byte(rx_byte);
        if (rx_byte == 8'h81) begin
            $display("  PASS: decoded byte = 0x%h (expected 0x81)", rx_byte);
            pass_count = pass_count + 1;
        end else begin
            $display("  FAIL: decoded byte = 0x%h, expected 0x81", rx_byte);
        end
        wait(tx_done_tick);

        $display("\n========================================");
        $display("Test Summary: %d/%d PASSED", pass_count, test_count);
        $display("========================================");

        wait(!tx_busy);
        #100;
        $finish;
    end

endmodule
