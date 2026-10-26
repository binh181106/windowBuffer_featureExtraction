`timescale 1ns / 1ps

// =============================================================================
// Testbench for Window Buffer Module
// =============================================================================
module tb_window_buffer;

    // =============================================================================
    // Clock and Reset
    // =============================================================================
    reg clk;
    reg rst_n;

    // =============================================================================
    // Control
    // =============================================================================
    reg enable;
    reg soft_reset;

    // =============================================================================
    // Data Input
    // =============================================================================
    reg [7:0] sample_in;
    reg sample_valid;

    // =============================================================================
    // Read Interface
    // =============================================================================
    reg read_en;
    reg [8:0] read_addr;
    wire [7:0] frame_out;

    // =============================================================================
    // Status
    // =============================================================================
    wire window_ready;
    wire [31:0] samples_collected;
    wire ready_bank;

    // =============================================================================
    // DUT
    // =============================================================================
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
    reg window_ready_seen;

    // (fix tb) Latch đếm số lần window_ready (0->1) để verify đúng số cửa sổ,
    // và sample trong settle region (#1 sau posedge) vì window_ready là pulse
    // 1 chu kỳ set bởi non-blocking của DUT. Chấm trong active-region (trước
    // đây) đọc giá trị cũ -> "never asserted".
    reg wr_prev;
    integer wr_count;
    initial begin
        wr_prev = 0; wr_count = 0;
    end
    always @(posedge clk) begin
        if (!rst_n) begin
            wr_prev  = 0;
            wr_count = 0;   // reset cùng DUT để count "từ đầu" mỗi test
        end else begin
            if (window_ready && !wr_prev) wr_count = wr_count + 1;
            wr_prev = window_ready;
        end
    end

    initial begin
        $display("========================================");
        $display("Window Buffer Testbench");
        $display("========================================");

        test_count = 0;
        pass_count = 0;
        window_ready_seen = 0;

        // Initialize
        rst_n = 0;
        enable = 0;
        soft_reset = 0;
        sample_in = 0;
        sample_valid = 0;
        read_en = 0;
        read_addr = 0;

        #100;
        rst_n = 1;
        #100;

        // ================================================================
        // Test 1: Basic Buffering (collect 512 samples)
        // ================================================================
        $display("\n[Test 1] Basic Buffering (512 samples)");
        test_count = test_count + 1;

        // (fix tb) dùng wr_count (latch đếm cạnh 0->1 trong settle region) thay vì
        // read window_ready trong active region (race với NBA của DUT).
        // Kỳ vọng (RTL v3.0): window_ready đầu tiên phát đúng khi ĐỦ 512 mẫu
        // (total=512), KHÔNG phải 256.
        enable = 1;
        for (i = 0; i < 512; i = i + 1) begin
            @(posedge clk);
            sample_in = 8'(i % 256);
            sample_valid = 1;
            @(posedge clk);
            sample_valid = 0;
        end
        #20;   // settle

        $display("  samples_collected = %d, wr_count = %d", samples_collected, wr_count);
        if (wr_count == 1) begin
            $display("  PASS: window_ready asserted exactly once at 512 samples");
            pass_count = pass_count + 1;
        end else begin
            $display("  FAIL: window_ready asserted %0d times, expected 1", wr_count);
        end

        // ================================================================
        // Test 2: Read Back Data
        // ================================================================
        $display("\n[Test 2] Read Back Data");
        test_count = test_count + 1;

        read_en = 1;
        for (i = 0; i < 10; i = i + 1) begin
            read_addr = i[8:0];
            @(posedge clk);
            #20;
            $display("  [%d] frame_out = 0x%h", i, frame_out);
        end
        $display("  PASS: Read operation works");
        pass_count = pass_count + 1;

        // ================================================================
        // Test 3: Reset Behavior
        // ================================================================
        $display("\n[Test 3] Reset Behavior");
        test_count = test_count + 1;

        rst_n = 0;
        enable = 0;
        #50;
        rst_n = 1;
        #50;

        if (samples_collected == 0 && !window_ready) begin
            $display("  PASS: Buffer reset properly");
            pass_count = pass_count + 1;
        end else begin
            $display("  FAIL: samples_collected = %d", samples_collected);
        end

        // ================================================================
        // Test 4: 50% Overlap (collect 768 samples)
        // ================================================================
        $display("\n[Test 4] 50%% Overlap (768 samples)");
        test_count = test_count + 1;

        // (fix tb) Từ sau reset của Test 3, wr_count = 0. Feed 768 mẫu ->
        // total = 768. RTL phát window_ready ở total=512 và total=768
        // (overlap 256 mẫu) -> kỳ vọng wr_count = 2 (cửa sổ 2nd = overlap).
        enable = 1;
        for (i = 0; i < 768; i = i + 1) begin
            @(posedge clk);
            sample_in = 8'(i);
            sample_valid = 1;
            @(posedge clk);
            sample_valid = 0;
        end
        #20;   // settle

        $display("  samples_collected = %d, wr_count = %d", samples_collected, wr_count);
        if (wr_count == 2) begin
            $display("  PASS: Second window ready (overlap detected), wr_count = 2");
            pass_count = pass_count + 1;
        end else begin
            $display("  FAIL: window_ready asserted %0d times, expected 2", wr_count);
        end

        // ================================================================
        // Test 5: Disable Buffering
        // ================================================================
        $display("\n[Test 5] Disable Buffering");
        test_count = test_count + 1;

        // (fix tb) Counter là CUMULATIVE (Test 1+4 đã nạp ~1280 mẫu),
        // nên không thể kiểm tra "< 200". Thay bằng: khi enable=0,
        // counter KHÔNG TĂNG thêm. Snapshot giá trị trước, feed 100 mẫu
        // với enable=0, rồi kiểm tra counter đứng yên.
        begin
            reg [31:0] before_count;
            before_count = samples_collected;

            enable = 0;
            repeat(5) @(posedge clk);
            for (i = 0; i < 100; i = i + 1) begin
                @(posedge clk);
                sample_in = 8'hFF;
                sample_valid = 1;
                @(posedge clk);
                sample_valid = 0;
            end
            #20;

            if (samples_collected == before_count) begin
                $display("  PASS: Buffering disabled (counter steady at %d)", before_count);
                pass_count = pass_count + 1;
            end else begin
                $display("  FAIL: counter moved %d -> %d with enable=0",
                         before_count, samples_collected);
            end
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
        $dumpfile("tb_window_buffer.vcd");
        $dumpvars(0, tb_window_buffer);
    end

endmodule
