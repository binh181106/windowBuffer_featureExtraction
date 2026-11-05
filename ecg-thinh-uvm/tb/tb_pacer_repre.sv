`timescale 1ns / 1ps
// =============================================================================
// Pacer representative timing probe — 50 MHz @ avg 360 Hz (board config)
// =============================================================================
// Standalone check of sample_pacer with the BOARD parameters
// (CLK_HZ=50e6, TARGET_HZ=360 -> PHASE_INC = round(2^32*360/50e6) = 30924).
// Measures the first 3 sample pulses and verifies, in one short run
// (ROM_WORDS=32, NOT the full 2048):
//   1. pulse width = exactly 1 cycle (no back-to-back valid)
//   2. each inter-pulse gap in {138887, 138888} (2^32/30924 = 138887.83)
//   3. avg rate over 2 intervals ~= 360 Hz (PHASE_INC quantizes to 360.002741
//      Hz = 50e6*30924/2^32, NOT exactly 360; +7.6 ppm)
//   4. data order = ROM[0], ROM[1], ROM[2]
//
// Counting convention (settle before asserting): `t_pulse[i] = $time/20` is
// the CYCLE INDEX at each pulse edge; `gap = t_pulse[i+1]-t_pulse[i]` is the
// cycle-index DIFFERENCE = the inter-pulse PERIOD (138887..138888 cycles).
// The number of idle cycles STRICTLY BETWEEN two pulses is `gap-1`. The check
// below asserts the period (gap), not the between-count; that is intentional
// and unchanged.
// Integer-only (no `real`, no %f) + a hard cycle budget: Questa 10.7c-safe.
// The full-pipeline FAST run (tb_demo_rom) already proves end-to-end ordering
// + no rate-gate loss; this is the timing-representative pacer proof.
// =============================================================================
module tb_pacer_repre;
    parameter int  ROM_WORDS = 32;
    parameter ROM_HEX = "../demo/ecg_rom.hex";

    reg clk = 1'b1;
    always #10 clk = ~clk;   // 20 ns period = 50 MHz

    reg rst_n = 1'b0;
    wire [4:0] rom_addr;
    wire [7:0] rom_out;
    wire [7:0] s_data;
    wire s_valid, s_eod;

    ecg_rom #( .ROM_WORDS(ROM_WORDS), .ROM_DW(8), .ROM_HEX(ROM_HEX) ) u_rom (
        .clk(clk), .rom_addr(rom_addr), .rom_out(rom_out)
    );
    sample_pacer #( .CLK_HZ(50_000_000), .TARGET_HZ(360),
                    .ROM_WORDS(ROM_WORDS), .ROM_DW(8) ) u_pacer (
        .clk(clk), .rst_n(rst_n),
        .rom_out(rom_out), .rom_addr(rom_addr),
        .sample_data(s_data), .sample_valid(s_valid), .end_of_data(s_eod)
    );

    reg [31:0] t_pulse [0:2];
    reg [7:0]  got_data [0:2];
    reg [5:0]  npulse;
    reg        pulse_wide;   // back-to-back valid => width > 1
    reg        prev_valid;

    always @(posedge clk) begin
        prev_valid <= s_valid;
        if (s_valid) begin
            if (prev_valid) pulse_wide <= 1'b1;
            if (npulse < 3) begin
                t_pulse[npulse] <= $time / 20;
                got_data[npulse] <= s_data;
                npulse <= npulse + 1;
            end
        end
    end

    reg [31:0] gap0, gap1;
    integer ok; integer c;
    integer gsum, gavg;
    initial begin
        ok = 0; c = 0;
        pulse_wide = 0; npulse = 0;
        rst_n = 0;
        repeat (4) @(posedge clk);
        rst_n = 1;
        // hard budget: 3 pulses ~= 3*138888 cycles; allow 5x for safety
        while (npulse < 3 && c < 3*138888*5) begin
            @(posedge clk);
            c = c + 1;
        end
        repeat (4) @(posedge clk);

        gap0 = t_pulse[1] - t_pulse[0];
        gap1 = t_pulse[2] - t_pulse[1];
        gsum = gap0 + gap1;
        gavg = gsum / 2;
        $display("PACER_GAP[0]=%0d [1]=%0d (expect 138887 or 138888)", gap0, gap1);
        $display("PACER_AVG gap=%0d cycles -> %0d Hz (=50e6*2/%0d... )", gavg, 0, gavg);
        // integer Hz over 2 intervals: 50e6 * 2 / gsum
        $display("PACER_RATE = 50e6 * 2 / %0d = %0d Hz (expect ~360)",
                 gsum, 100_000_000 / gsum);

        if (gap0 == 138887 || gap0 == 138888) begin $display("  gap0 OK"); ok = ok + 1; end
        else $display("  FAIL gap0=%0d", gap0);
        if (gap1 == 138887 || gap1 == 138888) begin $display("  gap1 OK"); ok = ok + 1; end
        else $display("  FAIL gap1=%0d", gap1);
        if ((100_000_000 / gsum) >= 359 && (100_000_000 / gsum) <= 361)
            begin $display("  rate OK"); ok = ok + 1; end
        else $display("  FAIL rate=%0d", 100_000_000 / gsum);
        if (!pulse_wide) begin $display("PACER width OK (single-cycle pulses)"); ok = ok + 1; end
        else $display("PACER FAIL: back-to-back valid");

        $display("PACER data order: %0d %0d %0d", got_data[0], got_data[1], got_data[2]);
        if (got_data[0] == 8'h20 && got_data[1] == 8'h20 && got_data[2] == 8'h21)
            begin $display("  data order OK"); ok = ok + 1; end
        else $display("  FAIL data order (expect 20 20 21)");

        if (ok == 5) $display("Test Summary: 5/5 PASSED");
        else         $display("Test Summary: %0d/5 FAILED", ok);
        #100;
        $finish;
    end
endmodule
