# VERIFICATION_REVIEW — Independent RTL & checker audit (2026-11-01)

Scope: pre-FPGA-build review of the product top (`top_ecg_classifier`, 50.4 MHz
config) and the ROM demo top (`top_ecg_rom_demo`, 50 MHz board config). Evidence
is from **this session's runs**, not from prior PASS claims. No RTL in the working
tree was modified during this review; fault injection was done on scratch copies.

## 1. Evidence actually run in this session

| Item | Result | Where |
|---|---|---|
| Full regression (`scripts/run_regression.sh`, Questa 10.7c, fresh libs) | **15/15 PASS, exit 0** | fresh run 2026-11-01 (logs regenerated) |
| `demo_rom` (7 windows vs independent golden, 8N1 decode, reset+replay) | PASS 2/2 | `logs/demo_rom.log` |
| `pacer_repre` (50 MHz @ 360 Hz gap check) | PASS 5/5 | `logs/pacer_repre.log` |
| Fault injection F1: ReLU reverted to `32'd0` (scratch copy) | `tb_ai_classifier_math` **FAIL 4/5** (Test 5: fc1_out[0]=-8) | scratch run |
| Fault injection F2: rr_timer guard removed (scratch copy) | `tb_rr_probe` **FAIL 1/3** (f_rr=21 absolute index) | scratch run |
| Fault injection F3: window-latency fix reverted (scratch copy) | `tb_feature_extraction` **FAIL 5/8** (Tests 7–8: rms/var stale) | scratch run |
| Golden cross-check (Python, independent of Questa) | all 7 demo packets byte-exact on every STRICT byte; open deltas only on f_crest (16-17) + checksum (32) for w3/w6 | `demo/golden/expected_packets.sv` vs `logs/demo_rom.log` |

Conclusion on the prior session's claims: the "15/15 PASS" in
`AUTOMATION_STATUS.md` §9.5 was **not reproducible from the committed
`logs/regression_full.log`** (that log showed `demo_rom COMPILE_FAIL`, exit 1 —
stale/partial artifact). The fresh run this session confirms 15/15 exit 0, so the
claim is *now* backed by evidence, but the saved log was not.

## 2. Checker audit — which tests have independent expected values

| Test | Independent expected? | Nature |
|---|---|---|
| `tb_adc_interface` | Partial — data value (0x55), overflow-latch, reset | Behavior check, not golden math |
| `tb_window_buffer` | Partial — counts (1/2 ready pulses), read-back smoke | Markers + counts |
| `tb_feature_extraction` | **Yes** — hand-computed per-window values (Tests 1–8 incl. two-window latency) | Real math checks; crest **frozen as-RTL** (2730/−24576) with spec-intent noted |
| `tb_rr_probe` | **Yes** — interval semantics (11/9), distinguishes fixed vs broken | Real check |
| `tb_ai_classifier_math` | **Yes** — hand-computed Q4.12 results, ROM-hooked weights; Test 5 guards the ReLU fix | Real math checks |
| `tb_uart_tx` | **Yes** — bit-accurate 0x55/0x81 decode | Real |
| `tb_apb_slave_if` | Partial — CSR R/W echo | Interface check |
| `tb_control_fsm` | **No — marker-only** (`Reached LOAD`, `pulsed`, `Reached NORMALIZE`) | Smoke |
| `tb_ai_classifier` (non-math) | **No — pipeline smoke** (zero weights, any class) | Smoke only; do not cite as math evidence |
| `tb_top_ecg_classifier` | Partial — E2E flow, UART byte == {6'b0,class}; class value NOT checked against a golden (zero weights → always 00) | Flow check |
| `tb_demo_rom` | **Yes** — byte-exact vs `golden_model.py` (independent Python, on-disk hex as source) | Real, with masked open bytes (below) |
| `tb_pacer_repre` | **Yes** — expected gap 138887/138888, pulse width 1 | Real |

## 3. 12-feature coverage table (asserted / masked / why)

| Feature | asserted anywhere | where | masked/dominated | why |
|---|---|---|---|---|
| f_rms | Yes | feature TB 2,7,8; demo strict | value is **mean-of-squares**, not sqrt (sum_sq>>9) | frozen convention |
| f_var | Yes | feature TB 7,8; demo strict | custom bit-exact formula, negative values occur | owner convention, frozen |
| f_peak | Yes | feature TB 1,3,5; demo strict | — | |
| f_zc | Yes (unit) | feature TB 6 (alt-sign pattern) | **always 0 in-pipeline**: baseline clamp keeps samples 0..86 → bit7 never set | known degenerate; spec open |
| f_ptp | Yes | feature TB 1; demo strict | — | |
| f_crest | **frozen as-RTL, NOT spec** | feature TB 5,7,8 (2730/−24576); demo bytes 16-17 **masked** | Questa 10.7c 16-bit numerator truncation → 0.667 where spec says 3.33 | owner decision open |
| f_half_ratio | Yes | feature TB 6; demo strict | always 4096 (all samples positive after clamp) on demo data | degenerate on this data, not masked |
| f_max | Yes | demo strict | — | |
| f_rr | Yes (probe) | `tb_rr_probe` (interval=11 semantics); demo bytes 22-23 asserted strict | off-by-1 vs textbook (11 vs 12) is owner-open; **but the demo golden currently asserts it strict** | see §4 |
| f_rr_prev | Yes (probe) | same | same | same |
| f_rr_ratio | Yes (probe guard) | feature TB 4 (divide-by-zero guard → 4096); demo strict | — | |
| f_rr_diff | Yes (probe) | same | same as f_rr | |

Note: `tb_rr_probe` checks NUM_SAMPLES=32 probe, not the 512-sample DUT path;
the 512-path RR check is the demo golden only.

## 4. Findings (data-correctness first, then docs)

### F-A — Demo golden asserts RR bytes strict; §9.4 text is stale
The shipped `expected_packets.sv` masks **only** bytes 16,17 (crest) and 32
(checksum). Bytes 22-29 (f_rr, f_rr_prev, f_rr_ratio, f_rr_diff) are asserted
byte-exact against the Python model. `AUTOMATION_STATUS.md` §9.4 says the RR
family is "reported, not forced" — that is not what the artifact does.
Because the Python RR model is a bit-exact mirror of the guarded-RTL fix,
this is a mirror check, not an independent one: it will NOT catch a future
regression if the golden and RTL are re-derived from the same wrong assumption.
Decision needed: (a) keep strict (mirror-only, cheap), or (b) unmask RR and
re-derive the 512-path expected intervals from an independent interval-count
(11 vs 12 off-by-one is the open owner item).

### F-B — `open-delta` count in demo log is wrong by 2 (cosmetic)
`tb_demo_rom`'s `open_delta_count` prints 1 for w3/w6 (it counts packets
where any open byte differs, not bytes); my byte-level compare finds **3**
differs (16, 17, 32). Also §9.4's "exactly one open byte (the checksum)"
is inaccurate. No functional impact; log wording only.

### F-C — `f_crest` truncation is a real spec divergence, frozen
Confirmed by F1-style reasoning and feature TB Test 8: for the 8×20 window,
RTL gives 2730 (0x667 Q4.12 ≈ 0.667) vs spec intent 13653 (≈3.33). The 16-bit
numerator `peak_reg <<< 12` overflows for peak ≥ 4 (4*4096=16384 = 0x4000
still fits, but 81920 wraps to 16384 in s16). This affects **every** window
where peak*4096 > 32767, i.e. nearly all real windows — the demo log shows
w3/w6 crest deltas. Owner decision required before board.

### F-D — `f_rms` is mean-of-squares, not RMS (frozen convention)
`f_rms = sum_square >> 9` = mean of squares in Q0.4-ish scaling, no sqrt.
Golden + TBs are built on this. Documented, not a bug, but the name and the
retrained-weight contract must match the AI owner's expectation.

### F-E — `f_zc` is dead in-pipeline (known, reported)
Baseline clamp (window_buffer, samples < 169 → 0) keeps all demo samples in
0..86 → bit7 never set → f_zc ≡ 0 for any real ECG data through this path.
Feature TB 6 proves the zc *math* works given signed input; the in-system
value is 0 by data property, not by zc logic. Decide: feed pre-clamp data or
mean-referenced zc.

### F-G — Demo APB STATUS is dead (EX1998/EX2565 in synth, noted in MODULE_REPORT §15.3)
In `top_ecg_rom_demo`, `sys_busy` has no driver and `sys_overflow` is unconnected
to APB → STATUS register always reads 0 for busy/overflow. Not a data bug
(packetizer takes overflow flags directly), but the STATUS APB port does not
reflect reality on the demo. Fix: `assign sys_busy = ~u_ctrl_fsm.fsm_idle` (expose it) or drop the claim.

### F-H — `regression_full.log` in repo was stale (process, not RTL)
See §1. Regenerate after every full run or delete; a committed log that
contradicts the status doc misleads the next handoff.

### F-I — `mlp_weights_rom.v` is a vestige
Reads `../AI_FSM_ECG-main/AI_FSM_ECG-main/weight.hex` (path not in repo), is
not instantiated by any top, and is still in `rtl.f` (compiles into the
lib, dead code). `ai_classifier` carries its own placeholder registers.
Flag: remove from `rtl.f` or delete, and note the weight-loading path is
the internal ROM-write case (partial: only addresses 24-25, 120-121, 128,
160 are wired — a full weight.hex load is NOT implemented even via that path).

### F-J — Zero-weight MLP proves pipeline only
As already stated, `class_code==00` everywhere is the placeholder-weights
result, not classification. With real weights, argmax/ReLU/saturation paths
are covered by `tb_ai_classifier_math` Tests 3-5 (including the ReLU-clamp
guard verified via F1 above).

### F-K — div=140000 (real 360 Hz) pipeline timing never simulated
Top TB overrides `SYS_SAMPLE_RATE_DIV=20`. The pacer_repre covers the demo's
360 Hz pacing, but the **product** adc_interface rate gate at div=140000 is
unverified. Correct units: 140000 cycles @50.4 MHz = 2.778 ms per sample
(= 360 Hz); a 512-sample window = 71.7e6 cycles; `LOAD_TIMEOUT = 100e6`
cycles = 1.984 s. The 1.984 s timeout must exceed worst-case window+feature
latency at the real rate (1.422 s fill + ~512-sample feature compute) — it
does, but that argument was never written out. Worth one timing check before
board.

## 5. Confirmed sound (no action)

- **ADC rate gate + latch**: `rate_tick` uses `>= div-1` (exactly div-period),
  single merged always block (Gowin EX2000 fix), overflow latches + reports
  on next tick. Demo div=1 path: every 1-cycle pacer pulse forwarded,
  `sample_count==2048` confirmed in demo sim.
- **Window 511/512/513 / wrap / overlap**: trigger condition
  `(total>=512 && (total-512)%256==0)` fires at totals 512, 768, ... only;
  oldest_addr logic handles not-full vs full buffer; combinational read keeps
  feature_extraction's sample/addr alignment (the v3.0 fix). Read-while-write
  collision relies on BRAM first-write-first-read + 10 µs read vs 2.78 ms
  sample period — an edge case only; SVA still recommended (§6).
- **control_fsm v3.1 blocking-next_state commit**: verified by reading —
  `next_state` is computed blocking within the same cycle and committed once
  via NBA; the prior 2-cycle lag bug is structurally gone. Marker TB is weak
  but E2E top + demo runs exercise it end-to-end (window → feature → mlp →
  done → irq → UART).
- **MLP datapath order, normalization, MAC, saturation, argmax tie-break**:
  covered by `tb_ai_classifier_math` with independent hand-computed values;
  F1 proves the ReLU guard is live.
- **Demo self-start**: ROM → pacer (single-pass, no loopback) → pipeline →
  APB sequencer (restart-per-result) → packetizer (latch-before-serialize,
  drop latch) → single uart_tx driver. 7 strict-match windows + reset/replay
  + no drops, confirmed in sim; checksum self-consistency checked in-TB.
- **UART 8N1**: bit-accurate decode on both product and demo paths; baud
  114 416 (−0.68%) at 50 MHz reported.

## 6. Verification gaps (pre-FPGA, ranked)

1. **Real trained weights** — no `weight.hex`; classification quality
   unverifiable. Blocker for "classifier" claims, not for pipeline demo.
2. **crest / zc / RR off-by-one** owner decisions (§4 F-C, F-E, F-A) —
   frozen-or-wrong values will silently propagate to a retrained model.
3. **div=140000 timing** (F-K) — one run or a timing argument.
4. **No SVA / corner coverage**: window no-double-fire while reading,
   write/read same-address collision, `soft_reset` mid-ACCUMULATE, double
   `start` during DONE, APB write during UART serialize.
5. **control FSM is marker-only** — add a done/irq/uart_send sequence check
   (currently proven only via E2E).
6. **Demo STATUS dead** (F-G) — decide whether STATUS must be live on board.
7. Synthesis: demo synth PASSed on GW5A-LV25 (netlist, resources, 0 latch,
   MLP not pruned — per MODULE_REPORT §15, consistent with what I read of
   the synth log claims); **P&R still blocked** on confirmed ACG525 part
   + `.cst` pin map. Do not call the design board-ready on synthesis numbers.

## 7. Bottom line

No functional blocker in the *pipeline* datapath: every data-correctness
fix found so far has a live, sensitive checker (F1/F2/F3 reproduced-then-
caught). Before FPGA build: (1) owner decisions on crest/zc/RR semantics,
(2) real weights if classification matters, (3) div=140000 timing check,
(4) close F-G/F-A/F-B doc-vs-artifact mismatches so the golden stays
honest. P&R remains blocked on hardware constraints as previously.
