# AUTOMATION_STATUS — ECG Classifier (Questa 10.7c, Windows)

> State file so the next session continues without re-surveying the repo.
> Updated: 2026-11-01 — **ROM demo IMPLEMENTED** (§9): ROM → pacer → pipeline →
> binary UART vs independent golden; regression now **13/13 PASS, exit 0**
> (12 product + demo_rom). Gowin synth script + SDC written, P&R BLOCKED
> (ACG525 part not confirmed, §9.7). Nothing on the board yet.
> Previous: 2026-10-31 — §7 proposal recorded; 2026-10-30 — 12/12 PASS + RTL
> ReLU fix (§3.1) + two-window latency proof (§3.2).

## 0. Environment (confirmed on this machine, not from docs)

- Questa root: `H:\questasim64_10.7c`
  - `vsim.exe`/`vlog.exe`/`vlib.exe`/`vmap.exe` — QuestaSim-64 **10.7c (2018.08)**,
    confirmed via `vlog -version`/`vsim -version` + install `.version.txt`, **not** 25.1.
  - UVM: `H:\questasim64_10.7c\verilog_src\uvm-1.2\src\uvm_pkg.sv`
- License: works in batch. **No** license-server issue.
- Icarus: **not installed**.
- Toolchain notes (10.7c specifics that matter):
  - `vlog`/`vsim` do **not** accept `-mfcu` (that flag is from the 25.x docs). Use `-sv`.
  - UVM TB uses `-sv` + `+incdir+` + `uvm_pkg.sv` + `+define+APB_RTL_V30`.
  - Libraries: `vlib work_reg` then `vlog/vsim -work work_reg` **from `simlib/`**.
  - Batch limitations confirmed this pass: `wave add`/`wave group`/`radix` print
    "not supported in batch mode" and **silently no-op on good AND bad paths alike**;
    `examine` returns "No objects found" for even top-level signals in the optimized
    build. → **Waveform path verification is only meaningful in the GUI Transcript.**

## 1. Commands

### Batch regression (fast, no GUI)
```bash
cd "H:/IC Design/Code/ECG/ecg-thinh-uvm/scripts"
bash run_regression.sh
```
- `scripts/rtl.f` shared source list → `simlib/work_reg`; fresh lib each run;
  per-test timeout; logs `logs/<name>.log` + `<name>_sim.log`; summary + exit code.
- Latest full result: **12/12 PASS, exit 0** (see §2).

### GUI (one window, Transcript + Waveform)
```bat
"H:\IC Design\Code\ECG\ecg-thinh-uvm\scripts\gui\run_gui.bat" tb_top_ecg_classifier
```
- Reuses `simlib/work_reg` (builds if missing), loads `wave_<tb_top>.do`, `run -all`,
  applies a **per-test calibrated `wave zoom range` after run**, keeps GUI open.
- Zoom values: top = `195000ns..310000ns` (measured, below); control = `0..500ns`;
  default `0..500000ns`.
- ⚠ Questa 10.7c syntax: `wave zoom range <a> <b>` is required — plain
  `wave zoom {a b}` is an error ("unknown or ambiguous subcommand 0ns").
- Both `.do` files are now **self-reporting**: every command is `catch`-wrapped and
  failures print `[wave] FAIL: <cmd> -> <msg>`; a final `[wave] summary: N ok, M failed`
  line makes a broken path visible in the Transcript (replaces the old silent
  `onerror {resume}`).

### Measured pipeline event times (div=20 top TB, timescale 1 ns)
Measured in-TB with a temporary `$time` probe (probe removed afterwards):

| event | time (ns) |
|---|---|
| window_ready (first) | 204104 |
| feature_valid | 214381 |
| mlp_done | 218111 |
| sys_done / uart_send | 218250 |
| sim $finish | 306252 |

## 2. Test results (latest regression, on 10.7c)

| Test | Scope | Result | Notes |
|---|---|---|---|
| adc | unit | PASS 5/5 | overflow latched + asserted |
| window | unit | PASS 5/5 | trigger/read-back/reset |
| feature | unit | PASS **8/8** | + Test 7–8 **two consecutive windows** (fix proof) |
| ai | unit | PASS 6/6 | pipeline smoke (placeholder weights) |
| ai_math | **deterministic** | PASS **5/5** | + Test 4 full non-zero path, Test 5 ReLU clamp |
| apb | unit | PASS 7/7 | CSR R/W + interrupt |
| uart | unit | PASS 2/2 | bit-accurate 8N1 decode |
| control | unit | PASS (markers) | LOAD→feature_start→NORMALIZE |
| smoke_f / smoke_w | smoke | PASS | 8-sample variants |
| top | E2E | PASS 8/8 | UART RX byte decoded `{6'b0,class}` |
| uvm | APB env | PASS (smoke env) | UVM 1.2 + `APB_RTL_V30` |

## 3. Bugs found & fixed (this pass, with reproduction evidence)

### 3.1 **RTL BUG — ReLU clamp was dead code** (`ai/ai_classifier.v`, S_RELU)
- Comparison `if (fc1_out_raw[cnt] > 32'd0)`: `fc1_out_raw` is `signed [31:0]`
  but `32'd0` is an **unsigned** literal → mixed signed/unsigned comparison
  converts the signed operand to unsigned; a negative neuron (-8 = 0xFFFFFFF8
  = 4294967288) compares `> 0` **true** → ReLU returned the *negative value*,
  i.e. ReLU was `identity`, not `max(0,·)`.
- **Evidence (independent reproduction)**: `scripts/probe/tb_relu_probe.sv` on a
  clean lib: `fc1_out_raw[0] = -8` (correct MAC) but `hidden_out[0] = -8`,
  `fc1_out[0] = -8` (should be 0). After fix → both `0`.
- **Fix (minimal, 1 token)**: `32'd0` → `32'sd0` (signed literal). No change to
  MAC, saturation, argmax, or any other stage.
- **Impact on prior results**: any MLP run with negative hidden neurons was
  wrong. With the placeholder zero-weights used in regression, hidden neurons
  are ≥ 0 (biases 0, weights 0 → 0), so the regression results are unaffected;
  the bug only manifests with **trained weights** that produce negative pre-activations.
- Regression re-run after fix: **12/12 PASS** (no behavior change in any existing test).

### 3.2 Feature 1-window latency fix — re-verified with TWO windows
- `feature/feature_extraction.v`: `f_var`/`f_rms`/`f_crest` read NBA registers
  written in the same cycle → reported the **previous** window.
  Fixed with combinational `var_now`/`rms_now` (bit-exact original formulas).
- New **Test 7/8** (`tb_feature_extraction.sv`): two consecutive windows with
  distinct data (8×10 then 8×20), independent expected values:
  | window | f_rms | f_var | f_crest (as-RTL) | f_crest (spec intent) |
  |---|---|---|---|---|
  | A = 8×10 (first, post-reset) | 1 | 6300 | −24576 (0xA000) | 40960 (wraps s16) |
  | B = 8×20 (second) | 6 | 25200 | **2730** (0xAAA) | **13653** (0x3585) |
  - Proves: first window ≠ reset values; second window ≠ first window; all three
    latency-affected features come from the *current* window.
  - Expected values computed independently **and** cross-checked by
    `scripts/probe/tb_feat_2win_probe.sv` (mirrors the RTL width contexts).

### 3.3 **NEW finding: crest expression truncation** (not fixed — owner decision)
- The Test-8 run exposed that in Questa 10.7c the shift `(peak_reg <<< 12)` in
  the crest expression is truncated to **16 bits** *before* the division:
  numerator 81920 → 0x8000 (16384 as s16) → 16384/6 = **2730**, while the
  spec-intent value 20×4096/6 = **13653** (= 3.33 in Q4.12, well inside range).
  So `f_crest` is wrong even for in-range ratios (0.667 instead of 3.33).
- Behavior **frozen** in Test 8 (asserts 2730, with a comment marking 13653 as
  spec intent). No RTL change made — this is an algorithm/owner decision
  (widen the shift/division expression, or change the crest definition).

### 3.4 TB/checker hardening (no RTL change)
- `tb/tb_ai_classifier_math.sv` extended: hierarchical ROM hook
  (`dut.fc1_weights[...] = …` — ROM regs are not ports; this is the intended
  test hook and does **not** bypass MAC/ReLU/argmax, which execute in the FSM)
  + 2 new tests:
  - **Test 4** full non-zero path: f0=8, mean=0, inv_scale=1.0,
    fc1_w[0]=1.0, fc2_w={0.25,0.5,0.75,1.0} → fc2_out = {8192,16384,24576,32768}
    (Q4.12 of {2,4,6,8}), argmax → class 11. Expected hand-computed, not copied.
  - **Test 5** ReLU clamp: fc1_w[0]=−1 → fc1raw=−8 → fc1_out[0]=0, all-zero FC2
    tie → lowest index 0. (This test FAILS on the pre-fix RTL — it is the guard
    against regression of the §3.1 bug.)
- `scripts/gui/wave_*.do` — self-reporting rewrite (see §1), paths cross-checked
  against source: `dut` (top TB instance), `dut.u_ctrl_fsm` (control FSM instance
  in `top_ecg_classifier.v`), `current_state` (registered port, 1-cycle lagged
  copy of internal `state`) + `timeout_cnt`, all confirmed in `control_fsm.v`.
- `scripts/gui/run_gui.bat` — per-test calibrated zoom, correct `range` subcommand.

### 3.5 Changed files (complete list, this verification pass)

| File | Change | Type |
|---|---|---|
| `ai/ai_classifier.v` | **RTL fix §3.1**: S_RELU `32'd0` → `32'sd0` (1 token) | RTL (behavioral) |
| `feature/feature_extraction.v` | 1-window latency fix `var_now`/`rms_now` (§3.2) | RTL (bit-exact) |
| `tb/tb_feature_extraction.sv` | new Tests 7–8 (two consecutive windows, independent expected; Test 8 freezes as-RTL crest 2730 w/ spec-intent 13653 noted) | TB |
| `tb/tb_ai_classifier_math.sv` | ROM-hook task + Tests 4–5 (non-zero full path, ReLU clamp); wired `fc1_out`/`fc2_out` ports | TB |
| `tb/tb_adc_interface.sv` | Test 3 latches + asserts `adc_overflow` | TB |
| `tb/tb_window_simple.sv` | `write_counter` → `write_ptr` (elab fix) | TB |
| `tb/tb_top_ecg_classifier.sv` | transient `$time` event probe **added then removed** (net-zero, used only to calibrate zoom); UART-RX byte decode retained | TB |
| `scripts/gui/wave_tb_top_ecg_classifier.do` | self-reporting rewrite (catch + `[wave] summary`), calibrated zoom note | automation |
| `scripts/gui/wave_tb_control_fsm.do` | same self-reporting rewrite | automation |
| `scripts/gui/run_gui.bat` | per-test `wave zoom range` (top `195000ns..310000ns`, control `0..500ns`, default `0..500000ns`) | automation |
| `scripts/probe/tb_relu_probe.sv`, `scripts/probe/tb_feat_2win_probe.sv` | new isolated probes (reproduction evidence) | probe |
| `docs/AUTOMATION_STATUS.md` | this document | docs |

Scratch libs `work_wave`/`work_vw`/`work_wv` and probe do-files were deleted from
`simlib/` after use; `work_reg`/`work_uvm`/`work_probe` remain (regression/probes reuse them).

## 4. Open / needs-a-decision (NOT silently changed)

- **Real MLP weights**: `weight.hex` (164 words) **not in repo**; `mlp_weights_rom`
  not instantiated; inference runs on placeholder zeros → any `class_code=00`
  proves the pipeline, **not** classification quality. Retrain (AI owner).
- **`f_crest` expression truncation** (§3.3): spec-intent 13653 vs RTL 2730 for the
  8×20 window. Decide: widen expression (e.g. `peak<<<12` in ≥32-bit before divide)
  or re-specified crest scaling. Until decided, Test 8 freezes current behavior.
- **`f_zc` / `f_half_ratio`**: upstream baseline clamp → samples 0..86, bit7 never
  set → `f_zc≡0` in-system. Decide: clamp-then-zero vs mean-referenced zc.
- **Variance formula** is the team's custom bit-exact convention — kept as-is.
- **360 Hz (div=140000) not simulated**: top TB overrides `SYS_SAMPLE_RATE_DIV=20`
  for speed. Timing-representative run at the real divider outstanding.
- Synthesis script paths (`synthesis/run_synth.tcl` → `rtl/...`) still stale;
  write/read-collision on the circular buffer unverified at synthesis.

## 5. Verification limits of the agent (what could NOT be confirmed)

- **GUI waveforms**: the agent launches the GUI and reads the Transcript/logs,
  but **cannot read the desktop screen**. The `.do` files self-report their own
  success/failure now, so a failed path will show `[wave] FAIL …` in the
  Transcript — check the final `[wave] summary:` line when the GUI opens.
- Batch mode can NOT validate `wave add` paths (no-op on both good and bad
  paths, "not supported in batch mode"). Path names were validated
  **statically** against `top_ecg_classifier.v` / `control_fsm.v` / the TB sources.
- No synthesis, no FPGA, no div=140000 timing run performed.

## 6. Suggested next steps (short list, pre-existing)

1. AI owner: deliver trained `weight.hex` → load via ROM write path, re-run top TB.
2. Feature owner: decide crest expression width (§3.3) + zc/half-ratio semantics;
   add a real-ECG segment to the top TB stimulus (currently sine).
3. Fix `synthesis/run_synth.tcl` paths; target Gowin; check Fmax/resources.
4. Add SVA for `window_ready` no-double-fire and write/read collision corners.
5. Confirm UART byte on hardware at real 115200.

## 7. NEW PROPOSAL (2026-10-31) — standalone ROM-driven demo + Gowin ACG525 prep (**NOT started**)

Request: build a self-starting demo path — ECG samples in ROM → 360 Hz sample
pacing (clock-enable, no PLL) → existing pipeline → binary UART packet to PC —
then prepare a Gowin build for the ACG525 board. **Nothing in this section
exists yet; it is a hand-off plan**, mapped to the requested items:

- **§7.2 Data**: source + conversion script + reproducible hex. Prefer PhysioNet
  MIT-BIH; if unavailable, clearly mark **synthetic**. ≥3 windows of 512,
  stride 256. Report min/max/clipping + post-window-preprocess range. No
  per-window normalization to force thresholds; no disease labels on synthetic.
- **§7.3 ROM + pacer module**: synthesizable ROM + 50 MHz clock-enable pacer
  producing avg 360 sps (50 MHz not divisible by 360 → fractional /
  phase-accumulator divider, **quantify the error**, 1-cycle pulses). Must
  coexist with `adc_interface`'s rate gate without double-dividing or dropping
  samples (test the interaction). Handle read latency in sim **and** Gowin
  (RAM inference).
- **§7.4 Demo top** (`top_ecg_rom_demo`): reuse existing pipeline, deterministic
  reset + auto-start, small APB sequencer (proper setup/handshake) if CSR
  config needed, no internal `force` in synthesizable RTL. Handles multiple
  consecutive windows. Do not expose the full APB bus on FPGA pins. Check
  whether the FSM needs one start or a restart per result.
- **§7.5 UART packets**: header/type/length + simple check; document byte
  order, signedness, scaling, and a decode method. 115200 8N1 at 50 MHz
  (**report actual baud**). Do NOT change the product top's one-byte protocol;
  keep a single TX controller (never tie two UART outputs together). Latch data
  before serializing; guarantee a packet completes before the next starts.
  Python decode script + offline-testable parser.
- **§7.6 Demo TB + golden**: independent expected features (from formulas /
  confirmed Q4.12 format, **not** copied from the DUT). For open behaviors
  (§3.3 crest, variance, zc) keep TWO distinct checks: (1) match current RTL,
  (2) match math spec. Weights placeholder = flow + math check only, NOT
  accuracy. Decode `uart_txd` in the TB against independent expected packets.
  Test mid-way reset + replay. No `force` for start/data/results in the
  integrated demo test. Two configs: (1) fast-paced but still slower than the
  pipeline/UART settle, (2) representative 50 MHz @ avg 360 Hz. Keep
  golden-expected, sim results, and board-compare files clearly separated.
- **§7.7 GUI + regression**: GUI launcher for the demo TB + grouped waveform
  config (ROM/sample, window, feature, MLP, APB, UART) with timeline-matched
  zoom, keep GUI open; state the desktop-observation limit. Add the demo test
  to `run_regression.sh` with a timeout, its own log, a checker, and a correct
  exit code. Run the affected tests while editing, full regression at the end.
- **§7.8 Gowin build (only after sim passes)**: separate synth script reusing
  the existing valid config; SDC for the 50 MHz input; CST **only** from
  confirmed pins/voltages/polarities (ACG525 board doc says: XTAL T9,
  LED0-3 = D14/C14/B9/A9, KEY0-2 = B16/A15/C15, UART TX/RX = V8/U8 — **to be
  re-confirmed against the actual ACG525 reference + package before use, do
  not assume**). Do not assign unused APB/ADC to FPGA pins. Run synthesis if
  license/EDA allow; check ROM inference, RAM/DSP usage, latches, signedness,
  and what optimizes away (note explicitly whether zeroed weights let the MLP
  shrink away). P&R only when target+constraints are sufficient; distinguish
  synth timing estimates from post-P&R. Do NOT claim board-ready while timing/
  constraints are open. No FPGA flashing this session.
- **§7.9 Deliverable**: a ROM-demo guide (data source + conversion,
  architecture, reset/start, clock/rates/baud, sim/GUI/regression/Gowin
  commands, UART format + decode, a verified-results table, pre-board open
  items) + a final report covering the 6 requested points (what was built,
  real vs synthetic data, test + UART expected/actual, synth/P&R result or
  why blocked, what the user must supply, one concrete next on-board step).

## 8. Open questions / blocked items for §7 (report, don't silently resolve)

- ECG source: is PhysioNet reachable here? Fallback is a clearly-labeled
  synthetic stimulus (infra development only, no disease labels).
- ACG525 pinout / I/O voltage / reset polarity / LED active level: confirm
  from board docs + Gowin package before CST; do not assume.
- `weight.hex` still absent → the demo proves the **pipeline**, not
  classification quality (see §4).

## 9. ROM DEMO — IMPLEMENTED (2026-11-01) — self-start ROM → pipeline → UART

§7 is now **built and passing**. Regression = 13/13 (12 product + `demo_rom`).

### 9.1 Files (new)

| Path | What |
|---|---|
| `demo/ecg_rom.v` | 8-bit ROM, `$readmemh` + registered read (1-cycle latency) |
| `demo/sample_pacer.v` | 32-bit phase-accumulator, clock-enable; avg TARGET_HZ; single pass, no loopback; 1-cycle valid pulse |
| `demo/demo_apb_seq.v` | deterministic APB bring-up + per-result RESULT read + `pkt_req` + FSM re-start; no external CPU, no FPGA APB pins |
| `demo/demo_uart_packetizer.v` | **sole** driver of `uart_tx`; 33-byte binary packet, latches before serializing, drop latch |
| `demo/top_ecg_rom_demo.v` | demo top: ROM+pacer → existing adc_interface(window/feature/ai/control_fsm) → packetizer→uart_tx. Reuses product modules unmodified |
| `demo/ecg_convert.py` | real MIT-BIH 100 ch0 (360 sps) → 8-bit hex. `read_channel` fixed (was `stride=1` bug returning the interleaved whole stream) |
| `demo/golden_model.py` | independent golden from the on-disk `ecg_rom.hex`; emits `expected_packets.{sv,json}` + a strict byte-mask |
| `demo/uart_decode.py` | offline parser (no board) + self-test vs golden |
| `demo/test_ecg_convert.py` | converter unit tests (channel separation, order, endianness, invalid input) |
| `tb/tb_demo_rom.sv` | demo TB: 8N1 decode of `uart_txd`, 33-byte reassembler, strict-golden compare, reset+replay. No `force` on start/data/result |
| `synthesis/run_demo_synth.tcl` | Gowin synth for the demo top (fixed real paths; device still PLACEHOLDER) |
| `synthesis/demo_ecg_rom_demo.sdc` | clock-only SDC (50 MHz confirmed); CST pinned pending part confirmation |
| `scripts/gui/run_gui_demo.bat` + `scripts/gui/wave_tb_demo_rom.do` | GUI launcher + grouped, self-reporting waveform |

### 9.2 Data: REAL, not synthetic
- **MIT-BIH record 100, ch0 (MLII), 360 sps**, sampled 1000..3047 (N=2048).
  Downloaded 2026-10-31 from the PhysioNet S3 mirror (`physionet-open.s3.amazonaws.com/mitdb/1.0.0/100.dat`), see `demo/data/SOURCE.md`.
- 12-bit → 8-bit (WFDB 212): linear `round((raw−min)·255/range)` per segment; **no per-window
  normalization, no threshold-tuning**. post-baseline (window_buffer clamp @169)
  range is **0..86** → `f_zc≡0` across all windows (known §4 open item, reported,
  not corrected).
- **`read_channel` bug found & fixed (2 passes)**:
  1. (pass 1) old code did `vals[channel::n]` with `n=len//n`→`stride=1`,
     returning the whole interleaved stream, not channel 0.
  2. (pass 2, 2026-11-01) the file was assumed **int16**, but `100.hea`
     declares WFDB format **212** (signed 12-bit, 2 samples/3 bytes):
     1.950.000 B = 650 000×2×12/8 exact, int16 would need 2.600.000 B and
     give 487 500/ch ≠ 650 000 per .hea. Decoded ch0 baseline = 995 = .hea
     baseval; the int16 mis-decode gave −32717..+32681 (corrupted). The old
     hex/golden (and thus every "vs golden" PASS before 2026-11-01) ran on
     **mis-decoded data**. `ecg_convert.py` now decodes 212 + validates the
     .hea and rejects truncated files; hex + golden regenerated;
     `test_ecg_convert.py` locks the packing with hand-derived fixtures.
  Now the golden reads the **on-disk hex** (single source of truth) and
  expected values are computed independently from spec.

### 9.3 Clock / sample / baud
- Pacer: `PHASE_INC = round(2^32·TARGET_HZ/CLK_HZ)` (64-bit math). Board =
  50 MHz @ 360 Hz target → `PHASE_INC=30924`, **actual avg rate = 360.002741
  Hz** (= 50e6·30924/2^32, +7.6 ppm; gaps 138887/138888 = round of
  2^32/30924 = 138887.831). Do not quote as "exactly 360". FAST sim = 33 333
  Hz (gap ≈ 1500 cycles) so a 33-byte packet (33×10×437 = 144 210 cycles)
  always finishes before the next window result — no drops. REPRE config = 360 Hz.
- UART: `baud_div=437` (APB), at 50.0 MHz the **actual baud = 50e6/437 = 114 416**
  (−0.68% vs 115200, within UART tolerance). Reported, not assumed.

### 9.4 Golden assertion split (settled vs owner-open)
The demo asserts **byte-exact on the settled features + framing** (sync/type/len/
win_index, f_rms/f_var/f_peak/f_zc/f_ptp/f_crest-as-RTL-note/f_half/f_max,
class, flags) via `exp_mask`. The **tool-dependent / owner-open items are
REPORTED, not forced**:
- `f_crest` — 16-bit shifted numerator truncation (§3.3, this pass froze 2730
  as-RTL vs 13653 spec); reported as open-delta in the TB log.
- `f_rr*` family — RTL `rr_timer` reset is dead code, so it captures event
  position, not interval; reported as open-delta.
- `f_zc` — baseline clamp → 0 (see §4).
All 7 windows pass the strict comparison; the 4 middle windows show exactly one
open byte differing (the checksum, which sums the open crest/RR bytes) — expected.

### 9.5 Test result (latest full regression, 10.7c)
| Test | Result |
|---|---|
| 12 product tests | PASS (unchanged from §2) |
| `demo_rom` | **PASS (2/2)** — Run1 single-pass (7 packets, all strict-match golden,
  `adc sample_count=2048`, `end_of_data=1`, `drop=0`, `winR=7`); Run2 mid-way
  reset+replay (replay packets strict-match, no drop) |
| `demo/test_ecg_convert.py` | 5/5 PASS |
| `demo/uart_decode.py` self-test | PASS (7 golden packets, corrupt-checksum
  rejected, resync ok) |

### 9.6 Gowin build status
- `synthesis/run_demo_synth.tcl` + `demo_ecg_rom_demo.sdc` written; synth
  options reuse the valid product config; paths fixed to the real `demo/`+`pipeline`
  layout. **NOT run** this session (device part not confirmed).
- **P&R BLOCKED**: the ACG525 chip/package/speed is **not found** under
  `H:\Gowin\Gowin_V1.9.9_x64\IDE\data` — per the task, do **not** assume the
  part. `set_device` is a PLACEHOLDER until the user confirms the part.
- Zeroed MLP weights: `ai_classifier` keeps `fc1/fc2` weight registers at 0
  (placeholder); MAC/ReLU/argmax still execute — report whether the tool prunes
  the dead-zero path during synthesis. Do NOT claim classification accuracy.

### 9.7 Still open before board
1. **Confirm the ACG525 part/package/speed** (and I/O voltage, reset/LED
   polarity) → then fill `set_device` + a CST pin map for demo pins only
   (sys_clk, sys_rst_n, uart_txd/rxd, status_led, demo_done/overflow/class;
   **no APB/ADC pins**).
2. **Deliver trained `weight.hex`** → replace the placeholder zeros; re-run demo.
3. **Decide crest width (§3.3) + zc/RR semantics** — currently reported-open.
4. **No board flashing this session.**

## 10. INDEPENDENT VERIFICATION REVIEW (2026-11-01) — see `docs/VERIFICATION_REVIEW.md`

A fresh, source-reading + fault-injection audit of RTL and checkers before FPGA.
Findings live in `docs/VERIFICATION_REVIEW.md`; this section is the short record.

### 10.1 Real evidence this session (not prior claims)
- Full regression re-run on 10.7c: **15/15 PASS, exit 0** (12 product + `demo_rom`
  2/2 + `pacer_repre` 5/5 + `rr_probe` 3/3).
- **Fault injection (scratch copies, working RTL untouched)** — proves the key
  checkers actually catch their bugs:
  | fault reintroduced | checker | result |
  |---|---|---|
  | ReLU `32'sd0`→`32'd0` | `tb_ai_classifier_math` | FAIL 4/5 (Test 5) |
  | rr_timer guard removed | `tb_rr_probe` | FAIL 1/3 (f_rr=21 absolute) |
  | window-latency fix reverted | `tb_feature_extraction` | FAIL 5/8 (Tests 7-8 stale) |
- Independent Python golden cross-check: all 7 demo packets byte-exact on every
  STRICT byte; open deltas only on `f_crest` (16-17) + checksum (32) for w3/w6.

### 10.2 Doc/artifact mismatches found (no data bug, but must fix)
- **§9.4 is stale**: the shipped `expected_packets.sv` masks only crest (16,17)
  + checksum (32); the **RR family (22-29) IS asserted strict** against the
  Python model. That makes RR a *mirror* check (won't catch a re-derivation
  that shares the assumption), not independent. Decision: keep strict (cheap)
  or re-derive 512-path RR intervals independently (ties to the 11-vs-12
  off-by-one owner item).
- **"exactly one open byte (the checksum)" is wrong**: w3/w6 differ on **3**
  open bytes (crest low, crest high, checksum). Log's `open-delta=1` counts
  packets, not bytes. Cosmetic, log wording only.
- `logs/regression_full.log` in the repo was **stale** (showed `demo_rom
  COMPILE_FAIL`, exit 1) while §9.5 claimed 13/13 — now reproduced 15/15.
  Regenerate logs after each run; a committed log contradicting the doc
  misleads handoff.

### 10.3 Confirmed-sound (read + sim)
- ADC rate gate (`>=div-1` exact period), merged single-always EX2000 fix,
  overflow latch+report. Demo div=1 path forwards every pacer pulse
  (sample_count==2048).
- window trigger at totals 512/768/... only, oldest-addr wrap, combinational
  read alignment. Collision edge = BRAM first-write-first-read, SVA still owed.
- control_fsm v3.1 blocking next_state commit (2-cycle-lag bug structurally
  gone). Marker TB weak but E2E top + demo exercise it.
- MLP normalization/MAC/saturation/argmax covered by `tb_ai_classifier_math`
  (independent hand-computed); ReLU guard proven live by fault injection.

### 10.4 Data-correctness items open for owners (frozen, not silently fixed)
- **f_crest truncation** (§3.3 / review F-C): 16-bit `peak<<<12` numerator
  wraps → 0.667 instead of spec 3.33 for nearly all real windows. Decide.
- **f_rms is mean-of-squares**, not sqrt (frozen convention; retrained weights
  must match).
- **f_zc ≡ 0 in-pipeline** (baseline clamp keeps samples 0..86, bit7 unset);
  zc math works on signed input (TB 6) but is dead on this data path.
- **Demo APB STATUS dead** (MODULE_REPORT §15.3): `sys_busy` undriven,
  `sys_overflow` unconnected → STATUS busy/overflow always 0. Not a data bug
  (packetizer takes flags directly); fix or drop the claim before board.
- **`mlp_weights_rom.v` is dead** (reads an out-of-repo hex, uninstantiated,
  still in `rtl.f`); `ai_classifier`'s internal ROM-write path only wires a
  handful of addresses, so a full weight.hex load is NOT implemented anywhere.
- **div=140000 (real 360 Hz) pipeline timing never simulated** (top TB uses
  div=20); control_fsm `LOAD_TIMEOUT=100e6` must exceed real window+feature
  latency — one timing argument or run owed before board.

### 10.5 Bottom line
Pipeline datapath has **no functional blocker**: every data-correctness fix
found has a live, sensitive checker (reproduced then caught). Before FPGA
build: owner decisions on crest/zc/RR semantics, real weights if
classification matters, a div=140000 timing check, and closing the
doc/artifact mismatches in §10.2. P&R remains blocked on confirmed ACG525
part + `.cst` (§9.7). No board flashing this session.

## 11. ECG SOURCE DATA VERIFICATION (2026-11-01) — 212 decoder fix

Task: pause P&R, verify the ECG source data independently of prior claims.

### 11.1 Confirmed (byte-level evidence, not report description)
- `100.hea` field 3 = **212** (WFDB: signed 12-bit, 2 samples per 3 bytes).
- `100.dat` = 1 950 000 B = 650 000 × 2 ch × 12 bit / 8 exactly; int16 would
  be 2 600 000 B. **Native 212, no conversion step, no intermediate artifact.**
- 212 decode ch0[0] = 995 = `.hea` **initial value** (MLII; 1024 = digital
  offset/ADC zero, not a baseline) → framing OK. Segment 1000..3047 ch0:
  min 907, max 1213, p2p = 306 units = **1.53 mV** at 200 units/mV (5 µV/unit).
  No clinical amplitude or heart-rate is derived from this data (record 100
  is documented normal sinus; no AF/RR label is asserted here).
- The previous int16 read (−32717..+32681, repeating byte-frame pattern) is
  corrupted data; the on-disk `ecg_rom.hex` matched it 2048/2048 → **all
  "vs golden" PASSes before this session ran on mis-decoded data.**

### 11.2 Fixed
- `demo/ecg_convert.py`: 212 decode (bit-packing + sign extension), 2-channel
  separation + order, `.hea` cross-check (channel/rate/sample-count),
  explicit data-loss policy (truncated group = hard error, no silent trim).
- `demo/test_ecg_convert.py`: hand-derived byte fixture (negatives + edges
  0/2047/−1/−2048), incomplete-group rejection, invalid-channel raise.
- `demo/ecg_rom.hex` + `demo/golden/*` regenerated (golden from the hex,
  independent of the DUT; no expected values adjusted to fit the DUT).
- `tb/tb_pacer_repre.sv`: data-order constant followed the new ROM content
  (`20 20 21`); timing expecteds **unchanged** — convention now documented
  in the TB: `gap` = cycle-index difference (inter-pulse period,
  138887/138888); idle cycles strictly between pulses = gap−1.
- Timing units corrected in `control_fsm.v` comment + review F-K:
  140000 cycles @50.4 MHz = **2.778 ms**/sample (not s); LOAD_TIMEOUT 100e6
  cycles = **1.984 s** (not 100 s).
- `docs`/`SOURCE.md`/`golden_model.py` stale "int16/16-bit" claims updated.

### 11.3 Test results (this session, regenerated data)
| test | result |
|---|---|
| `demo/test_ecg_convert.py` (5 tests, incl. independent real-data 212 check) | PASS |
| `demo/uart_decode.py` self-test | PASS (7 packets, corrupt-checksum rejected) |
| `tb_demo_rom` (Questa, golden vs DUT) | PASS 2/2 |
| `tb_pacer_repre` | PASS 5/5 |
| `tb_control_fsm_timeout` (new, `control_tmo`) | PASS 4/4 |
| full regression (`run_regression.sh`) | **16/16 PASS, exit 0** |

(The 15/15 recorded earlier in §11.3 pre-dates this session's addition of the
`control_tmo` test and the converter real-data check; current count is 16/16.)

### 11.4 LOAD_TIMEOUT — investigated, guard is LIVE (earlier "dead code" note corrected)
Re-reading S_LOAD: `timeout_cnt` is reloaded **only** on the two event branches
(`timeout_cnt <= LOAD_TIMEOUT` at `control_fsm.v:184,189`, fired on `window_ready`
and `feat_valid` pulses); the S_LOAD *hold* branch does **not** reload, so the
top-level decrement (`control_fsm.v:135`) runs every hold cycle and the
`timeout_cnt==0 → S_IDLE` escape **is reachable**. My §11.4-draft note
("reloaded on every branch / dead code") was **wrong** — a `window_ready`
pulse is a single-cycle event, not a hold.

Proven by a new focused test `tb/tb_control_fsm_timeout.sv` (registered as
`control_tmo` in the regression), which overrides the module parameter
`LOAD_TIMEOUT` (default unchanged; both timeouts are now `parameter`s on
`control_fsm`) to 120 cycles:
- **T1 HANG** (no `window_ready`/`feat_valid` in S_LOAD): FSM escapes to
  `S_IDLE` at `cycles_in_load = 121 ≈ LOAD_TIMEOUT`; **no spurious `done`**.
  → the hang-escape path is live and correct; it does **not** fabricate a
  success on timeout (it returns to IDLE, per spec intent "không deadlock").
- **T2 NORMAL** (`window_ready` then `feat_valid` arrive early): reaches
  `S_NORM` — the timeout does **not** fire prematurely on the normal path.
Result: `Test Summary: 4/4 PASSED`.

- **UART checksum** (separate, verified no change needed): computed
  independently over all received bytes in the checksum scope, **including
  the masked feature bytes** — `tb_demo_rom.pkt_is_valid` sums
  `cur[p][2..31]` from captured bytes and compares to `cur[p][32]`
  (`tb/tb_demo_rom.sv:164`). Requirement met as-is.

So there is **no FSM bug to fix here** — the reload-on-event design is
intentional and the timeout guard is the documented failure escape. The one
open *recovery-semantics* question (report, not silently chosen): on timeout
the FSM silently returns to `S_IDLE` with no `done`/`irq`; if the board needs
a distinct "load-timeout" status to surface to the host, that is a new
feature, not a fix. Not implemented.

### 11.5 Independent-reference limit (stated, not hidden)
WFDB tooling (`wfdb` python / WFDB MATLAB) is **not installed**; not installed
without permission. Without it, the 212 framing was checked against the
`.hea` (an external, decoder-independent source) rather than against the
decoder's own output:
- file-size 1 950 000 B ≡ 650 000×2×12/8 (whole-record integrity);
- decoded sample count per channel = 650 000 = `.hea` `nsamp`;
- **both channels assert against `.hea` check-fields** (external, written by
  the official WFDB tools from their own decode of this exact file): ch0 (MLII)
  initial = 995 = `.hea` baseval **and** channel-sum mod 2¹⁶ = 0xA98D = `.hea`
  scale −22131; ch1 (V5) initial = 1011 = `.hea` baseval **and** channel-sum
  mod 2¹⁶ = 0x4E54 = `.hea` scale 20052.
- **Decoder bug found & fixed (2026-11-02, channel 1):** the shipped 212
  second-sample formula `ch1 = ((b1&0xF0)>>4)|(b2<<4)` placed byte2 as the
  *high* byte of sample 1, giving ch1[0]=−205 and sum 0x570C — wrong. The
  correct layout is `ch1 = b2|((b1&0xF0)<<4)` (byte1 high nibble = ch1 top-4,
  byte2 = ch1 low-8, i.e. each 12-bit sample stored low-byte-first). Only that
  layout reproduces BOTH V5 `.hea` invariants. ch0's formula was already
  correct (matches MLII baseval + scale), which is why ch0 PASS masked the ch1
  error. Both `demo/ecg_convert.py::read_channel` and the test's independent
  unpacker are fixed; `test_real_data_independent_212` now asserts baseval +
  scale for **both** channels, so a regressed layout FAILs rather than printing
  a fingerprint.
None of this *replaces* a byte-exact WFDB diff. To close it before board,
`python -m pip install wfdb` (or WFDB MATLAB), then diff the first N samples
of `wfdb.read` vs `ecg_convert.read_channel` on **both** channels over the
head and the 1000..3047 segment — a ~10-minute check, not yet run. No RR,
heart-rate, or rhythm label is asserted anywhere in this project from RTL
threshold crossings.

### 11.6 Decoder-independent per-channel integrity (asserted, both channels)
`demo/test_ecg_convert.py::test_real_data_independent_212` uses a
self-contained 212 unpack (NOT `read_channel`) and, for **both** channels,
asserts two external `.hea` invariants — first sample = `.hea` baseval and
full-channel sum mod 2¹⁶ = `.hea` `scale` field:
- ch0 (MLII): n = 650 000; ch0[0] = 995 = baseval; sum16 = 0xA98D = −22131 = scale.
- ch1 (V5):  n = 650 000; ch1[0] = 1011 = baseval; sum16 = 0x4E54 = 20052 = scale.
Both PASS. A 650 000-sample full-channel sum matching the `.hea` `scale`
field independently of the first sample is a strong (not just "fingerprint")
confirmation that the unpack is correct on both channels. The `.hea` fields are
external (written by the official WFDB tools); a byte-exact diff against the
official `wfdb` reader remains an optional extra check (§11.5), not yet run.

