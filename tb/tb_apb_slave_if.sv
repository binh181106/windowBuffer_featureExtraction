`timescale 1ns / 1ps

// =============================================================================
// Testbench for APB Slave Interface
// =============================================================================
module tb_apb_slave_if;

    // =============================================================================
    // Clock and Reset
    // =============================================================================
    reg pclk;
    reg presetn;

    // =============================================================================
    // APB Signals
    // =============================================================================
    reg [31:0] paddr;
    reg psel;
    reg penable;
    reg pwrite;
    reg [31:0] pwdata;
    wire [31:0] prdata;
    wire pready;
    wire pslverr;

    // =============================================================================
    // Internal Control Signals
    // =============================================================================
    wire sys_enable;
    wire sys_start;
    wire [15:0] ppg_threshold;
    wire [15:0] baud_div;
    wire ble_enable;
    wire uart_enable;
    wire soft_reset;

    // Status inputs
    reg sys_busy;
    reg sys_done;
    reg [1:0] sys_class_code;
    reg sys_overflow;

    // =============================================================================
    // DUT
    // =============================================================================
    apb_slave_if #(
        .ADDR_WIDTH(8),
        .DATA_WIDTH(32)
    ) dut (
        .pclk(pclk),
        .presetn(presetn),
        .paddr(paddr),
        .psel(psel),
        .penable(penable),
        .pwrite(pwrite),
        .pwdata(pwdata),
        .prdata(prdata),
        .pready(pready),
        .pslverr(pslverr),
        .sys_enable(sys_enable),
        .sys_start(sys_start),
        .ppg_threshold(ppg_threshold),
        .baud_div(baud_div),
        .ble_enable(ble_enable),
        .uart_enable(uart_enable),
        .soft_reset(soft_reset),
        .sys_busy(sys_busy),
        .sys_done(sys_done),
        .sys_class_code(sys_class_code),
        .sys_overflow(sys_overflow)
    );

    // =============================================================================
    // Clock Generation (50 MHz)
    // =============================================================================
    initial begin
        pclk = 0;
        forever #10 pclk = ~pclk;  // 20ns period = 50MHz
    end

    // =============================================================================
    // APB Write Task
    // =============================================================================
    task apb_write;
        input [31:0] addr;
        input [31:0] data;
        begin
            paddr  = addr;
            pwdata = data;
            @(posedge pclk);
            psel   = 1;
            pwrite = 1;
            penable = 0;
            @(posedge pclk);
            penable = 1;
            @(posedge pclk);
            while (!pready) @(posedge pclk);
            psel   = 0;
            penable = 0;
        end
    endtask

    // =============================================================================
    // APB Read Task
    // =============================================================================
    task apb_read;
        input [31:0] addr;
        output [31:0] data;
        begin
            paddr  = addr;
            @(posedge pclk);
            psel   = 1;
            pwrite = 0;
            penable = 0;
            @(posedge pclk);
            penable = 1;
            @(posedge pclk);
            while (!pready) @(posedge pclk);
            data = prdata;
            psel   = 0;
            penable = 0;
        end
    endtask

    // =============================================================================
    // Test Sequence
    // =============================================================================
    reg [31:0] read_data;
    integer test_count;
    integer pass_count;

    initial begin
        $display("========================================");
        $display("APB Slave Interface Testbench");
        $display("========================================");

        // Initialize
        test_count = 0;
        pass_count = 0;

        presetn = 0;
        paddr = 0;
        psel = 0;
        penable = 0;
        pwrite = 0;
        pwdata = 0;
        sys_busy = 0;
        sys_done = 0;
        sys_class_code = 0;
        sys_overflow = 0;

        #100;
        presetn = 1;
        #100;

        $display("\n[Test 1] Write to CTRL register (enable)");
        test_count = test_count + 1;
        apb_write(32'h00, 32'h00000001);
        #50;
        if (sys_enable == 1) begin
            $display("  PASS: sys_enable = %b", sys_enable);
            pass_count = pass_count + 1;
        end else begin
            $display("  FAIL: sys_enable expected 1, got %b", sys_enable);
        end

        $display("\n[Test 2] Write to THRESH register");
        test_count = test_count + 1;
        apb_write(32'h08, 32'h00000050);
        #50;
        if (ppg_threshold == 16'h50) begin
            $display("  PASS: ppg_threshold = 0x%h", ppg_threshold);
            pass_count = pass_count + 1;
        end else begin
            $display("  FAIL: ppg_threshold expected 0x50, got 0x%h", ppg_threshold);
        end

        $display("\n[Test 3] Write to BAUD register");
        test_count = test_count + 1;
        apb_write(32'h0C, 32'h00000358);
        #50;
        if (baud_div == 16'h358) begin
            $display("  PASS: baud_div = %d", baud_div);
            pass_count = pass_count + 1;
        end else begin
            $display("  FAIL: baud_div expected 856, got %d", baud_div);
        end

        $display("\n[Test 4] Read STATUS register");
        test_count = test_count + 1;
        sys_busy = 1;
        sys_done = 0;
        apb_read(32'h04, read_data);
        #50;
        if (read_data[0] == 1) begin
            $display("  PASS: STATUS[0] (busy) = %b", read_data[0]);
            pass_count = pass_count + 1;
        end else begin
            $display("  FAIL: STATUS[0] expected 1, got %b", read_data[0]);
        end

        $display("\n[Test 5] Read VERSION register");
        test_count = test_count + 1;
        apb_read(32'h14, read_data);
        #50;
        if (read_data[15:0] == 16'h0100) begin
            $display("  PASS: VERSION = 0x%h", read_data[15:0]);
            pass_count = pass_count + 1;
        end else begin
            $display("  FAIL: VERSION expected 0x0100, got 0x%h", read_data[15:0]);
        end

        $display("\n[Test 6] Write to CONFIG register");
        test_count = test_count + 1;
        apb_write(32'h18, 32'h00000003);
        #50;
        if (ble_enable == 1 && uart_enable == 1) begin
            $display("  PASS: ble_enable = %b, uart_enable = %b", ble_enable, uart_enable);
            pass_count = pass_count + 1;
        end else begin
            $display("  FAIL: ble_enable = %b, uart_enable = %b", ble_enable, uart_enable);
        end

        $display("\n[Test 7] Start pulse (write 1 to bit 1)");
        test_count = test_count + 1;
        $display("  Writing 0x03 to CTRL (enable=1, start=1)");
        paddr = 32'h00;
        pwdata = 32'h00000003;
        @(posedge pclk);
        psel = 1; pwrite = 1; penable = 0;
        @(posedge pclk);  // SETUP phase - sys_start set here
        if (sys_start == 1) begin
            $display("  PASS: sys_start pulse detected");
            pass_count = pass_count + 1;
        end else begin
            $display("  FAIL: sys_start not detected");
        end
        penable = 1;
        @(posedge pclk);
        psel = 0; penable = 0;

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
        $dumpfile("tb_apb_slave_if.vcd");
        $dumpvars(0, tb_apb_slave_if);
    end

endmodule
