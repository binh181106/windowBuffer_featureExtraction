# =============================================================================
# Waveform config: tb_control_fsm (Questa 10.7c GUI)
# (self-reporting) every wave/radix command wrapped in `catch`; failures print
# a visible "[wave] FAIL ..." line. Old `onerror {resume}` hid per-signal
# errors, so a broken path was invisible in the transcript.
# Paths verified against tb_control_fsm.sv + control_fsm.v:
#   DUT instance = `dut` (control_fsm), registers state/next_state/
#   feat_started/cnt/timeout_cnt, ports as listed below.
# =============================================================================

set ::wv_fail [expr 0]
set ::wv_ok   [expr 0]

proc wv_run { cmd } {
    global ::wv_fail ::wv_ok
    set r [catch $cmd]
    if { $r != 0 } {
        set ::wv_fail [expr $::wv_fail + 1]
        # NOTE: square brackets in the label are escaped so Tcl does not
        # treat "[wave]" as a command substitution.
        puts "\[wave\] FAIL: $cmd -> $r"
    } else {
        set ::wv_ok [expr $::wv_ok + 1]
    }
}

set T /tb_control_fsm

# --- Clock / Reset (binary) -------------------------------------------------
wv_run { radix binary }
wv_run [list wave add $T/clk]
wv_run [list wave add $T/rst_n]
wv_run "wave group \"CLK / RESET\" {$T/clk $T/rst_n}"

# --- Handshake inputs (binary) ----------------------------------------------
wv_run [list wave add $T/start]
wv_run [list wave add $T/apb_enable]
wv_run [list wave add $T/window_ready]
wv_run [list wave add $T/feat_valid]
wv_run [list wave add $T/mlp_done]
wv_run [list wave add $T/soft_reset]
wv_run "wave group \"HANDSHAKE IN\" {$T/start $T/apb_enable $T/window_ready $T/feat_valid $T/mlp_done $T/soft_reset}"

# --- FSM state (v3.1 oscillation check) (binary) -----------------------------
wv_run [list wave add $T/dut/state]
wv_run [list wave add $T/dut/next_state]
wv_run [list wave add $T/dut/current_state]
wv_run [list wave add $T/dut/feat_started]
wv_run "wave group \"FSM STATE (v3.1)\" {$T/dut/state $T/dut/next_state $T/dut/current_state $T/dut/feat_started}"

# --- Counters (decimal) -------------------------------------------------------
wv_run { radix decimal }
wv_run [list wave add $T/dut/cnt]
wv_run [list wave add $T/dut/timeout_cnt]
wv_run "wave group \"COUNTERS\" {$T/dut/cnt $T/dut/timeout_cnt}"

# --- Control outputs (binary) -------------------------------------------------
wv_run { radix binary }
wv_run [list wave add $T/dut/fsm_idle]
wv_run [list wave add $T/dut/window_en]
wv_run [list wave add $T/dut/feature_start]
wv_run [list wave add $T/dut/mlp_start]
wv_run [list wave add $T/dut/mlp_valid]
wv_run [list wave add $T/dut/uart_send]
wv_run [list wave add $T/dut/done]
wv_run "wave group \"CTRL OUT\" {$T/dut/fsm_idle $T/dut/window_en $T/dut/feature_start $T/dut/mlp_start $T/dut/mlp_valid $T/dut/uart_send $T/dut/done}"

# --- TB checker (binary) ------------------------------------------------------
wv_run [list wave add $T/fs_seen]
wv_run "wave group \"CHECKER\" {$T/fs_seen}"

puts "\[wave\] summary: $::wv_ok ok, $::wv_fail failed (see lines above)."
