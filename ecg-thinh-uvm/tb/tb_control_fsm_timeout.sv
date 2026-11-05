`timescale 1ns / 1ps
// =============================================================================
// Focused test of the control_fsm S_LOAD timeout *escape*.
//
// Spec intent (control_fsm.v header + S_LOAD comment): if a full window
// arrives but feature_valid never does, S_LOAD must fall back to S_IDLE via
// the `timeout_cnt == 0` guard -- it must NOT hang or emit a fake success.
// The shipped default LOAD_TIMEOUT is 100e6 cycles (~2 s); to prove the
// behavior in seconds, this TB overrides the module parameter to a small
// value. It verifies TWO things:
//   T1  HANG: S_LOAD with no window_ready/feat_valid -> returns to S_IDLE
//       after ~LOAD_TIMEOUT cycles (the guard IS live, not dead code).
//   T2  NORMAL: S_LOAD where window_ready then feat_valid arrive early ->
//       reaches S_NORM, i.e. the timeout does NOT fire prematurely.
// Neither test ever pulses a spurious "success": on the hang path no
// feat_valid/done is asserted, only the return to S_IDLE is checked.
// =============================================================================
module tb_control_fsm_timeout;

    localparam [27:0] TMO = 28'd120;   // short LOAD_TIMEOUT for the sim

    reg clk;
    reg rst_n;
    reg start;
    reg feat_valid;
    reg apb_enable;
    reg window_ready;
    reg mlp_done;
    reg soft_reset;

    wire fsm_idle;
    wire window_en;
    wire done;
    wire [3:0] current_state;
    wire feature_start;

    localparam S_IDLE = 4'd0;
    localparam S_LOAD = 4'd1;
    localparam S_NORM = 4'd2;

    control_fsm #(.LOAD_TIMEOUT(TMO)) dut (
        .clk(clk), .rst_n(rst_n),
        .start(start), .feat_valid(feat_valid), .apb_enable(apb_enable),
        .window_ready(window_ready), .mlp_done(mlp_done),
        .soft_reset(soft_reset),
        .fsm_idle(fsm_idle), .window_en(window_en),
        .feature_start(feature_start),
        .done(done), .current_state(current_state),
        .feature_read_en(), .mlp_start(), .mlp_valid(), .uart_send(),
        .read_addr(), .next_state_debug()
    );

    initial begin
        clk = 0;
        forever #9.92 clk = ~clk;  // 19.84 ns period = 50.4 MHz
    end

    reg [31:0] cycles_in_load;
    integer ok;
    initial begin
        ok = 0; cycles_in_load = 0;
        rst_n = 0; start = 0; feat_valid = 0; apb_enable = 0;
        window_ready = 0; mlp_done = 0; soft_reset = 0;
        repeat (4) @(posedge clk);
        rst_n = 1;
        repeat (4) @(posedge clk);

        // =================================================================
        // T1: enter S_LOAD, then hold (no window_ready, no feat_valid) and
        //     count cycles spent in S_LOAD before it escapes to S_IDLE.
        //     NOTE: current_state lags state by 1 cycle -> wait until the
        //     S_LOAD entry is visible before counting, and the escape count
        //     includes that 1-cycle lag (~TMO+2, within the TMO-2..TMO+4 band).
        // =================================================================
        start = 1; apb_enable = 1;
        @(posedge clk);                      // commit S_IDLE -> S_LOAD (E0)
        start = 0;                            // single start pulse only
        apb_enable = 1;                       // keep enabled so we STAY in LOAD
        while (current_state !== S_LOAD) @(posedge clk);   // S_LOAD visible
        cycles_in_load = 0;
        // wait for the FSM to leave S_LOAD (escape to S_IDLE on timeout)
        while (current_state === S_LOAD) begin
            @(posedge clk);
            cycles_in_load = cycles_in_load + 1;
        end
        // Escape must be to IDLE, not NORM/DONE (no spurious success).
        if (current_state === S_IDLE)
            begin $display("T1 PASS: S_LOAD hang escaped to S_IDLE"); ok = ok + 1; end
        else
            $display("T1 FAIL: after S_LOAD hold, state=%0d (expected S_IDLE)",
                     current_state);
        // Escape timing ~ TMO cycles (not dramatically early).
        if (cycles_in_load >= TMO-2 && cycles_in_load <= TMO+4)
            begin $display("T1 PASS: cycles_in_load=%0d ~= LOAD_TIMEOUT=%0d",
                           cycles_in_load, TMO); ok = ok + 1; end
        else
            $display("T1 FAIL: cycles_in_load=%0d not ~= LOAD_TIMEOUT=%0d",
                     cycles_in_load, TMO);
        // No fake success on the hang path: check BEFORE T2 (which will
        // re-assert done via its own flow). done must still be low here.
        if (done === 1'b0)
            begin $display("T1 PASS: no spurious done on hang path"); ok = ok + 1; end
        else
            $display("T1 FAIL: done asserted on hang path");

        repeat (4) @(posedge clk);

        // =================================================================
        // T2: enter S_LOAD, feed window_ready then feat_valid EARLY (well
        //     before TMO) -> must reach S_NORM (timeout must not fire).
        // =================================================================
        start = 1; apb_enable = 1;
        @(posedge clk);                       // S_IDLE -> S_LOAD
        start = 0;
        repeat (8) @(posedge clk);            // 8 cycles into LOAD
        window_ready = 1;
        @(posedge clk);                        // feature_start pulses, reload
        window_ready = 0;
        repeat (3) @(posedge clk);
        feat_valid = 1;
        @(posedge clk);                        // state -> S_NORM (branch 2)
        feat_valid = 0;
        repeat (2) @(posedge clk);             // current_state lags state by 1 -> S_NORM
        if (current_state === S_NORM)
            begin $display("T2 PASS: early window_ready+feat_valid -> S_NORM (no early timeout)"); ok = ok + 1; end
        else
            $display("T2 FAIL: expected S_NORM, got state=%0d", current_state);
        repeat (4) @(posedge clk);

        if (ok == 4) $display("Test Summary: 4/4 PASSED");
        else         $display("Test Summary: %0d/4 FAILED", ok);
        #100;
        $finish;
    end
endmodule
