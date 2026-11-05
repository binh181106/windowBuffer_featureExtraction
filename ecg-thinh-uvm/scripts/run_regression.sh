#!/usr/bin/env bash
# =============================================================================
# ECG Classifier — Regression Runner (QuestaSim 10.7c batch)
#
# Reuse the SAME source list for batch and GUI: scripts/rtl.f
# Fresh library every run (no stale compile hiding errors). Per-test timeout.
# Separate logs + a summary table + an exit code that reflects the real result.
#
# Result categories per test:
#   PASS / FAIL(checker) / COMPILE_FAIL / ELAB_FAIL / TIMEOUT / BLOCKED
#
# Questa 10.7c specifics (confirmed 2026-10-30):
#   - vlog/vsim do NOT accept -mfcu (that flag is from Questa 25.x docs).
#   - vlog does NOT accept -c99. Use -sv for SystemVerilog.
#   - Libraries: vlib creates "work_reg" / "work_uvm" inside $SIMLIB, and we
#     invoke vlog/vsim FROM $SIMLIB so "-work work_reg" resolves there
#     (same pattern as the legacy tb/Makefile).
#
# Usage:  bash run_regression.sh
# Env:    QUESTA_ROOT (default H:/questasim64_10.7c), TIMEOUT (default 120s)
# =============================================================================
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
TB_DIR="$REPO/tb"
SIMLIB="$REPO/simlib"
SIMROOT="${QUESTA_ROOT:-H:/questasim64_10.7c}"
VLOG="$SIMROOT/win64/vlog.exe"
VSIM="$SIMROOT/win64/vsim.exe"
VLIB="$SIMROOT/win64/vlib.exe"
UVM_SRC="$SIMROOT/verilog_src/uvm-1.2/src"

LOG_DIR="$REPO/logs"
mkdir -p "$LOG_DIR" "$SIMLIB"

RTL_F="$SCRIPT_DIR/rtl.f"
TIMEOUT="${TIMEOUT:-120}"   # seconds per simulation

# ---------------------------------------------------------------------------
# Tool sanity (path error vs code error: stop early with a clear message).
# ---------------------------------------------------------------------------
for t in "$VLOG" "$VSIM" "$VLIB"; do
  if [ ! -e "$t" ]; then
    echo "FATAL: Questa tool not found: $t"
    echo "Set QUESTA_ROOT to the correct install dir and retry."
    exit 100
  fi
done
echo "Questa : $SIMROOT"
echo "vlog   : "$("$VLOG" -version 2>/dev/null | head -1)
echo "vsim   : "$("$VSIM" -version 2>/dev/null | head -1)
echo

# rtl.f lists repo-root-relative paths -> absolute paths.
mapfile -t RTL_SRCS < <(sed 's#^\s*##; s#\s*$##' "$RTL_F" | grep -v '^$' | sed "s#^#$REPO/#")

# ---------------------------------------------------------------------------
# 1) Fresh library + compile all RTL once (batch and GUI share this lib).
# ---------------------------------------------------------------------------
rm -rf "$SIMLIB/work_reg" "$SIMLIB/work_uvm"
"$VLIB" "$SIMLIB/work_reg"  > "$LOG_DIR/vlib.log" 2>&1
"$VLIB" "$SIMLIB/work_uvm" >> "$LOG_DIR/vlib.log" 2>&1

cd "$SIMLIB"
echo "== vlog: RTL (9 modules) -> work_reg"
"$VLOG" -sv -work work_reg "${RTL_SRCS[@]}" > "$LOG_DIR/rtl_compile.log" 2>&1
if ! grep -q "^Errors: 0, Warnings: 0" "$LOG_DIR/rtl_compile.log"; then
  echo "    !! RTL compile reported issues:"
  grep -E "Error|Warning" "$LOG_DIR/rtl_compile.log" | head -5
fi
grep -E "^Errors" "$LOG_DIR/rtl_compile.log" | tail -1
echo

# ---------------------------------------------------------------------------
# run_one <name> <mode:expect|smoke> <tb_top> <tb_rel_to_TB_DIR>...
#   expect : pass iff "Test Summary: P/T PASSED" with P==T, T>0, no FAIL line
#   smoke  : pass iff no ** Error / ** Fatal / UVM_FATAL and clean exit
# ---------------------------------------------------------------------------
declare -a RESULT SUMMARIES
total=0; passed=0

run_one() {
  local name="$1"; local mode="$2"; local top="$3"; shift 3
  local log="$LOG_DIR/${name}.log"
  total=$((total+1))

  # Split remaining args: source files (.sv/.v) -> vlog, others -> markers.
  local -a srcs=() marks=()
  local a
  for a in "$@"; do
    case "$a" in *.sv|*.v) srcs+=("$a") ;; *) marks+=("$a") ;; esac
  done

  # Compile this TB into the shared lib (cwd = SIMLIB so -work resolves).
  "$VLOG" -sv -work work_reg "${srcs[@]}" > "$log" 2>&1
  if ! grep -q "^Errors: 0, Warnings: 0" "$log"; then
    RESULT+=("$name|COMPILE_FAIL"); _report; return
  fi

  # Simulate with a hard wall-clock timeout (coreutils `timeout` present here).
  timeout "$TIMEOUT" "$VSIM" -c -work work_reg "$top" -do "run -all; quit -f" \
      > "${log%.log}_sim.log" 2>&1
  local rc=$?
  cat "${log%.log}_sim.log" >> "$log"
  if [ $rc -eq 124 ]; then RESULT+=("$name|TIMEOUT"); _report; return; fi

  local verdict=""
  case "$mode" in
    expect)
      if grep -qE '\*\* (Error|Fatal)' "$log"; then
        verdict="ELAB_FAIL"
      else
        local pt p t
        pt="$(tr -s ' ' < "$log" | grep -oE 'Test Summary: .*PASSED' | tail -1)"
        p="$(printf '%s' "$pt" | grep -oE '[0-9]+' | sed -n '1p')"
        t="$(printf '%s' "$pt" | grep -oE '[0-9]+' | sed -n '2p')"
        if [ -n "$p" ] && [ "$p" -eq "$t" ] && [ "$t" -gt 0 ] \
           && ! grep -qE 'FAIL' "$log"; then
          verdict="PASS (${p}/${t})"
        else
          verdict="FAIL(summary='${pt:-no summary}' fail_lines=$(grep -cE 'FAIL' "$log"))"
        fi
      fi
      ;;
    markers)
      # Pass iff every marker string is present AND no FAIL / hard error.
      local miss=0 m
      for m in "${marks[@]}"; do
        [ -z "$m" ] && continue
        if ! grep -qF "$m" "$log"; then miss=1; fi
      done
      if grep -qE '\*\* (Error|Fatal)' "$log"; then
        verdict="ELAB_FAIL"
      elif [ $miss -eq 1 ] || grep -qE 'FAIL' "$log"; then
        verdict="FAIL(marker missing / FAIL present)"
      else
        verdict="PASS(markers)"
      fi
      ;;
    smoke)
      if grep -qE '\*\* (Error|Fatal)|UVM_FATAL' "$log" || [ $rc -ne 0 ]; then
        verdict="FAIL"
      else
        verdict="PASS(smoke)"
      fi
      ;;
  esac
  RESULT+=("$name|$verdict"); _report
}

_report() {
  local line="${RESULT[-1]}"
  local name="${line%%|*}"; local res="${line#*|}"
  case "$res" in PASS*) passed=$((passed+1)) ;; esac
  printf '  [%-24s] %s\n' "$res" "$name"
  SUMMARIES+=("| $name | $res | $LOG_DIR/$name.log |")
}

echo "== Unit testbenches =="
run_one adc     expect tb_adc_interface    "$TB_DIR/tb_adc_interface.sv"
run_one window  expect tb_window_buffer    "$TB_DIR/tb_window_buffer.sv"
run_one feature expect tb_feature_extraction "$TB_DIR/tb_feature_extraction.sv"
run_one ai      expect tb_ai_classifier    "$TB_DIR/tb_ai_classifier.sv"
run_one ai_math expect tb_ai_classifier_math "$TB_DIR/tb_ai_classifier_math.sv"
run_one apb     expect tb_apb_slave_if     "$TB_DIR/tb_apb_slave_if.sv"
run_one uart    expect tb_uart_tx          "$TB_DIR/tb_uart_tx.sv"
run_one control markers tb_control_fsm \
    "$TB_DIR/tb_control_fsm.sv" \
    "Reached LOAD state" \
    "feature_start pulsed on window_ready" \
    "Reached NORMALIZE state"
run_one control_tmo expect tb_control_fsm_timeout "$TB_DIR/tb_control_fsm_timeout.sv"
run_one rr_probe expect tb_rr_probe "$TB_DIR/tb_rr_probe.sv"
run_one smoke_f smoke  tb_feature_simple   "$TB_DIR/tb_feature_simple.sv"
run_one smoke_w smoke  tb_window_simple    "$TB_DIR/tb_window_simple.sv"
echo

echo "== Top-level E2E =="
run_one top expect tb_top_ecg_classifier "$TB_DIR/tb_top_ecg_classifier.sv"
echo

# ---------------------------------------------------------------------------
# 2) UVM APB environment (own library; uvm_pkg + interface + define APB_RTL_V30).
# ---------------------------------------------------------------------------
echo "== UVM APB env =="
UVM_LOG="$LOG_DIR/uvm.log"
rm -f "$UVM_LOG"; : > "$UVM_LOG"
if [ -d "$UVM_SRC" ]; then
  "$VLOG" -sv -work work_uvm \
      +incdir+"$UVM_SRC" "$UVM_SRC/uvm_pkg.sv" \
      "$REPO/apb/apb_slave_if.v" \
      "$REPO/tb/uvm/apb_slave_if_if.sv" \
      "$REPO/tb/uvm/apb_slave_if_env_pkg.sv" \
      "$REPO/tb/uvm/tb_apb_uvm.sv" \
      +define+APB_RTL_V30 >> "$UVM_LOG" 2>&1
  if ! grep -q "^Errors: 0, Warnings: 0" "$UVM_LOG"; then
    RESULT+=("uvm|COMPILE_FAIL"); _report
  else
    total=$((total+1))
    timeout "$TIMEOUT" "$VSIM" -c -work work_uvm tb.tb_apb_uvm \
        -do "run -all; quit -f" >> "$UVM_LOG" 2>&1
    rc=$?
    if [ $rc -eq 124 ]; then
      RESULT+=("uvm|TIMEOUT"); _report
    elif grep -qE 'UVM_FATAL' "$UVM_LOG"; then
      RESULT+=("uvm|ELAB_FAIL"); _report
    elif grep -qE 'UVM_ERROR *[:=]* *[1-9]' "$UVM_LOG"; then
      RESULT+=("uvm|FAIL(uvm_error>0)"); _report
    else
      RESULT+=("uvm|PASS(smoke env)"); _report
    fi
  fi
else
  RESULT+=("uvm|BLOCKED(no uvm_pkg under $SIMROOT)"); _report
fi
echo

# ---------------------------------------------------------------------------
# 3) Demo ROM testbench (ROM -> pacer -> pipeline -> UART; independent golden)
#    Own library work_demo, longer timeout (fast-paced run ~2-4 min), own log.
#    Pass iff "Demo ROM TB  Test Summary: P/T PASSED" with P==T.
#    Requires demo/ecg_rom.hex to exist; regen via demo/ecg_convert.py if missing.
# ---------------------------------------------------------------------------
echo "== Demo ROM (ROM -> pipeline -> UART, vs golden) =="
# Python-side checks first (converter unit tests + offline decoder self-test).
PY_LOG="$LOG_DIR/demo_python.log"
rm -f "$PY_LOG"; : > "$PY_LOG"
total=$((total+1))
if ( cd "$REPO" && python -I demo/test_ecg_convert.py ) >> "$PY_LOG" 2>&1 \
   && ( cd "$REPO" && python -I demo/uart_decode.py ) >> "$PY_LOG" 2>&1; then
  RESULT+=("demo_python|PASS"); _report
else
  RESULT+=("demo_python|FAIL"); _report
fi

DEMO_LOG="$LOG_DIR/demo_rom.log"
rm -f "$DEMO_LOG"; : > "$DEMO_LOG"
if [ ! -e "$REPO/demo/ecg_rom.hex" ]; then
  echo "  regenerating demo/ecg_rom.hex ..."
  ( cd "$REPO" && python -I demo/ecg_convert.py --start 1000 --n 2048 \
      --channel 0 --out demo/ecg_rom.hex >> "$DEMO_LOG" 2>&1 )
fi
( cd "$REPO" && python -I demo/golden_model.py >> "$DEMO_LOG" 2>&1 )
"$VLIB" "$SIMLIB/work_demo" >> "$DEMO_LOG" 2>&1
( cd "$SIMLIB" && "$VLOG" -sv -work work_demo \
    ../demo/ecg_rom.v ../demo/sample_pacer.v \
    ../demo/demo_apb_seq.v ../demo/demo_uart_packetizer.v \
    ../demo/top_ecg_rom_demo.v \
    ../adc/adc_interface.v ../window/window_buffer.v \
    ../feature/feature_extraction.v ../ai/ai_classifier.v \
    ../control/control_fsm.v ../apb/apb_slave_if.v \
    ../uart/uart_tx.v \
    ../tb/tb_demo_rom.sv +incdir+.. >> "$DEMO_LOG" 2>&1 )
if grep -q "^Errors: 0, Warnings: 0" "$DEMO_LOG"; then
  total=$((total+1))
  DEMO_TIMEOUT="${DEMO_TIMEOUT:-300}"
  CAPTURE="$SIMLIB/capture_run1.bin"
  rm -f "$CAPTURE"
  timeout "$DEMO_TIMEOUT" "$VSIM" -c -work work_demo tb_demo_rom \
      -do "run -all; quit -f" "+CAPTURE=$CAPTURE" >> "$DEMO_LOG" 2>&1
  rc=$?
  pt="$(grep -oE 'Demo ROM TB +Test Summary: +[0-9]+/[0-9]+ (PASSED|FAILED)' \
       "$DEMO_LOG" | tail -1)"
  p="$(printf '%s' "$pt" | grep -oE '[0-9]+' | sed -n '1p')"
  t="$(printf '%s' "$pt" | grep -oE '[0-9]+' | sed -n '2p')"
  if [ $rc -eq 124 ]; then
    RESULT+=("demo_rom|TIMEOUT"); _report
  elif grep -qE '\*\* (Error|Fatal)' "$DEMO_LOG"; then
    RESULT+=("demo_rom|ELAB_FAIL"); _report
  elif [ -n "$p" ] && [ "$p" -eq "$t" ] && [ "$t" -gt 0 ] \
       && grep -q "Demo ROM TB.*Test Summary: *$p/$t PASSED" "$DEMO_LOG"; then
    # The DUT's own byte capture must also pass the OFFLINE checker
    # (231 bytes / 7 packets / window order / checksum / strict bytes).
    total=$((total+1))
    if ( cd "$REPO" && python -I demo/uart_decode.py --check "$CAPTURE" ) \
         >> "$DEMO_LOG" 2>&1; then
      RESULT+=("demo_capture|PASS"); _report
      SUMMARIES[-1]="| demo_capture | PASS | $LOG_DIR/demo_rom.log |"
    else
      RESULT+=("demo_capture|FAIL"); _report
      SUMMARIES[-1]="| demo_capture | FAIL | $LOG_DIR/demo_rom.log |"
    fi
    RESULT+=("demo_rom|PASS(${p}/${t})"); _report
  else
    RESULT+=("demo_rom|FAIL(summary='${pt:-none}')"); _report
  fi
else
  RESULT+=("demo_rom|COMPILE_FAIL"); _report
fi

# Demo APB STATUS readback (idle / busy / overflow) over REAL APB
# transactions. Reuses work_demo.
PLOG="$LOG_DIR/demo_status.log"
rm -f "$PLOG"; : > "$PLOG"
( cd "$SIMLIB" && "$VLOG" -sv -work work_demo \
    ../demo/ecg_rom.v ../demo/sample_pacer.v ../demo/demo_apb_seq.v \
    ../demo/demo_uart_packetizer.v ../demo/top_ecg_rom_demo.v \
    ../adc/adc_interface.v ../window/window_buffer.v \
    ../feature/feature_extraction.v ../ai/ai_classifier.v \
    ../control/control_fsm.v ../apb/apb_slave_if.v ../uart/uart_tx.v \
    ../tb/tb_demo_status.sv +incdir+.. >> "$PLOG" 2>&1 )
if grep -q "^Errors: 0, Warnings: 0" "$PLOG"; then
  total=$((total+1))
  timeout "${DEMO_TIMEOUT:-300}" "$VSIM" -c -work work_demo tb_demo_status \
      -do "run -all; quit -f" >> "$PLOG" 2>&1
  rc=$?
  pt="$(grep -oE 'Test Summary: +[0-9]+/[0-9]+ (PASSED|FAILED)' "$PLOG" | tail -1)"
  p="$(printf '%s' "$pt" | grep -oE '[0-9]+' | sed -n '1p')"
  t="$(printf '%s' "$pt" | grep -oE '[0-9]+' | sed -n '2p')"
  if [ $rc -eq 124 ]; then
    RESULT+=("demo_status|TIMEOUT"); _report
  elif grep -qE '\*\* (Error|Fatal)' "$PLOG"; then
    RESULT+=("demo_status|ELAB_FAIL"); _report
  elif [ -n "$p" ] && [ "$p" -eq "$t" ] && [ "$t" -gt 0 ] \
     && grep -q "Test Summary: $p/$t PASSED" "$PLOG"; then
    RESULT+=("demo_status|PASS(${p}/${t})"); _report
  else
    RESULT+=("demo_status|FAIL(summary='${pt:-none}')"); _report
  fi
else
  RESULT+=("demo_status|COMPILE_FAIL"); _report
fi

# Pacer representative timing: 50 MHz @ 360 Hz phase-accumulator, short run
# (3 pulses, ROM_WORDS=32). Reuses work_demo. Proves gap/rate/pulse-width/data
# order for the BOARD cadence without a full 2048-sample sim.
PLOG="$LOG_DIR/pacer_repre.log"
rm -f "$PLOG"; : > "$PLOG"
( cd "$SIMLIB" && "$VLOG" -sv -work work_demo \
    ../demo/ecg_rom.v ../demo/sample_pacer.v ../tb/tb_pacer_repre.sv \
    +incdir+.. >> "$PLOG" 2>&1 )
if grep -q "^Errors: 0, Warnings: 0" "$PLOG"; then
  total=$((total+1))
  timeout 200 "$VSIM" -c -work work_demo tb_pacer_repre \
      -do "run -all; quit -f" >> "$PLOG" 2>&1
  ptp="$(grep -oE 'Test Summary: +[0-9]+/[0-9]+ (PASSED|FAILED)' "$PLOG" | tail -1)"
  pp="$(printf '%s' "$ptp" | grep -oE '[0-9]+' | sed -n '1p')"
  pt="$(printf '%s' "$ptp" | grep -oE '[0-9]+' | sed -n '2p')"
  if [ -n "$pp" ] && [ "$pp" -eq "$pt" ] && [ "$pt" -gt 0 ] \
     && grep -q "Test Summary: $pp/$pt PASSED" "$PLOG"; then
    RESULT+=("pacer_repre|PASS(${pp}/${pt})"); _report
  else
    RESULT+=("pacer_repre|FAIL(summary='${ptp:-none}')"); _report
  fi
else
  RESULT+=("pacer_repre|COMPILE_FAIL"); _report
fi
echo

# ---------------------------------------------------------------------------
# Summary table + exit code.
# ---------------------------------------------------------------------------
echo "=================================================================="
printf '  %-24s | test | log\n' "result"
printf '%s\n' "------------------------------------------------------------------"
printf '%s\n' "${SUMMARIES[@]}"
echo "=================================================================="
echo "Passed: $passed / $total"

exitcode=0
for r in "${RESULT[@]}"; do
  case "${r#*|}" in PASS*) : ;; *) exitcode=1 ;; esac
done
echo
echo "Exit code: $exitcode (0 = all pass, 1 = at least one non-pass)"
echo "Logs:      $LOG_DIR"
exit $exitcode
