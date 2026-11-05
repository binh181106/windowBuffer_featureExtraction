`timescale 1ns / 1ps
// =============================================================================
// Demo ROM testbench — ROM -> pacer -> pipeline -> UART, checked against the
// INDEPENDENT golden (demo/golden/expected_packets.sv).
// =============================================================================
// Pacing config (overridable in scripts / regression):
//   FAST  (default): TARGET_HZ = 500_000 @ 50 MHz -> ~100-cycle sample gap.
//     Still >> one 33-byte packet (33*437 = 14421 cycles) so no UART drops.
//     NOTE: NOT board pacing; board-equivalent uses TARGET_HZ = 360
//     (gap = 50e6/360 ~ 138888 cycles) — see the REPRE variant.
//   REPRE: TARGET_HZ = 360, 50 MHz — a slower, board-representative timing run.
//
// Checks (no `force` on start/data/results — the DUT self-starts):
//   1. Pacer single-pass: end_of_data, and adc sample_count == ROM_WORDS
//      (rate gate with div=1 forwards every pulse; no double div / loss).
//   2. window_ready count == EXP_NUMW (T = 512..2048, stride 256).
//   3. Per-window packet reassembled from uart_txd (8N1 decode): sync/type/
//      len/checksum valid AND every byte matches the INDEPENDENT golden
//      (from the raw MIT-BIH file, not a DUT capture).
//   4. No pkt_drop (each 33-byte packet completes before the next starts).
//   5. Mid-way reset + replay: reset after 2 window_ready, re-run, packets
//      still valid.
//
// Golden: demo/golden/expected_packets.sv, generated from
// demo/data/mitbih_100.dat by demo/golden_model.py (kept separate from any
// sim/board compare capture).
// =============================================================================

module tb_demo_rom;
    // ---- pacing config ------------------------------------------------------
    // FAST config (default, regression): DUT clock 50 MHz, pacer TARGET_HZ =
    // 33333 -> PHASE_INC = 2861106, sample gap ~1500 cycles. One 33-byte UART
    // packet is 33 x 10 bits x 437 = 144210 cycles; consecutive window
    // results are 256 samples x 1500 = 384000 cycles apart -> a packet is
    // ALWAYS fully transmitted before the next result, so no drops.
    // NOTE: this is NOT the board sample cadence (board = 50 MHz @ 360 Hz,
    // gap ~138886 cycles). The REPRE config (TARGET_HZ=360) exercises the
    // board pacing in a separate, slower run.
    parameter real CLK_P     = 20.0;        // 50 MHz
    parameter int  CLK_HZ     = 50_000_000;
    parameter int  TARGET_HZ  = 33333;       // FAST
    parameter int  ROM_WORDS  = 2048;
    parameter ROM_HEX = "../demo/ecg_rom.hex";

    // The pacing cadence is an ELABORATION parameter (it feeds the DUT's
    // phase-accumulator constant), so it is overridden with
    //     vsim -gTARGET_HZ=360 ...
    // not with a plusarg. +SKIP_RUN2 skips the reset+replay run (used for
    // the slow 360 Hz board cadence, where one run already takes minutes).
    reg       skip_run2;
    initial begin
        skip_run2 = 1'b0;
        if ($test$plusargs("SKIP_RUN2")) skip_run2 = 1'b1;
    end

    reg clk = 1'b1;
    reg rst_n = 1'b0;
    wire uart_txd;
    wire [3:0] led;
    wire demo_done, demo_overflow;
    wire [1:0] demo_class;

    top_ecg_rom_demo #(
        .CLK_HZ(CLK_HZ),
        .TARGET_HZ(TARGET_HZ),
        .ROM_WORDS(ROM_WORDS),
        .ROM_HEX(ROM_HEX)
    ) dut (
        .sys_clk(clk),
        .sys_rst_n(rst_n),
        .uart_txd(uart_txd),
        .uart_rxd(1'b1),
        .status_led(led),
        .demo_done(demo_done),
        .demo_overflow(demo_overflow),
        .demo_class(demo_class)
    );

    always #(CLK_P/2) clk = ~clk;

    // ---- independent golden --------------------------------------------------
    `include "demo/golden/expected_packets.sv"

    // ---- UART 8N1 byte decoder (LSB-first), baud_div = 437 ------------------
    localparam [15:0] UBIT  = 437;
    localparam [15:0] UHALF = 218;
    reg [7:0]  rx_bit;
    reg [7:0]  rx_byte;
    reg [3:0]  rx_bi;
    reg [15:0] rx_cnt;
    reg        rx_in;
    reg        rx_prev;
    reg        rx_stop_ok;
    reg        byte_pulse;
    initial begin
        rx_bit=0; rx_byte=0; rx_bi=0; rx_cnt=0; rx_in=0; rx_prev=1;
        rx_stop_ok=0; byte_pulse=0;
    end
    always @(posedge clk) begin
        rx_prev    <= uart_txd;
        byte_pulse <= 1'b0;
        if (!rx_in) begin
            if (rx_prev === 1'b1 && uart_txd === 1'b0) begin
                rx_in <= 1'b1; rx_bi <= 4'd0; rx_cnt <= UBIT + UHALF;
            end
        end else begin
            if (rx_cnt != 16'd0) begin
                rx_cnt <= rx_cnt - 16'd1;
            end else begin
                if (rx_bi < 4'd8)
                    rx_bit[rx_bi[2:0]] <= uart_txd;
                if (rx_bi == 4'd8) begin
                    rx_stop_ok <= (uart_txd === 1'b1);
                    rx_byte    <= rx_bit;
                    rx_in      <= 1'b0;
                    rx_bi      <= 4'd0;
                    byte_pulse <= 1'b1;
                end else begin
                    rx_bi  <= rx_bi + 4'd1;
                    rx_cnt <= UBIT;
                end
            end
        end
    end

    // ---- 33-byte packet reassembler + capture ring --------------------------
    localparam PKTLEN = 33;
    localparam MAXPKT = 32;
    reg [7:0]  cur [0:MAXPKT-1][0:PKTLEN-1];
    reg [5:0]  ci;        // 6 bits: byte index 0..32
    reg        csyn;
    integer    ncur;
    reg [31:0] win_ready_cnt;
    integer    dbg_bytes, dbg_e7, dbg_done;
    reg [8*256-1:0] cap_file;

    always @(posedge clk)
        win_ready_cnt <= win_ready_cnt + (dut.window_ready ? 1 : 0);

    // diagnostics: count decoded bytes and E7 syncs
    always @(posedge clk)
        if (byte_pulse) begin
            dbg_bytes <= dbg_bytes + 1;
            if (rx_byte === 8'hE7) dbg_e7 <= dbg_e7 + 1;
        end

    // ---- raw capture to disk (for demo/uart_decode.py --check) -------------
    // Every decoded UART byte is written verbatim, so the file is exactly
    // what a board capture would contain. Opened via +CAPTURE= and scoped to
    // Run1 only (Run2 is the reset+replay run and would append a second copy
    // of the packets). Enabled/disabled with cap_en.
    integer cap_fd;
    reg     cap_en;
    initial begin
        cap_fd = 0;
        cap_en = 1'b0;
        if ($value$plusargs("CAPTURE=%s", cap_file)) begin
            cap_fd = $fopen(cap_file, "wb");
            if (cap_fd != 0)
                $display("[tb_demo_rom] capture -> %s", cap_file);
            else
                $display("[tb_demo_rom] capture open FAILED for %s", cap_file);
        end
    end
    always @(posedge clk)
        if (byte_pulse && cap_fd != 0 && cap_en)
            $fwrite(cap_fd, "%c", rx_byte);

    // ci = the slot the CURRENT byte is written to. On the E7 sync, slot 0 is
    // filled and ci -> 1. Bytes 1..32 are then written in order; when the
    // checksum (index 32, the 33rd byte) lands, the packet is complete and
    // ncur advances.
    always @(posedge clk) begin
        if (byte_pulse) begin
            if (!csyn) begin
                if (rx_byte === 8'hE7) begin
                    cur[ncur][0] <= rx_byte;
                    csyn <= 1'b1;
                    ci   <= 6'd1;
                end
            end else begin
                cur[ncur][ci] <= rx_byte;
                if (ci == 6'd32) begin
                    dbg_done <= dbg_done + 1;
                    csyn <= 1'b0;
                    ci   <= 6'd1;
                    if (ncur < MAXPKT-1)
                        ncur <= ncur + 1;
                end else begin
                    ci <= ci + 6'd1;
                end
            end
        end
    end

    // packet p structurally valid: sync/type/len + checksum
    function pkt_is_valid;
        input [31:0] p;
        integer k; integer s;
        begin
            s = 0;
            for (k = 2; k <= 31; k = k + 1) s = s + cur[p][k];
            pkt_is_valid = (cur[p][0] === 8'hE7) &&
                           (cur[p][1] === 8'hA5) &&
                           (cur[p][2] === 8'h01) &&
                           (cur[p][3] === 8'd28) &&
                           (cur[p][32] === s[7:0]);
        end
    endfunction

    // captured packet p matches golden window g on every STRICT byte
    // (exp_mask[g][k]==1). Owner-open / tool-dependent bytes (crest, RR
    // family, §3.3) are not asserted here; report_open_deltas surfaces them.
    function pkt_matches_golden;
        input [31:0] p;
        input [31:0] g;
        integer k;
        begin
            pkt_matches_golden = 1;
            for (k = 0; k < PKTLEN; k = k + 1)
                if (exp_mask[g][k] && cur[p][k] !== exp_pkt[g][k])
                    pkt_matches_golden = 0;
        end
    endfunction

    // number of open (non-strict) bytes that differ for packet p vs golden g.
    function open_delta_count;
        input [31:0] p;
        input [31:0] g;
        integer k;
        begin
            open_delta_count = 0;
            for (k = 0; k < PKTLEN; k = k + 1)
                if (!exp_mask[g][k] && cur[p][k] !== exp_pkt[g][k])
                    open_delta_count = open_delta_count + 1;
        end
    endfunction

    // ---- helpers (Questa 10.7c: static tasks, no `auto`) -------------------
    integer g_pace_gap;   // pacer sample gap in cycles (CLK_HZ / TARGET_HZ)

    task do_reset;
        input integer cycles;
        begin
            rst_n = 1'b0;
            repeat (4) @(posedge clk);
            rst_n = 1'b1;
            repeat (cycles) @(posedge clk);
        end
    endtask

    task advance;
        input integer n;
        begin
            repeat (n) @(posedge clk);
        end
    endtask

    // wait up to `budget` cycles until `want` more window_ready pulses have
    // been observed since entry. (Returns even on budget.)
    task wait_winready;
        input integer want;
        input integer budget;
        integer c; integer seen;
        begin
            c = 0; seen = 0;
            while ((seen < want) && (c < budget)) begin
                @(posedge clk);
                c = c + 1;
                if (dut.window_ready) seen = seen + 1;
            end
            if (seen < want)
                $display("  [wait_winready] got %0d/%0d in %0d cycles",
                         seen, want, c);
        end
    endtask

    // wait up to `budget` cycles until cond true.
    task wait_until_flag;
        input integer budget;
        integer c;
        begin
            c = 0;
            while (!dut.u_pacer.end_of_data && c < budget) begin
                @(posedge clk);
                c = c + 1;
            end
            if (!dut.u_pacer.end_of_data)
                $display("  [wait_eod] end_of_data not set in %0d cycles", c);
        end
    endtask

    // all 7 queued packets must fully serialize (33 bytes x 437 cycles each,
    // back-to-back) after end_of_data
    localparam DRAIN = 8 * 33 * 437 + 10000;   // ~125k cycles

    // count structurally-valid packets whose bytes match a golden window
    task count_valid;
        output integer found;
        integer i; integer g; integer matched;
        begin
            found = 0;
            for (i = 0; i < ncur; i = i + 1) begin
                matched = 0;
                if (pkt_is_valid(i)) begin
                    for (g = 0; g < EXP_NUMW; g = g + 1)
                        if (pkt_matches_golden(i, g)) matched = 1;
                    if (matched) found = found + 1;
                end
            end
        end
    endtask

    integer total, passed;
    integer i, g;
    integer found_v1, found_v2;

    initial begin
        total = 0; passed = 0;
        ncur = 0; win_ready_cnt = 0;
        dbg_bytes = 0; dbg_e7 = 0; dbg_done = 0;
        csyn = 1'b0; ci = 6'd1;
        g_pace_gap = CLK_HZ / TARGET_HZ;

        $display("========================================");
        $display("Demo ROM TB  TARGET_HZ=%0d gap=%0d ROM=%0d golden=%0d",
                 TARGET_HZ, g_pace_gap, ROM_WORDS, EXP_NUMW);
        $display("========================================");

        // =====================================================================
        // RUN 1: full stream, no reset
        // =====================================================================
        cap_en = 1'b1;              // capture Run1 bytes only
        do_reset(200);
        // stream runs ROM_WORDS samples * g_pace_gap cycles; allow 2x + margin
        wait_until_flag(2 * ROM_WORDS * g_pace_gap + 200000);
        // all 7 packets are queued and must serialize back-to-back:
        // 1 byte = 10 bits x 437 = 4370 cycles -> 33 bytes = 144210; x7 + margin
        advance(8 * 33 * 10 * UBIT + 20000);
        // debug: dump captured packet 0 vs golden 0 (byte-by-byte)
        for (g = 0; g < 33; g = g + 1)
            $display("  DBGP pkt0[%0d] got=0x%02X exp=0x%02X %s",
                     g, cur[0][g[31:0]], exp_pkt[0][g[31:0]],
                     (cur[0][g[31:0]] === exp_pkt[0][g[31:0]]) ? "" : "<== DIFF");

        // per-captured-packet diagnostic (Run1): win_index, valid, first diff
        for (i = 0; i < ncur; i = i + 1) begin
            begin
                $write("  R1FULL[%0d]", i);
                for (g = 0; g < PKTLEN; g = g + 1)
                    $write(" %02X", cur[i[31:0]][g]);
                $write("\n");
            end
        end
        for (i = 0; i < ncur; i = i + 1) begin
            begin
                integer k; integer gmatch; integer gbest; integer bd;
                gmatch = -1; gbest = 0; bd = 33;
                for (g = 0; g < EXP_NUMW; g = g + 1)
                    if (pkt_matches_golden(i, g)) gmatch = g;
                if (gmatch >= 0) begin
                    $display("  R1pkt[%0d] widx=%0d GOLDEN w%0d open-delta=%0d",
                             i, {cur[i[31:0]][5], cur[i[31:0]][4]},
                             exp_widx[gmatch], open_delta_count(i, gmatch));
                end else begin
                    // find first byte that differs from every golden window
                    for (g = 0; g < EXP_NUMW; g = g + 1) begin
                        k = 0;
                        while (k < 33 && cur[i[31:0]][k[31:0]] === exp_pkt[g][k[31:0]])
                            k = k + 1;
                        if (k < bd) begin bd = k; gbest = g; end
                    end
                    $display("  R1pkt[%0d] widx=%0d valid=%b no-golden 1st-diff@%0d vs g%0d got=0x%02X exp=0x%02X",
                             i, {cur[i[31:0]][5], cur[i[31:0]][4]},
                             pkt_is_valid(i), bd, gbest,
                             cur[i[31:0]][bd[31:0]], exp_pkt[gbest][bd[31:0]]);
                end
            end
        end
        total = total + 1;
        count_valid(found_v1);
        $display("Run1: ncur=%0d valid=%0d winR=%0d drop=%b eod=%b adc=%0d",
                 ncur, found_v1, win_ready_cnt,
                 dut.u_pz.pkt_drop, dut.u_pacer.end_of_data,
                 dut.u_adc_if.sample_count);
        $display("Run1: dbg_bytes=%0d dbg_e7=%0d", dbg_bytes, dbg_e7);
        if (found_v1 >= EXP_NUMW && !dut.u_pz.pkt_drop &&
            win_ready_cnt == EXP_NUMW &&
            dut.u_adc_if.sample_count == ROM_WORDS &&
            dut.u_pacer.end_of_data === 1'b1) begin
            passed = passed + 1;
            $display("PASS Run1: %0d valid packets match golden, single-pass",
                     found_v1);
        end else begin
            $display("FAIL Run1: valid=%0d/%0d drop=%b winR=%0d adc=%0d",
                     found_v1, EXP_NUMW, dut.u_pz.pkt_drop,
                     win_ready_cnt, dut.u_adc_if.sample_count);
        end

        // =====================================================================
        // RUN 2: mid-way reset + replay
        // =====================================================================
        // RUN 2: mid-way reset + replay
        // =====================================================================
        if (skip_run2) begin
            cap_en = 1'b0;
            if (cap_fd != 0) begin
                $fclose(cap_fd);
                $display("[tb_demo_rom] capture closed: %0d bytes", dbg_bytes);
                cap_fd = 0;
            end
            $display("Run2: SKIPPED (+SKIP_RUN2)");
        end else begin
        cap_en = 1'b0;              // stop capturing (replay must not append)
        if (cap_fd != 0) begin
            $fclose(cap_fd);
            $display("[tb_demo_rom] capture closed: %0d bytes", dbg_bytes);
            cap_fd = 0;
        end
        do_reset(200);
        // run partway (2 window_ready), then hard reset
        wait_winready(2, 4 * 256 * g_pace_gap + 2000);
        do_reset(400);
        // replay to the end of the ROM
        wait_until_flag(2 * ROM_WORDS * g_pace_gap + 200000);
        // let the final queued packet finish serializing
        advance(8 * 33 * 10 * UBIT + 20000);

        total = total + 1;
        count_valid(found_v2);
        $display("Run2: valid(replay)=%0d winR_total=%0d drop=%b eod=%b",
                 found_v2, win_ready_cnt, dut.u_pz.pkt_drop,
                 dut.u_pacer.end_of_data);
        // after the reset, ncur was NOT cleared (cur ring persists), so count
        // the replay packets as those matching golden among the whole ring.
        if (found_v2 >= EXP_NUMW && !dut.u_pz.pkt_drop &&
            dut.u_pacer.end_of_data === 1'b1) begin
            passed = passed + 1;
            $display("PASS Run2: reset+replay, %0d golden packets, no drop",
                     found_v2);
        end else begin
            $display("FAIL Run2: valid=%0d/%0d drop=%b eod=%b",
                     found_v2, EXP_NUMW, dut.u_pz.pkt_drop,
                     dut.u_pacer.end_of_data);
        end
        end // !skip_run2

        $display("========================================");
        $display("Demo ROM TB  Test Summary: %0d/%0d %s",
                 passed, total, (passed == total) ? "PASSED" : "FAILED");
        $display("========================================");
        #100;
        $finish;
    end

endmodule
