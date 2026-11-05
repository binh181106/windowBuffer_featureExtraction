`timescale 1ns / 1ps
// =============================================================================
// Demo STATUS testbench — APB STATUS readback in idle / busy / overflow
// =============================================================================
// Proves, via REAL APB transactions on the demo's internal APB bus:
//   T1 IDLE:      STATUS reads 0x0000_0000 (busy=0, done=0, overflow=0) while
//                 the FSM sits in S_IDLE (checked after the stream drained,
//                 because bring-up starts the FSM ~12 cycles after reset, and
//                 an earlier hijack would corrupt the sequencer's bring-up
//                 writes).
//   T2 BUSY:      STATUS bit0=1 while the FSM is in S_LOAD (mid-stream, a
//                 deterministic busy window before the first window_ready).
//   T3 OVERFLOW:  STATUS bit3=1 when the top-level overflow net is driven —
//                 the source is `force`d on the demo top's sys_overflow net, so
//                 T3 PROVES ONLY THE CONNECTION / READBACK PATH, NOT THAT THE
//                 adc/feature/mlp overflow SOURCE ACTUALLY ASSERTS (those
//                 sources are exercised by tb_adc_interface overflow tests
//                 and by the demo packet flags in tb_demo_rom).
//   T5/T6/T7 OR WIRING: each overflow source is driven on its OWN net while
//                 the other two are held at 0; STATUS bit3 must follow the
//                 driven source. This is what T3 alone does NOT prove — it
//                 proves the OR in the top is wired to the right nets.
//                 CONNECTION PROOF ONLY (sources are forced, not real data).
//   T4 UNDISTURBED: the STATUS hijacks above did not break the demo stream:
//                 7 window_ready, adc sample_count == ROM_WORDS, no pkt_drop,
//                 end_of_data, demo_done, demo_overflow == 0.
//   T8 DROP SEPARATION: pkt_drop must NOT set STATUS bit3 (a dropped packet
//                 is a transport loss, not a numeric overflow). The force is
//                 proven effective by checking demo_overflow == 1 while it
//                 is held, so "bit3 == 0" cannot pass vacuously.
//
// The APB bus has a single in-RTL driver (demo_apb_seq); to inject a STATUS
// read we `force` the top-level APB protocol nets (paddr/psel/penable/pwrite)
// for ~2 cycles. The forces land in quiescent windows (sequencer idle,
// psel=0), so no sequencer write is lost.
// =============================================================================

module tb_demo_status;
    parameter int CLK_HZ   = 50_000_000;
    parameter int TARGET_HZ = 33_333;       // fast pacing (same as tb_demo_rom)
    parameter int ROM_WORDS = 2048;
    parameter ROM_HEX = "../demo/ecg_rom.hex";

    localparam PERIOD_NS = 20.0;            // 50 MHz

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

    always #(PERIOD_NS/2) clk = ~clk;

    integer win_ready_cnt;
    integer total, passed;

    always @(posedge clk)
        win_ready_cnt <= win_ready_cnt + (dut.window_ready ? 1 : 0);

    // APB READ STATUS (addr 0x04) over the internal bus via brief forces.
    // SETUP (psel=1, penable=0, pwrite=0, paddr=0x04) -> ACCESS
    // (penable=1): the slave samples prdata at the ACCESS posedge; value is
    // stable afterwards. ~2 cycles total.
    task apb_read_status(output integer st);
        begin
            force dut.apb_paddr   = 32'h0000_0004;
            force dut.apb_psel    = 1'b1;
            force dut.apb_penable = 1'b0;
            force dut.apb_pwrite  = 1'b0;
            @(posedge clk); #1;
            force dut.apb_penable = 1'b1;
            @(posedge clk); #1;
            force dut.apb_penable = 1'b0;
            force dut.apb_psel    = 1'b0;
            st = dut.u_apb.prdata;
            release dut.apb_paddr;
            release dut.apb_psel;
            release dut.apb_penable;
            release dut.apb_pwrite;
        end
    endtask

    // APB WRITE a 32-bit value (SETUP -> ACCESS, same timing as the read).
    task apb_write(input integer addr, input integer data);
        begin
            force dut.apb_paddr   = addr;
            force dut.apb_pwdata  = data;
            force dut.apb_psel    = 1'b1;
            force dut.apb_penable = 1'b0;
            force dut.apb_pwrite  = 1'b1;
            @(posedge clk); #1;
            force dut.apb_penable = 1'b1;
            @(posedge clk); #1;
            force dut.apb_penable = 1'b0;
            force dut.apb_psel    = 1'b0;
            force dut.apb_pwrite  = 1'b0;
            release dut.apb_paddr;
            release dut.apb_psel;
            release dut.apb_penable;
            release dut.apb_pwrite;
            release dut.apb_pwdata;
        end
    endtask

    task advance;
        input integer n;
        begin
            repeat (n) @(posedge clk);
        end
    endtask

    // -------------------------------------------------------------------
    // Per-source overflow probe (T5/T6/T7).
    //
    // Each source is driven HIGH on its OWN net while the OTHER two are
    // forced LOW, so STATUS bit3 must follow EXACTLY the driven source.
    // This is what proves the OR in the demo top is wired to the right
    // nets (a mis-wired OR — e.g. adc_overflow tied to the wrong signal —
    // shows up as bit3 staying 0 when the driven source is high).
    //
    // SCOPE NOTE: the three nets are FORCED here, so these tests prove the
    // OR/net connection and the APB readback path. They do NOT prove that
    // the adc/feature/mlp overflow logic itself asserts on real data
    // (that is covered by tb_adc_interface and by the packet flags).
    // -------------------------------------------------------------------
    task probe_one_source(
        input [31:0] sel,            // bit0=adc, bit1=feature, bit2=mlp
        output [31:0] st_out,
        output        followed);      // 1 = STATUS bit3 followed the source
        integer s;
        begin
            force dut.adc_overflow     = sel[0];
            force dut.feature_overflow = sel[1];
            force dut.mlp_overflow     = sel[2];
            apb_read_status(s);
            st_out = s;
            // expected: bit3 == OR of the three forced source bits
            followed = (s[3] === (sel[0] | sel[1] | sel[2]));
            release dut.adc_overflow;
            release dut.feature_overflow;
            release dut.mlp_overflow;
        end
    endtask

    integer st;
    integer st_forced, st_released;
    integer wait_c;
    integer followed;
    reg drop_on_demo_ovf;

    initial begin
        total = 0; passed = 0;
        win_ready_cnt = 0;

        $display("========================================");
        $display("Demo STATUS TB  TARGET_HZ=%0d (fast)", TARGET_HZ);
        $display("========================================");

        rst_n = 1'b0;
        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        advance(200);

        // -----------------------------------------------------------------
        // T2 BUSY: ~500 cycles in, FSM is in S_LOAD (first window not ready
        // until ~512 samples * ~1500 cycles), and the sequencer is quiescent.
        // -----------------------------------------------------------------
        total = total + 1;
        apb_read_status(st);
        if (st[0] === 1'b1 && st[1] === 1'b0 && st[3] === 1'b0 &&
            dut.u_ctrl_fsm.current_state != 4'd0) begin
            passed = passed + 1;
            $display("PASS T2 busy: STATUS=0x%08x, fsm_state=%0d", st,
                     dut.u_ctrl_fsm.current_state);
        end else begin
            $display("FAIL T2 busy: STATUS=0x%08x fsm_state=%0d", st,
                     dut.u_ctrl_fsm.current_state);
        end

        // -----------------------------------------------------------------
        // T3 OVERFLOW READBACK: force the top-level overflow net, read STATUS,
        // release, read again. CONNECTION-ONLY PROOF (see header).
        // -----------------------------------------------------------------
        total = total + 1;
        force dut.sys_overflow = 1'b1;
        apb_read_status(st);
        st_forced = st;   // latched below via a separate reg to keep 10.7c simple
        release dut.sys_overflow;
        apb_read_status(st);
        st_released = st;
        if (st_forced[3] === 1'b1 && st_released[3] === 1'b0) begin
            passed = passed + 1;
            $display("PASS T3 overflow readback: forced=0x%08x released=0x%08x",
                     st_forced, st_released);
        end else begin
            $display("FAIL T3 overflow readback: forced=0x%08x released=0x%08x",
                     st_forced, st_released);
        end
        // NOTE: T3 proves the STATUS overflow bit follows the (forced) source
        // net. It does NOT prove the adc/feature/mlp overflow flags themselves.

        // -----------------------------------------------------------------
        // T5-T7 PER-SOURCE OR WIRING: drive each overflow source on its own
        // net (others forced 0) and confirm STATUS bit3 follows it.
        // This is what a top-level `sys_overflow` force (T3) does NOT
        // prove on its own — it proves the OR is wired to the right net.
        // CONNECTION PROOF ONLY (sources are forced, not real data).
        // -----------------------------------------------------------------
        total = total + 1;
        probe_one_source(32'b001, st_forced, followed);        // adc only
        if (followed && st_forced[3] === 1'b1) begin
            passed = passed + 1;
            $display("PASS T5 adc source -> STATUS bit3=1 (STATUS=0x%08x)", st_forced);
        end else begin
            $display("FAIL T5 adc source: followed=%b STATUS=0x%08x", followed, st_forced);
        end

        total = total + 1;
        probe_one_source(32'b010, st_forced, followed);        // feature only
        if (followed && st_forced[3] === 1'b1) begin
            passed = passed + 1;
            $display("PASS T6 feature source -> STATUS bit3=1 (STATUS=0x%08x)", st_forced);
        end else begin
            $display("FAIL T6 feature source: followed=%b STATUS=0x%08x", followed, st_forced);
        end

        total = total + 1;
        probe_one_source(32'b100, st_forced, followed);        // mlp only
        if (followed && st_forced[3] === 1'b1) begin
            passed = passed + 1;
            $display("PASS T7 mlp source -> STATUS bit3=1 (STATUS=0x%08x)", st_forced);
        end else begin
            $display("FAIL T7 mlp source: followed=%b STATUS=0x%08x", followed, st_forced);
        end

        // -----------------------------------------------------------------
        // Run to end-of-data, then drain all queued packets (back-to-back
        // serialization of 7 x 33 bytes x 10 bits x 437 + margin).
        // -----------------------------------------------------------------
        wait_c = 0;
        while (!dut.u_pacer.end_of_data && wait_c < 2 * ROM_WORDS *
               (CLK_HZ / TARGET_HZ + 2)) begin
            @(posedge clk);
            wait_c = wait_c + 1;
        end
        if (!dut.u_pacer.end_of_data)
            $display("FAIL: end_of_data not set in %0d cycles", wait_c);
        advance(8 * 33 * 10 * 437 + 20000);

        // -----------------------------------------------------------------
        // T1 IDLE: after the stream drained the FSM is parked in S_LOAD (the
        // demo sequencer re-issues CTRL=enable|start after every result, and
        // the ROM is exhausted -> no further window_ready ever arrives, so the
        // FSM legitimately waits in S_LOAD). To observe a true IDLE we issue
        // a real APB soft-reset (CTRL bit4), which returns the FSM to S_IDLE
        // and clears sys_enable -> the FSM stays idle.
        // -----------------------------------------------------------------
        total = total + 1;
        apb_write(32'h00, 32'h0000_0010);   // CTRL bit4 = soft_reset
        advance(8);
        apb_read_status(st);
        if (st === 32'h0000_0000 && dut.u_ctrl_fsm.current_state === 4'd0) begin
            passed = passed + 1;
            $display("PASS T1 idle: STATUS=0x%08x fsm_state=%0d", st,
                     dut.u_ctrl_fsm.current_state);
        end else begin
            $display("FAIL T1 idle: STATUS=0x%08x fsm_state=%0d", st,
                     dut.u_ctrl_fsm.current_state);
        end

        // T4 UNDISTURBED stream — evaluated BEFORE the soft-reset above would
        // matter, but the soft reset only clears the FSM state (no data
        // change), so the stream counters are still valid here.
        total = total + 1;
        if (win_ready_cnt == 7 && dut.u_adc_if.sample_count == ROM_WORDS &&
            dut.u_pacer.end_of_data === 1'b1 && dut.u_pz.pkt_drop === 1'b0 &&
            demo_overflow === 1'b0 && demo_done === 1'b1) begin
            passed = passed + 1;
            $display("PASS T4 undisturbed: winR=%0d adc=%0d eod=1 drop=0 demo_overflow=0 demo_done=1",
                     win_ready_cnt, dut.u_adc_if.sample_count);
        end else begin
            $display("FAIL T4 undisturbed: winR=%0d adc=%0d eod=%b drop=%b demo_overflow=%b demo_done=%b",
                     win_ready_cnt, dut.u_adc_if.sample_count,
                     dut.u_pacer.end_of_data, dut.u_pz.pkt_drop,
                     demo_overflow, demo_done);
        end

        // -----------------------------------------------------------------
        // T8 PACKET-DROP MEANING SEPARATION: pkt_drop must NOT appear in the
        // APB STATUS overflow bit (bit3). A dropped packet is a transport loss,
        // not a numeric overflow. Force pkt_drop high and read STATUS: bit3
        // must stay 0 (no overflow source forced), while the packetizer's own
        // pkt_drop flag proves the drop latch is reachable.
        // -----------------------------------------------------------------
        total = total + 1;
        force dut.u_pz.pkt_drop = 1'b1;
        #1 drop_on_demo_ovf = demo_overflow;
        apb_read_status(st_forced);
        release dut.u_pz.pkt_drop;
        // drop_on_demo_ovf must be 1: it proves the force actually took effect
        // (otherwise "bit3 == 0" would be vacuous).
        if (st_forced[3] === 1'b0 && drop_on_demo_ovf === 1'b1) begin
            passed = passed + 1;
            $display("PASS T8 pkt_drop does NOT set STATUS bit3 (STATUS=0x%08x, demo_overflow=1 during force)", st_forced);
        end else begin
            $display("FAIL T8: STATUS=0x%08x demo_overflow_during_force=%b", st_forced, drop_on_demo_ovf);
        end


        $display("========================================");
        $display("Test Summary: %0d/%0d %s", passed, total,
                 (passed == total) ? "PASSED" : "FAILED");
        $display("========================================");
        #100;
        $finish;
    end

endmodule
