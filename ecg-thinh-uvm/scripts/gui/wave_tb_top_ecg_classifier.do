# =============================================================================
# Waveform config: tb_top_ecg_classifier (Questa 10.7c GUI)
# Run through scripts/gui/run_gui.bat tb_top_ecg_classifier.
#
# (self-reporting) every wave/radix/zoom command is wrapped in `catch`;
# failures print a visible "[wave] FAIL ..." line to the Transcript instead of
# being silently swallowed (the old `onerror {resume}` hid per-signal errors).
# A final summary line prints how many commands failed, so a broken path is
# obvious in the transcript.
#
# Path names verified against the elaborated hierarchy (top_ecg_classifier.v +
# control_fsm.v): DUT instance is `dut`, control FSM instance is
# `dut.u_ctrl_fsm`, and the FSM exposes register `current_state` (port) as well
# as internal `state`/`next_state`. The DUT-level wires used here are all
# module-level signals declared in top_ecg_classifier.v.
# =============================================================================

set ::wv_fail [expr 0]
set ::wv_ok   [expr 0]

# Run one wave sub-command; on error print the offending command + message.
proc wv_run { cmd } {
    global ::wv_fail ::wv_ok
    set r [catch $cmd]
    if { $r != 0 } {
        set ::wv_fail [expr $::wv_fail + 1]
        # NOTE: the square brackets in the label are escaped so Tcl does not
        # treat "[wave]" as a command substitution.
        puts "\[wave\] FAIL: $cmd -> $r"
    } else {
        set ::wv_ok [expr $::wv_ok + 1]
    }
}

# Convenience helpers to keep the list below readable.
set T /tb_top_ecg_classifier

# --- Clock / Reset / ADC (binary) ------------------------------------------
wv_run { radix binary }
wv_run [list wave add $T/sys_clk]
wv_run [list wave add $T/sys_rst_n]
wv_run [list wave add $T/adc_valid]
wv_run [list wave add $T/adc_data]
wv_run "wave group \"CLK / RESET / ADC\" {$T/sys_clk $T/sys_rst_n $T/adc_valid $T/adc_data}"

# --- Handshake between blocks (binary) --------------------------------------
wv_run { radix binary }
wv_run [list wave add $T/dut/adc_sample_valid]
wv_run [list wave add $T/dut/window_ready]
wv_run [list wave add $T/dut/feature_start]
wv_run [list wave add $T/dut/feature_valid]
wv_run [list wave add $T/dut/mlp_start]
wv_run [list wave add $T/dut/mlp_done]
wv_run [list wave add $T/dut/uart_send]
wv_run "wave group \"HANDSHAKE\" {$T/dut/adc_sample_valid $T/dut/window_ready $T/dut/feature_start $T/dut/feature_valid $T/dut/mlp_start $T/dut/mlp_done $T/dut/uart_send}"

# --- FSM + counter (decimal) ------------------------------------------------
wv_run { radix decimal }
wv_run [list wave add $T/dut/u_ctrl_fsm/current_state]
wv_run [list wave add $T/dut/u_ctrl_fsm/timeout_cnt]
wv_run "wave group \"FSM (control)\" {$T/dut/u_ctrl_fsm/current_state $T/dut/u_ctrl_fsm/timeout_cnt}"

# --- Result + interrupt + UART (binary) --------------------------------------
wv_run { radix binary }
wv_run [list wave add $T/dut/sys_class_code]
wv_run [list wave add $T/dut/sys_done]
wv_run [list wave add $T/irq]
wv_run [list wave add $T/uart_txd]
wv_run [list wave add $T/byte_val]
wv_run [list wave add $T/rx_ok]
wv_run "wave group \"RESULT / IRQ / UART\" {$T/dut/sys_class_code $T/dut/sys_done $T/irq $T/uart_txd $T/byte_val $T/rx_ok}"

# --- Status LEDs (binary) ---------------------------------------------------
wv_run [list wave add $T/status_led]
wv_run "wave group \"STATUS LED\" {$T/status_led}"

# --- Zoom: applied by run_gui.bat AFTER `run -all` (a pre-run zoom gets
#     overridden). Calibrated range for div=20 TB override:
#   window_ready = 204104 ns ; feature_valid = 214381 ns
#   mlp_done = 218111 ns ; sys_done/uart_send = 218250 ns ; sim ends 306252 ns.
#   -> 195000ns .. 310000ns (195us..310us) shows window->feature->MLP->UART.
# (event times measured in-tb with a temporary $time probe on 2026-10-30,
#  run tb_top_ecg_classifier in work_reg, probe removed afterwards.)

puts "\[wave\] summary: $::wv_ok ok, $::wv_fail failed (see lines above)."
