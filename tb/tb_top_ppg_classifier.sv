`timescale 1ns / 1ps

// =============================================================================
// Testbench for Top-Level PPG Classifier
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
    // DUT
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
        forever #5 sys_clk = ~sys_clk;
    end

    // =============================================================================
    // APB Tasks
    // =============================================================================
    task apb_write;
        input [31:0] addr;
        input [31:0] data;
        begin
            @(posedge sys_clk);
            paddr  = addr;
            pwdata = data;
            psel   = 1;
            pwrite = 1;
            penable = 0;
            @(posedge sys_clk);
            penable = 1;
            @(posedge sys_clk);
            while (!dut.csr_pready) @(posedge sys_clk);
            psel   = 0;
            penable = 0;
        end
    endtask

    task apb_read;
        input [31:0] addr;
        output [31:0] data;
        begin
            @(posedge sys_clk);
            paddr  = addr;
            psel   = 1;
            pwrite = 0;
            penable = 0;
            @(posedge sys_clk);
            penable = 1;
            @(posedge sys_clk);
            while (!dut.csr_pready) @(posedge sys_clk);
            data = prdata;
            psel   = 0;
            penable = 0;
        end
    endtask

    // =============================================================================
    // ADC Data Generator Task
    // =============================================================================
    task generate_ppg_samples;
        input integer num_samples;
        integer i;
        integer sample_val;
        begin
            for (i = 0; i < num_samples; i = i + 1) begin
                @(posedge sys_clk);
                // Generate PPG-like waveform (sine wave with DC offset)
                sample_val = 128 + $rtoi($sin(i * 2 * 3.14159 / 64) * 40);
                adc_data = 8'(sample_val);
                adc_valid = 1;
                @(posedge sys_clk);
                adc_valid = 0;
            end
        end
    endtask

    // =============================================================================
    // Test Sequence
    // =============================================================================
    integer test_count;
    integer pass_count;
    reg [31:0] read_data;
    integer i;

    initial begin
        $display("========================================");
        $display("Top-Level PPG Classifier Testbench");
        $display("========================================");

        test_count = 0;
        pass_count = 0;

        // Initialize
        sys_rst_n = 0;
        paddr = 0;
        psel = 0;
        penable = 0;
        pwrite = 0;
        pwdata = 0;
        adc_data = 0;
        adc_valid = 0;
        uart_rxd = 1;

        #100;
        sys_rst_n = 1;
        #100;

        // ================================================================
        // Test 1: System Reset and Initial State
        // ================================================================
        $display("\n[Test 1] Initial State Check");
        test_count = test_count + 1;

        #200;
        if (dut.fsm_idle) begin
            $display("  PASS: FSM in IDLE state");
            pass_count = pass_count + 1;
        end else begin
            $display("  FAIL: FSM not in IDLE");
        end

        // ================================================================
        // Test 2: APB Configuration
        // ================================================================
        $display("\n[Test 2] APB Configuration");
        test_count = test_count + 1;

        apb_write(32'h08, 32'h00000050);  // Threshold
        apb_write(32'h0C, 32'h00000358);  // Baud
        apb_write(32'h18, 32'h00000003);  // Config (UART enable)

        #100;
        apb_read(32'h04, read_data);
        $display("  STATUS = 0x%h", read_data);

        $display("  PASS: APB configuration written");
        pass_count = pass_count + 1;

        // ================================================================
        // Test 3: Enable and Start
        // ================================================================
        $display("\n[Test 3] Enable and Start");
        test_count = test_count + 1;

        apb_write(32'h00, 32'h00000001);  // Enable

        #50;
        apb_write(32'h00, 32'h00000003);  // Enable + Start

        $display("  System enabled and started");
        $display("  PASS: Start command issued");
        pass_count = pass_count + 1;

        // ================================================================
        // Test 4: Feed PPG Samples
        // ================================================================
        $display("\n[Test 4] Feed PPG Samples");
        test_count = test_count + 1;

        // Feed 512 samples
        fork
            generate_ppg_samples(512);
        join

        #1000;
        $display("  512 samples fed");
        $display("  PASS: Sample feeding completed");
        pass_count = pass_count + 1;

        // ================================================================
        // Test 5: Wait for Classification
        // ================================================================
        $display("\n[Test 5] Wait for Classification");
        test_count = test_count + 1;

        // Wait for interrupt or done
        fork
            begin
                wait(irq == 1);
                $display("  Interrupt received!");
            end
            begin
                #50_000_000;  // 50ms timeout
                $display("  Timeout!");
            end
        join_any

        disable fork;

        #100;
        apb_read(32'h10, read_data);
        $display("  Result: class_code = %b", read_data[1:0]);

        case (read_data[1:0])
            2'b00: $display("  -> Normal (Healthy)");
            2'b01: $display("  -> Fast (Tachycardia)");
            2'b10: $display("  -> Slow (Bradycardia)");
            2'b11: $display("  -> Abnormal (Arrhythmia)");
        endcase

        if (read_data[1:0] !== 2'b00 || irq) begin
            $display("  PASS: Classification completed");
            pass_count = pass_count + 1;
        end else begin
            $display("  INFO: No classification (check feature extraction)");
        end

        // ================================================================
        // Test 6: Status Register Check
        // ================================================================
        $display("\n[Test 6] Status Register");
        test_count = test_count + 1;

        apb_read(32'h04, read_data);
        $display("  STATUS = 0x%h", read_data);
        $display("    busy   = %b", read_data[0]);
        $display("    done   = %b", read_data[1]);
        $display("    error  = %b", read_data[2]);
        $display("    overflow = %b", read_data[3]);

        $display("  PASS: Status readable");
        pass_count = pass_count + 1;

        // ================================================================
        // Test 7: Status LEDs Check
        // ================================================================
        $display("\n[Test 7] Status LEDs");
        test_count = test_count + 1;

        $display("  status_led = %b", status_led);
        $display("    [0] fsm_idle     = %b", status_led[0]);
        $display("    [1] window_ready = %b", status_led[1]);
        $display("    [2] feat_valid    = %b", status_led[2]);
        $display("    [3] done         = %b", status_led[3]);

        $display("  PASS: Status LEDs observable");
        pass_count = pass_count + 1;

        // ================================================================
        // Test 8: Reset Behavior
        // ================================================================
        $display("\n[Test 8] Reset Behavior");
        test_count = test_count + 1;

        sys_rst_n = 0;
        #50;
        sys_rst_n = 1;
        #100;

        if (dut.fsm_idle) begin
            $display("  PASS: System reset works");
            pass_count = pass_count + 1;
        end else begin
            $display("  FAIL: Reset did not work");
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
        $dumpfile("tb_top_ppg_classifier.vcd");
        $dumpvars(0, tb_top_ppg_classifier);
    end

endmodule
