`timescale 1ns / 1ps

// =============================================================================
// Testbench for PPG Classifier Top Level
// =============================================================================

module tb_top_ppg_classifier;

    // =============================================================================
    // Clock and Reset
    // =============================================================================
    reg sys_clk;
    reg sys_rst_n;

    // =============================================================================
    // APB Interface
    // =============================================================================
    reg [31:0] paddr;
    reg psel;
    reg penable;
    reg pwrite;
    reg [31:0] pwdata;
    wire [31:0] prdata;

    // =============================================================================
    // ADC Interface
    // =============================================================================
    reg [7:0] adc_data;
    reg adc_valid;

    // =============================================================================
    // UART Interface
    // =============================================================================
    wire uart_txd;
    reg uart_rxd;

    // =============================================================================
    // Interrupt
    // =============================================================================
    wire irq;

    // =============================================================================
    // Status LEDs
    // =============================================================================
    wire [3:0] status_led;

    // =============================================================================
    // Instantiate DUT
    // =============================================================================
    top_ppg_classifier dut (
        .sys_clk(sys_clk),
        .sys_rst_n(sys_rst_n),
        .paddr(paddr),
        .psel(psel),
        .penable(penable),
        .pwrite(pwrite),
        .pwdata(pwdata),
        .prdata(prdata),
        .adc_data(adc_data),
        .adc_valid(adc_valid),
        .uart_txd(uart_txd),
        .uart_rxd(uart_rxd),
        .irq(irq),
        .status_led(status_led)
    );

    // =============================================================================
    // Clock Generation (100 MHz)
    // =============================================================================
    initial begin
        sys_clk = 0;
        forever #5 sys_clk = ~sys_clk;  // 10 ns period = 100 MHz
    end

    // =============================================================================
    // Reset Sequence
    // =============================================================================
    initial begin
        sys_rst_n = 0;
        #100;
        sys_rst_n = 1;
    end

    // =============================================================================
    // APB Write Task
    // =============================================================================
    task apb_write;
        input [31:0] addr;
        input [31:0] data;
        begin
            @(posedge sys_clk);
            paddr = addr;
            pwdata = data;
            psel = 1;
            pwrite = 1;
            penable = 0;
            @(posedge sys_clk);
            penable = 1;
            @(posedge sys_clk);
            psel = 0;
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
            @(posedge sys_clk);
            paddr = addr;
            psel = 1;
            pwrite = 0;
            penable = 0;
            @(posedge sys_clk);
            penable = 1;
            @(posedge sys_clk);
            data = prdata;
            psel = 0;
            penable = 0;
        end
    endtask

    // =============================================================================
    // ADC Data Generator
    // =============================================================================
    reg [7:0] sample_counter;
    initial begin
        adc_data = 0;
        adc_valid = 0;
        sample_counter = 0;

        wait(sys_rst_n == 1);
        wait(dut.fsm_idle == 1);
        #100;

        forever begin
            // Generate PPG-like waveform (sine wave approximation)
            sample_counter = sample_counter + 8'd1;
            adc_data = 128 + $signed($sin(sample_counter * 2 * 3.14159 / 64) * 50);
            adc_valid = 1;
            #20000;  // 250 Hz sample rate (4 ms)
            adc_valid = 0;
            #20000;
        end
    end

    // =============================================================================
    // Test Sequence
    // =============================================================================
    reg [31:0] read_data;
    initial begin
        $display("=================================================");
        $display("PPG Classifier Testbench Started");
        $display("=================================================");

        // Wait for reset
        wait(sys_rst_n == 1);
        $display("[%t] Reset released", $time);

        // Wait for idle
        wait(dut.fsm_idle == 1);
        $display("[%t] FSM IDLE", $time);

        // Configure system
        #100;
        $display("[%t] Configuring PPG threshold...", $time);
        apb_write(32'h08, 32'h00000050);  // Threshold = 80

        $display("[%t] Configuring UART baud rate...", $time);
        apb_write(32'h0C, 32'h00000358);  // 115200 @ 100MHz

        $display("[%t] Enabling system...", $time);
        apb_write(32'h00, 32'h00000001);  // Enable

        // Start classification
        #100;
        $display("[%t] Starting classification...", $time);
        apb_write(32'h00, 32'h00000002);  // Start

        // Wait for completion
        fork
            begin
                wait(irq == 1);
                $display("[%t] Classification complete!", $time);
            end
            begin
                #10_000_000;  // Timeout 10 ms
                $display("[%t] TIMEOUT!", $time);
            end
        join_any

        // Read result
        #100;
        apb_read(32'h10, read_data);
        $display("[%t] Result: %b (class_code)", $time, read_data[1:0]);

        case (read_data[1:0])
            2'b00: $display("  -> Normal (Healthy)");
            2'b01: $display("  -> Fast (Tachycardia)");
            2'b10: $display("  -> Slow (Bradycardia)");
            2'b11: $display("  -> Abnormal (Arrhythmia)");
        endcase

        // Read status
        apb_read(32'h04, read_data);
        $display("[%t] Status: %h", $time, read_data);

        #1000;
        $display("=================================================");
        $display("Testbench Complete");
        $display("=================================================");
        $finish;
    end

    // =============================================================================
    // Waveform Dump
    // =============================================================================
    initial begin
        $dumpfile("tb_top_ppg_classifier.vcd");
        $dumpvars(0, tb_top_ppg_classifier);
    end

    // =============================================================================
    // Status Monitor
    // =============================================================================
    always @(posedge sys_clk) begin
        if (dut.fsm_idle)
            $display("[%t] FSM: IDLE", $time);
        else if (dut.current_state == 4'd1)
            $display("[%t] FSM: LOAD", $time);
        else if (dut.current_state == 4'd2)
            $display("[%t] FSM: NORM", $time);
    end

endmodule
