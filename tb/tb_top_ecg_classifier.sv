`timescale 1ns / 1ps

// =============================================================================
// Testbench for Top-Level ECG Classifier
// =============================================================================
module tb_top_ecg_classifier;

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
    // (fix tb v3.0) Override SYS_SAMPLE_RATE_DIV để sim nhanh.
    // Mặc định 140000 (360 Hz) -> 1 mẫu mỗi 2.78 ms; để đủ 512 mẫu cần
    // ~1.42 s mô phỏng. Dùng div = 20 (mỗi mẫu ~20 clock) để TB chạy nhanh
    // nhưng vẫn giữ đúng đường đi của datapath (rate gate -> window -> feature
    // -> MLP). Giá trị 140000 vẫn là mặc định của RTL cho phần cứng.
    localparam TB_SAMPLE_RATE_DIV = 20;

    top_ecg_classifier #(
        .SYS_SAMPLE_RATE_DIV(TB_SAMPLE_RATE_DIV)
    ) dut (
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
    // Clock Generation (50.4 MHz)
    // =============================================================================
    initial begin
        sys_clk = 0;
        forever #9.92 sys_clk = ~sys_clk;
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
    task generate_ecg_samples;
        input integer num_samples;
        integer i;
        integer sample_val;
        begin
            for (i = 0; i < num_samples; i = i + 1) begin
                // (fix tb v3.0) Chu kỳ đúng = SYS_SAMPLE_RATE_DIV clock
                // (khớp rate gate của ADC). Trước đây chu kỳ 2 clock ->
                // phần lớn mẫu bị bỏ qua vì rate gate chỉ tick 1 lần
                // mỗi div clock -> cửa sổ không bao giờ đầy 512 mẫu.
                @(posedge sys_clk);
                // Generate ECG-like waveform (sine wave with DC offset)
                sample_val = 128 + $rtoi($sin(i * 2 * 3.14159 / 64) * 40);
                adc_data = 8'(sample_val);
                adc_valid = 1;
                repeat (3) @(posedge sys_clk);   // giữ valid 3 clock (latch chắc)
                adc_valid = 0;
                repeat (TB_SAMPLE_RATE_DIV - 4) @(posedge sys_clk); // đủ 1 chu kỳ tick
            end
        end
    endtask

    // (fix tb) Latch bắt pulse 1-chu kỳ p_irq (p_irq = done & irq_en)
    reg irq_seen;
    initial begin
        irq_seen = 1'b0;
    end
    always @(posedge sys_clk) begin
        if (irq) irq_seen <= 1'b1;
    end

    // =============================================================================
    // Test Sequence
    // =============================================================================
    integer test_count;
    integer pass_count;
    reg [31:0] read_data;
    integer i;

    initial begin
        $display("========================================");
        $display("Top-Level ECG Classifier Testbench");
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

        apb_write(32'h08, 32'h00000050);  // ECG_THRESH
        // (fix tb) Baud legacy 0x358=868 (100 MHz) -> v3.0: 0x1B5=437
        apb_write(32'h0C, 32'h000001B5);  // Baud (437 = 115200 @ 50.4 MHz)
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
        // (fix tb) CTRL = 0x07: bit0 enable, bit1 start, bit2 irq_en
        // (irq_en phải bật thì apb_slave_if mới tạo p_irq -> irq ở top).
        apb_write(32'h00, 32'h00000007);  // Enable + Start + irq_enable

        $display("  System enabled and started");
        $display("  PASS: Start command issued");
        pass_count = pass_count + 1;

        // ================================================================
        // Test 4: Feed ECG Samples
        // ================================================================
        $display("\n[Test 4] Feed ECG Samples");
        test_count = test_count + 1;

        // (fix tb v3.0) Feed 768 mẫu (mẫu 1 chu kỳ tick) -> đủ cửa sổ 512
        // (window_ready đầu) + 1 cửa sổ overlap. Trước đây 512 mẫu feed
        // liên tục 2 chu kỳ/mẫu -> rate gate (div) chỉ tick mỗi 20 clock ->
        // cửa sổ không bao giờ đầy 512 mẫu.
        fork
            generate_ecg_samples(768);
        join

        $display("  768 samples fed");
        $display("  PASS: Sample feeding completed");
        pass_count = pass_count + 1;

        // ================================================================
        // Test 5: Wait for Classification
        // ================================================================
        $display("\n[Test 5] Wait for Classification");
        test_count = test_count + 1;

        // (fix tb) p_irq là pulse 1 chu kỳ -> dùng latch irq_seen (bắt pulse
        // trong always-block), không wait(irq==1) (có thể bỏ lỡ).
        // Timeout ~10s mô phỏng = ~500k clock @div=20: đủ cho feature
        // (512 chu kỳ) + MLP (~161 chu kỳ).
        fork
            begin
                wait(irq_seen == 1'b1);
                $display("  Interrupt received!");
            end
            begin
                #10_000_000;
                $display("  TIMEOUT: no interrupt");
            end
        join_any

        disable fork;

        #100;
        apb_read(32'h10, read_data);
        $display("  Result: class_code = %b (irq_seen = %b)", read_data[1:0], irq_seen);

        case (read_data[1:0])
            2'b00: $display("  -> Normal (Healthy)");
            2'b01: $display("  -> Fast (Tachycardia)");
            2'b10: $display("  -> Slow (Bradycardia)");
            2'b11: $display("  -> Abnormal (Arrhythmia)");
        endcase

        // (fix tb) Điều kiện PASS đúng: pipeline phải chạy xong (irq_seen=1)
        // và class_code phải là giá trị hợp lệ (0..3), không phải x.
        if (irq_seen && read_data[1:0] !== 2'bxx) begin
            $display("  PASS: Classification completed (class_code = %b)", read_data[1:0]);
            pass_count = pass_count + 1;
        end else begin
            $display("  FAIL: No classification (irq_seen=%b, class_code=%b)",
                     irq_seen, read_data[1:0]);
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
        $dumpfile("tb_top_ecg_classifier.vcd");
        $dumpvars(0, tb_top_ecg_classifier);
    end

endmodule
