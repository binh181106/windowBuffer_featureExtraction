# BOARD_DEMO_HANDOFF — ECG ROM demo, chuẩn bị chạy demo đầu tiên trên FPGA

> Báo cáo bàn giao để trợ lý khác review. Lần sửa: 2026-11-05 (bổ sung bằng
> chứng theo yêu cầu review; hiệu chỉnh phần synthesis + hướng dẫn GUI).
> Mục tiêu: demo `top_ecg_rom_demo` phát ECG từ ROM và gửi đúng 7 packet qua
> UART; MLP dùng weights bằng 0 nên `class=00` là kết quả dự kiến (chứng minh
> pipeline, KHÔNG phải chất lượng phân loại). Đánh giá model đã train là mốc
> riêng.

---

## 1. Bộ source đang dùng

### 1.1 Trạng thái git

```
$ git rev-parse --abbrev-ref HEAD
main
$ git rev-parse HEAD
3f16e3e93ea56f3a03601cb4772fc823ef6eafda
$ git log -1 --oneline
3f16e3e Merge pull request #1 from binh181106/feat/thinh/apb-uvm

$ git status --short
?? ecg-thinh-uvm/

$ git diff --stat
(rỗng)

$ git diff --cached --stat
(rỗng)
```

### 1.2 Source demo: untracked, và `git diff` BỎ SÓT — giải thích

- `git status --short` chỉ hiện **một** dòng `?? ecg-thinh-uvm/` → **toàn bộ
  thư mục là UNTRACKED**, không phải "được giải nén vào main đang tracked".
- Lý do: `.gitignore` của branch `newest-update` (dòng cuối: `logs/`,
  `simlib/`) **không** loại `ecg-thinh-uvm/`, nhưng trên `main` hiện tại
  **không có file `.gitignore` nào ở root** (kiểm tra: `cat .gitignore` →
  "No such file or directory"). Vì vậy `git status` coi cả thư mục là
  untracked và **gộp thành một mục duy nhất** — git không liệt kê file con.
- **Hệ quả thực tế (quan trọng cho review)**: `git diff --stat` và
  `git diff --cached --stat` đều **RỖNG** → **`git diff` thông thường KHÔNG
  thấy bất kỳ thay đổi nào của bộ source demo**, kể cả file sửa và file mới.
  Đây là lý do báo cáo này **không** dùng `git diff` làm bằng chứng, mà
  xuất diff tường minh so với `newest-update@bf0f983` (§1.4).
- Không có gì staged, không có commit mới, không push (`git log -1` vẫn là
  `3f16e3e`). Việc này là **cố ý** theo yêu cầu "không reset/stash/checkout
  đè/commit/push".

### 1.3 Nguồn gốc của source

- Demo **không nằm trong working tree ban đầu**. Nó nằm ở branch
  `newest-update` @ `bf0f983` (còn `32e6f25` là commit cha tạo demo).
- Đã lấy về bằng `git archive newest-update ecg-thinh-uvm | tar -x` (không
  checkout, không sửa lịch sử git). File log/simlib local **giữ nguyên**.
- `ecg-board-demo.patch`: **không tồn tại** trong workspace (đã tìm toàn bộ
  `H:\IC Design` và repo) → không có bản tham khảo nào để đối chiếu.

### 1.4 Diff so với `newest-update@bf0f983` (nguồn chuẩn)

Các file dưới đây là **toàn bộ** phần thay đổi của lượt này:

```
 demo/top_ecg_rom_demo.v      |  19 ++++++++--   4 ----
 demo/uart_decode.py          | 224 ++++++++++++--  23 ----
 tb/tb_demo_rom.sv            |  53 ++++++++++++++   0 ----
 scripts/run_regression.sh    |  58 ++++++++++++++-   1 ----
 tb/tb_demo_status.sv         | 335 +++++++++++++++++ (file MỚI)
 docs/BOARD_DEMO_HANDOFF.md   | 503 +++++++++++++++++ (file MỚI)
```

Lệnh tái tạo diff (không cần commit):
```bash
git archive newest-update ecg-thinh-uvm | tar -x -C /tmp/base_uvm
diff -ru --strip-trailing-cr /tmp/base_uvm/ecg-thinh-uvm ecg-thinh-uvm \
     --exclude=simlib --exclude=logs --exclude=__pycache__ --exclude=work
```

**File MỚI — toàn bộ nội dung được gửi kèm báo cáo này:**
- `tb/tb_demo_status.sv` (335 dòng — bản đầy đủ ở Phụ lục A).
- `docs/BOARD_DEMO_HANDOFF.md` (file này).

Nội dung đầy đủ của `tb/tb_demo_status.sv` và `demo/uart_decode.py` được dán
trực tiếp trong bản báo cáo kèm theo (Phụ lục A và B).

### 1.5 Trạng thái product top — KHÔNG đổi

`top/top_ecg_classifier.v`, `feature/feature_extraction.v`,
`ai/ai_classifier.v`, `demo/demo_uart_packetizer.v`, `demo/demo_apb_seq.v`,
`demo/golden/*` **không bị sửa**. Giao thức UART, weights, thuật toán feature
giữ nguyên. Không có thay đổi port nào.

---

## 2. Bằng chứng kiểm thử

### 2.1 19/19 regression (chạy 2026-11-05, `bash scripts/run_regression.sh`, exit 0)

| # | Test | Verdict | Log |
|---|---|---|---|
| 1 | adc | PASS (5/5) | `logs/adc.log` |
| 2 | window | PASS (5/5) | `logs/window.log` |
| 3 | feature | PASS (8/8) | `logs/feature.log` |
| 4 | ai | PASS (6/6) | `logs/ai.log` |
| 5 | ai_math | PASS (5/5) | `logs/ai_math.log` |
| 6 | apb | PASS (7/7) | `logs/apb.log` |
| 7 | uart | PASS (2/2) | `logs/uart.log` |
| 8 | control | PASS (markers) | `logs/control.log` |
| 9 | control_tmo | PASS (4/4) | `logs/control_tmo.log` |
| 10 | rr_probe | PASS (3/3) | `logs/rr_probe.log` |
| 11 | smoke_f | PASS (smoke) | `logs/smoke_f.log` |
| 12 | smoke_w | PASS (smoke) | `logs/smoke_w.log` |
| 13 | top | PASS (8/8) | `logs/top.log` |
| 14 | uvm | PASS (smoke env) | `logs/uvm.log` |
| 15 | demo_python | PASS | `logs/demo_python.log` |
| 16 | demo_capture | PASS | `logs/demo_rom.log` |
| 17 | demo_rom | PASS (2/2) | `logs/demo_rom.log` |
| 18 | demo_status | PASS (8/8) | `logs/demo_status.log` |
| 19 | pacer_repre | PASS (5/5) | `logs/pacer_repre.log` |

`Passed: 19 / 19`, `Exit code: 0`. Log đầy đủ: `logs/regression_full.log`.

### 2.2 Tóm tắt 4 mục trọng tâm

**`demo_status` (TB mới) — `logs/demo_status.log`**
```
# PASS T2 busy: STATUS=0x00000001, fsm_state=1
# PASS T3 overflow readback: forced=0x00000009 released=0x00000001
# PASS T5 adc source -> STATUS bit3=1 (STATUS=0x00000009)
# PASS T6 feature source -> STATUS bit3=1 (STATUS=0x00000009)
# PASS T7 mlp source -> STATUS bit3=1 (STATUS=0x00000009)
# PASS T1 idle: STATUS=0x00000000 fsm_state=0
# PASS T4 undisturbed: winR=7 adc=2048 eod=1 drop=0 demo_overflow=0 demo_done=1
# PASS T8 pkt_drop does NOT set STATUS bit3 (STATUS=0x00000000, demo_overflow=1 during force)
# Test Summary: 8/8 PASSED
```

**`demo_rom` FAST — `logs/demo_rom.log`**
```
# Demo ROM TB  TARGET_HZ=33333 gap=1500 ROM=2048 golden=7
# Run1: ncur=7 valid=7 winR=7 drop=0 eod=1 adc=2048
# Run1: dbg_bytes=231 dbg_e7=7
# PASS Run1: 7 valid packets match golden, single-pass
# [tb_demo_rom] capture closed: 231 bytes
# PASS Run2: reset+replay, 15 golden packets, no drop
# Demo ROM TB  Test Summary: 2/2 PASSED
```

**`demo_rom` REPRE (cadence board) — `logs/demo_rom_repre.log`**

Lệnh **đầy đủ** đã dùng:
```bash
cd "H:/IC Design/Code/ECG/ecg-thinh-uvm/simlib"
timeout 1500 /h/questasim64_10.7c/win64/vsim.exe -c -work work_demo tb_demo_rom \
    -gTARGET_HZ=360 -do "run -all; quit -f" \
    +SKIP_RUN2 +CAPTURE=../simlib/capture_repre.bin \
    > ../logs/demo_rom_repre.log 2>&1
```
- **Override tham số**: `-gTARGET_HZ=360` (override **elaboration parameter** của
  `tb_demo_rom`; nó truyền xuống `top_ecg_rom_demo.TARGET_HZ` → `sample_pacer`).
  `+SKIP_RUN2` bỏ lượt reset+replay (lượt 360 Hz rất chậm, 1 lượt đã đủ).
- **Timeout**: `timeout 1500` (giây) — lượt thực tế **hoàn tất, rc=0, không
  bị timeout**. TB báo `gap=138888` (≈ 50 MHz/360 Hz).
- Kết quả:
```
# Demo ROM TB  TARGET_HZ=360 gap=138888 ROM=2048 golden=7
# Run1: ncur=7 valid=7 winR=7 drop=0 eod=1 adc=2048
# Run1: dbg_bytes=231 dbg_e7=7
# PASS Run1: 7 valid packets match golden, single-pass
# [tb_demo_rom] capture closed: 231 bytes
# Demo ROM TB  Test Summary: 1/1 PASSED
```
- Capture REPRE **byte-identical** với capture FAST (`cmp` → IDENTICAL):
  cadence chỉ đổi thời gian, không đổi dữ liệu.

**Capture checker — `logs/demo_rom.log`**
```
== capture check: ...\simlib\capture_run1.bin (231 bytes) ==
     size 231 bytes = 7 x 33  OK
     packet frames 7  OK
     pkt#0 @0: framing + checksum 0xDF  OK
     pkt#1 @33: framing + checksum 0xB9  OK
     pkt#2 @66: framing + checksum 0x31  OK
     pkt#3 @99: framing + checksum 0x82  OK
     pkt#4 @132: framing + checksum 0x9F  OK
     pkt#5 @165: framing + checksum 0x54  OK
     pkt#6 @198: framing + checksum 0x3D  OK
     window indices [1, 2, 3, 4, 5, 6, 7] in order  OK
     pkt#1 @33 MASKED difference (reported, not fatal): byte[16](f_crest[7:0]) expected 0xB7 actual 0xDB, byte[17](f_crest[15:8]) expected 0xFD actual 0x06, byte[32](checksum) expected 0x8C actual 0xB9
     ... (w4, w5 tương tự)
CHECK RESULT: PASS
```
Lệnh chấm độc lập: `python -I demo/uart_decode.py --check simlib/capture_run1.bin`
→ `CHECK RESULT: PASS`, **exit 0**. Với capture checksum hỏng → `CHECK RESULT:
FAIL`, **exit 1** (đã kiểm).

### 2.3 Test `force sys_overflow` — giới hạn đã làm rõ, và đã BỔ SUNG

**Giới hạn của T3 (bản cũ)**: T3 force trực tiếp net `sys_overflow` ở top-level.
Nó **chỉ** chứng minh:
1. bit3 của thanh ghi STATUS phản ánh net `sys_overflow` (đường readback),
2. và bit3 trở lại 0 khi thả force.

Nó **KHÔNG** chứng minh:
- OR ở top nối đúng **nguồn** nào (nếu `sys_overflow` bị nối sai nguồn, T3 vẫn PASS);
- logic overflow của adc/feature/mlp có thực sự assert trên dữ liệu thật hay không.

**Đã bổ sung (lần này) — T5/T6/T7 kích từng nguồn riêng:**
mỗi nguồn được force trên **net riêng của nó**, các nguồn còn lại force = 0,
và bit3 STATUS phải bám đúng nguồn vừa kích:

| Test | Nguồn kích (net) | Kỳ vọng | Kết quả |
|---|---|---|---|
| T5 | `adc_overflow`=1, feature=0, mlp=0 | bit3=1 | PASS (STATUS=0x9) |
| T6 | `feature_overflow`=1, adc=0, mlp=0 | bit3=1 | PASS (STATUS=0x9) |
| T7 | `mlp_overflow`=1, adc=0, feature=0 | bit3=1 | PASS (STATUS=0x9) |

**Chứng minh các test này thật sự bắt lỗi (fault injection, trên bản sao
scratch, working tree không bị đụng):**
bỏ `feature_overflow` khỏi OR trong `top_ecg_rom_demo.v`
(`assign sys_overflow = adc_overflow | mlp_overflow;`) rồi chạy lại:
```
# PASS T5 adc source -> STATUS bit3=1 (STATUS=0x00000009)
# FAIL T6 feature source: followed=000...0 STATUS=0x00000001
# PASS T7 mlp source -> STATUS bit3=1 (STATUS=0x00000009)
# Test Summary: 7/8 FAILED
```
→ T6 bắt đúng lỗi nối OR. Log: `logs/fi_status_fault.log`. Bản sao scratch đã
xoá sau khi chạy.

**T8 — tách ý nghĩa packet-drop**: force `dut.u_pz.pkt_drop`=1 → `demo_overflow`
= 1 (chứng minh force có hiệu lực, không vacuous) nhưng **STATUS bit3 vẫn = 0**
→ pkt-drop KHÔNG lẫn vào STATUS overflow. Kỳ vọng này là **ý nghĩa được chốt**
(packet-drop = mất transport ≠ tràn số); xem §3.1.

**Giới hạn còn lại (ghi rõ, không tuyên bố quá):** T5–T8 dùng `force` trên net
→ chúng là **bằng chứng về ĐƯỜNG NỐI + readback**, KHÔNG phải bằng chứng rằng
logic overflow adc/feature/mlp tự assert trên dữ liệu thật. Phần đó do
`tb_adc_interface` (overflow latch + assert) và cờ trong packet demo phủ.

### 2.4 Code mới

- `demo/uart_decode.py` (290 dòng) — xem **Phụ lục B**.
- `tb/tb_demo_status.sv` (335 dòng) — xem **Phụ lục A**.

---

## 3. Hiệu chỉnh phần synthesis (theo review)

### 3.1 Trạng thái thật của bằng chứng synthesis

**Cảnh báo quan trọng**: lần sửa này **KHÔNG chạy Gowin** (theo yêu cầu).
Vì vậy **mọi khẳng định về warning sau khi sửa là CHƯA KIỂM** — log
synthesis trong repo là bản **CŨ** (2026-10-31 23:53:58, trước khi sửa B1/B3).

### 3.2 Bảng warning (trích từ log synth CŨ `synthesis/demo_out/top_ecg_rom_demo.log`)

| Warning | Vị trí | Nội dung | Đã xác nhận gì | CHỜ build |
|---|---|---|---|---|
| `EX3670` | `demo/top_ecg_rom_demo.v:250` | Actual bit length 32 ≠ formal 8 cho port `paddr` (APB slave) | — | Đã **sửa** (truncate tường minh `apb_paddr[7:0]`) |
| `EX3670` | `demo/top_ecg_rom_demo.v:276` | Như trên, port `paddr` của `demo_apb_seq` | — | Đã **sửa** |
| `EX1998` | `demo/top_ecg_rom_demo.v:105` | Net `sys_busy` không có driver | — | Đã **sửa** (`assign sys_busy = ~fsm_idle`) |
| `EX2565` | `demo/top_ecg_rom_demo.v:270` | Input `sys_overflow` không được driver, gán 0 → **mô phỏng lệch** | — | Đã **sửa** (`assign sys_overflow = adc\|feature\|mlp`) |
| `EX1998` | `ai/ai_classifier.v:77,80,83,86` | `fc1_weights[2][15]`, `fc1_biases[2][15]`, `fc2_weights[1][15]`, `fc2_biases[1][15]` không có driver | Đây là **hệ quả của weights placeholder = 0** trong `ai_classifier` (không phải nối sai trong demo) | **KHÔNG khẳng định "sẽ tự hết"** — phải xác nhận khi nạp weights thật; có thể vẫn còn nếu cấu trúc placeholder không đổi |
| `EX1998` | `ai/ai_classifier.v:119,120,121` | `rom_addr[7]`, `rom_wdata[15]`, `rom_we` không có driver | Đường nạp weights **nội bộ** của `ai_classifier`, chưa nối đầy đủ (chỉ vài địa chỉ) | Cần xác nhận khi implement đường nạp weight.hex |
| `EX3858` | `demo/ecg_rom.v:40`, `control/control_fsm.v:242` | System task `display` bị bỏ qua khi synthesis | Vô hại, có chủ đích | Xác nhận ở lần build tới |
| `EX3791` | `window/window_buffer.v:55` | Expression size 32 → 8 | Có chủ đích (truncate về 8 bit) | Xác nhận ở lần build tới |
| `EX3791` | `feature/feature_extraction.v:254` | Expression size 10 → 9 | Có chủ đích (địa chỉ 9 bit) | Xác nhận ở lần build tới |
| `CV0016` | `demo/top_ecg_rom_demo.v:49` | Input `uart_rxd` unused | Có chủ đích (demo không dùng RX) | Xác nhận ở lần build tới |

**Tóm tắt**: 4 warning thuộc phần demo đã được sửa (2 paddr, 1 sys_busy,
1 sys_overflow) — nhưng **chưa có log synthesis mới để chứng minh chúng đã
hết**. 7 warning còn lại thuộc `ai/ai_classifier.v` và các module sản phẩm:
**không sửa, không khẳng định sẽ tự biến mất**.

### 3.3 Tài nguyên — trích nguyên văn từ report gốc

Nguồn: `synthesis/demo_out/top_ecg_rom_demo_syn.rpt.html` (bản CŨ,
Tool V1.9.9 64-bit, Part `GW5A-LV25UG324C2/I1`, Device `GW5A-25`, Device
Version A, Created `Sat Oct 31 23:53:58 2026`).

**Bảng "Resource | Usage"** (đơn vị: **số primitive**):
```
I/O Port | 12      I/O Buf | 11   (IBUF 2, OBUF 9)
Register | 974     (DFFRE 25, DFFPE 13, DFFCE 936)
LUT      | 2479    (LUT2 224, LUT3 813, LUT4 1442)
ALU      | 573
SSRAM    | 64      (RAM16SDP4 64)
INV      | 9
DSP      | MULT12X12 1, MULT27X36 2
BSRAM    | 1       (pROM 1)
```

**Bảng "Resource | Usage | Utilization"** (đơn vị: số dùng / tổng của device,
phần trăm):
```
Logic    | 3445 (2488 LUT, 573 ALU, 64 RAM16) / 23040 | 15%
Register | 974 / 23685 | 5%
  --Register as Latch | 0 / 23685 | 0%
  --Register as FF    | 974 / 23685 | 5%
BSRAM    | 1 / 56 | 2%
```

**Phân biệt ba thứ review yêu cầu (rất dễ nhầm):**
| Khái niệm | Số | Bằng chứng |
|---|---|---|
| **Dữ liệu ROM** | **2048 mẫu × 8 bit = 16 384 bit** | `demo/ecg_rom.v:31` `reg [ROM_DW-1:0] rom [0:ROM_WORDS-1]`, `ROM_WORDS=2048`, `ROM_DW=8` |
| **Số block BSRAM** | **1** (loại `pROM`) | `BSRAM | 1`, `pROM | 1`; `_syn_rsc.xml`: `<SubModule name="u_rom" Bsram="1"/>` |
| **Số primitive SSRAM** | **64** (loại `RAM16SDP4`) | `SSRAM | 64`, `RAM16SDP4 | 64`; `_syn_rsc.xml`: `<SubModule name="u_window" ... Ssram="64"/>` |

→ **64 RAM16SDP4 thuộc về `u_window` (window_buffer), KHÔNG phải ROM.** ROM
chỉ dùng **1** primitive `pROM` (đúng 2048×8 bit đóng gói trong 1 block pROM
256 bit × 64 từ INIT_RAM). Con số "64" trong báo cáo cũ trước đây là
**số primitive SSRAM của window buffer**, không phải số block ROM.

### 3.4 INIT_RAM — KHÔNG khớp `ecg_rom.hex` hiện tại (đã kiểm, không đoán)

Đã đối chiếu thực tế: netlist có **64** `defparam INIT_RAM_00..3F` (mỗi
dòng 256 bit = 32 byte) và `demo/ecg_rom.hex` có đúng **2048** mẫu. Đã thử
**cả hai** quy ước đóng gói byte (little-endian và big-endian trong 256-bit):

```
LE (byte0 = địa chỉ thấp nhất): KHÔNG khớp (lệch tại block 00)
  netlist[:8] 0xb7 0x33 0x29 0xb7 0x3e 0x34 0xb7 0x46
  hex[:8]     0x20 0x20 0x21 0x23 0x23 0x21 0x20 0x20
BE (byte0 = địa chỉ cao nhất): KHÔNG khớp (lệch tại block 00)
  netlist[:8] 0x51 0xb7 0x3d 0x4e 0xb7 0x46 0x4c 0xb7
  hex[:8]     0x20 0x20 0x21 0x23 0x23 0x21 0x20 0x20
```

**Kết luận đúng**: netlist trong repo **KHÔNG được sinh từ `ecg_rom.hex`
hiện tại**. Điều này giải thích được: `ecg_rom.hex` hiện tại đã được **sinh
lại** sau khi sửa bộ giải mã WFDB 212 (AUTOMATION_STATUS §11.2, 2026-11-02),
còn netlist có `Created Time Sat Oct 31 23:53:58 2026` — **trước** đó. (File
`demo/ecg_rom.hex` và netlist có cùng mtime 2026-11-02 07:30 vì mtime đó là
thời điểm `git archive` giải nén, **không** phải thời điểm chạy synthesis.)

Vì không chứng minh được thứ tự đóng gói (Gowin có thể sắp xếp lại byte,
hoặc netlist đã cũ), báo cáo này **bỏ kết luận "INIT_RAM khớp hex"**.

**Bước phải kiểm ở lần synthesis tiếp theo:**
1. Chạy lại synthesis (sau khi có part/pin xác nhận).
2. Trong netlist mới, lấy `INIT_RAM_00` và **đối chiếu với `ecg_rom.hex`**
   bằng script độc lập — cả 2 quy ước endian, và tìm quy ước khớp (ví dụ
   thứ tự 8-bit trong 256-bit word theo nhóm 32, hoặc bit-lane packing).
   Script dùng để kiểm nằm ở Phụ lục C.
3. **Cách kiểm thay thế, mạnh hơn và không phụ thuộc đóng gói**: chạy
   `tb_demo_rom` với **đúng** file hex mà synthesis dùng (`ROM_HEX`), và
   xác nhận capture 231 byte khớp golden. Đây mới là bằng chứng end-to-end
   rằng ROM trên board chứa đúng dữ liệu — đã chạy PASS cho file hex hiện
   tại.
4. Kiểm `INIT_RAM` đủ 64 từ (2048 byte) — không thiếu từ nào.

### 3.5 Timing trong report CŨ — cảnh báo

Report gốc ghi:
```
Timing Clock Summary: sys_clk | Base | Period 10.000 | Frequency 100.0 MHz
Max Frequency Summary: sys_clk | Constraint 100.0 MHz | Actual Fmax 35.4 MHz | Logic Level 50
Detail Timing Paths: Slack -18.254  (u_feature/rr_current_3_s0 -> u_feature/f_rr_ratio_0_s0)
```
và `GowinSynthesis Constraints File: ---` (rỗng).

→ Bản synthesis này **chạy KHÔNG có SDC** (constraint 100 MHz là mặc định
của tool), **không** phải 20 ns/50 MHz như `synthesis/demo_ecg_rom_demo.sdc`
định nghĩa. `Fmax thực = 35.4 MHz` **và slack âm (-18.254 ns)** chỉ là kết quả
với constraint sai đó, nên **không** kết luận được rằng thiết kế không đạt
50 MHz. Cần chạy lại synthesis **có** SDC để có con số đúng.

### 3.6 Ba trạng thái (chỉ đánh dấu PASS khi có kết quả thực tế)

| Trạng thái | Trạng thái thật | Bằng chứng |
|---|---|---|
| **Code / mô phỏng** | **PASS** — 7 packet / 231 byte / index 1–7 / checksum / so golden strict; reset+replay; STATUS idle/busy/overflow (8/8, có fault-injection chứng minh test nhạy); cadence board 360 Hz; regression 19/19 exit 0 | §2 |
| **Sẵn sàng để build (Gowin)** | **CHƯA XÁC NHẬN** — có script + SDC + một lần synthesis cũ (netlist + report, **không có SDC**, constraint sai 100 MHz, slack âm). Sau khi sửa B1/B3 **chưa chạy lại Gowin** → không có log synthesis mới, không có P&R, không có CST, không có bitstream | `synthesis/demo_out/*` (CŨ, 2026-10-31) |
| **Đã chạy trên board** | **CHƯA CHẠY** — chưa nạp bitstream, chưa thu UART thật | — |

---

## 4. Hướng dẫn GUI (Gowin) — thứ tự đã sửa theo review

### Bước 0 (CHỜ THÔNG TIN — làm TRƯỚC mọi bước khác)

**Xác nhận board / device / pin.** Không mở project, không tạo project, không
chạy P&R cho tới khi có:
1. Tên board thật + **schematic hoặc tài liệu pin** (chân clock 50 MHz, reset,
   UART TX/RX, LED, mức I/O LVCMOS33/18, reset polarity, LED active level).
2. **Chip/package Gowin thực tế** trên board → đối chiếu với device DB đã cài
   (`H:/Gowin/Gowin_V1.9.9_x64/IDE/data/device/device_info.csv`, ví dụ dòng
   `GW5A-LV25...`), để chọn đúng Family/Device/Package/Speed.

*Phương án nhỏ hơn*: nếu chỉ có tên chip (không có schematic), tôi vẫn có thể
chọn Device/Package đúng trong GUI và chạy synthesis + P&R **không có
constraint pin** — nhưng P&R sẽ không cho kết quả pin hợp lệ và chưa nạp
được. Cần schematic cho `.cst`.

### Bước 1–5 (làm được ngay sau khi có thông tin Bước 0)

1. **Create Project**: top = `top_ecg_rom_demo`, Device/Package theo Bước 0.
2. **Thêm source** (Chipscope off):
   `demo/ecg_rom.v demo/sample_pacer.v demo/demo_apb_seq.v
   demo/demo_uart_packetizer.v demo/top_ecg_rom_demo.v adc/adc_interface.v
   window/window_buffer.v feature/feature_extraction.v ai/ai_classifier.v
   control/control_fsm.v apb/apb_slave_if.v uart/uart_tx.v`
   — **không** thêm `ai/mlp_weights_rom.v` (demo không instantiate nó; weights
   = placeholder 0 trong `ai_classifier`).
3. **Constraints**: SDC = `synthesis/demo_ecg_rom_demo.sdc` (20 ns / 50 MHz —
   lần synthesis CŨ **đã không dùng** file này, xem §3.5) + file `.cst` pin
   do tôi soạn khi có schematic. Chỉ gán pin demo:
   `sys_clk`, `sys_rst_n`, `uart_txd`, `uart_rxd`, `status_led[3:0]`,
   `demo_done`, `demo_overflow`, `demo_class[1:0]` — **không** đưa APB/ADC ra pin.
4. **Synthesis → P&R → xem timing report**: mục tiêu chu kỳ 20 ns, **slack ≥ 0**
   (bản CŨ có slack âm nhưng vì constraint sai — xem §3.5). So tài nguyên với
   §3.3 (kỳ vọng: 1 pROM, 64 RAM16SDP4 cho window, ~2479 LUT, ~974 FF,
   3 MULT). **Kiểm tra ROM init** theo §3.4 bước 1–4.
5. **Generate bitstream → Program → thu UART** 115200 8N1 (baud thật 114 416,
   −0.68%, trong dung sai), lưu **binary** `capture.bin`, rồi:
   `python -I demo/uart_decode.py --check capture.bin`
   Kỳ vọng: 231 byte, 7 packet, index 1–7, `CHECK RESULT: PASS` (exit 0).
   Byte `f_crest` (16–17) có thể lệch golden — đó là điểm đã mask, xem §5.

---

## 5. Điểm phản biện / quyết định cuối

1. **`sys_overflow` = numeric overflow, KHÔNG gồm packet-drop.** Đây là
   **ý nghĩa được chốt** (khớp product top `top_ecg_classifier.v:331`) và
   giờ đã có test T8 bảo vệ. Nếu team muốn packet-drop cũng báo trên STATUS,
   đó là **thay đổi interface → cần cập nhật `docs/interfaces.md` + owner
   duyệt**, không sửa lặng lẽ.
2. **Demo FSM không tự về IDLE khi ROM cạn**: `demo_apb_seq` re-start FSM sau
   mỗi result nên FSM đứng ở S_LOAD chờ cửa sổ không bao giờ đến. Đây là
   **hành vi hợp lệ** (LOAD_TIMEOUT = 100e6 chu kỳ ≈ 2 s @50 MHz ≫ thời gian
   dòng ROM), không phải bug — nhưng nghĩa là trạng thái "busy" là trạng thái
   thật của demo; TB T1 vì vậy soft-reset qua APB để quan sát IDLE thật. Nếu
   muốn FSM về IDLE khi hết ROM thì đó là **feature mới**, không tự thêm.
3. **`f_crest` (byte 16–17) vẫn sai theo spec** (truncation 16 bit; xem
   VERIFICATION_REVIEW F-C). Hiện **mask + report**, chưa sửa — vì sửa là thay
   đổi thuật toán feature (vi phạm AGENTS.md §4.2 và yêu cầu "giữ nguyên
   thuật toán feature").
4. **`f_zc ≡ 0`** trong pipeline do baseline clamp của window_buffer (samples
   0..86, bit7 không set) — đã biết, không sửa.
5. **RR off-by-one (11 vs 12)** — golden đang **mirror** RTL, tức là check
   kiểu mirror chứ không độc lập (VERIFICATION_REVIEW F-A). Để lại owner.

---

## 6. Điều user cần cung cấp tiếp (đúng thứ duy nhất còn thiếu)

**Schematic hoặc tài liệu pin của board** — gồm: tên board, chip/package
Gowin thực tế, chân clock 50 MHz, chân reset, chân UART TX/RX, chân LED,
mức I/O (LVCMOS33/18), reset polarity. Không có tài liệu này thì **không tạo
`.cst`, không chạy P&R**.

Khi có: tôi ghi `.cst` cho đúng pin demo, và bước kiểm ROM init (§3.4) trở
thành bước xác nhận trong lần build của bạn.

---

## 7. Để lại cho mốc tích hợp model thật (KHÔNG thuộc demo này)

- `weight.hex` (164 từ Q4.12) + **đường nạp đầy đủ**: `ai_classifier` hiện
  dùng registers placeholder 0; đường ROM-write nội bộ chỉ nối một phần địa
  chỉ (24-25, 120-121, 128, 160) → phải implement full load trước khi đánh
  giá phân loại. `mlp_weights_rom.v` là vestige (đọc hex ngoài repo, không
  instantiate) — có thể gỡ khỏi `scripts/rtl.f`.
- Quyết định `f_crest` truncation (byte 16–17), `f_zc≡0`, RR off-by-one.
- **Timing `div=140000` của product top** chưa sim (F-K): demo dùng pacer nên
  **không** phủ được rate-gate 140000 của `adc_interface` bản product.
- Chạy lại synthesis **có SDC** để có con số Fmax/slack đúng cho 50 MHz
  (bản CŨ không có SDC — §3.5).

---

## Phụ lục A — `tb/tb_demo_status.sv` (file MỚI, toàn bộ nội dung)

```systemverilog
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
```

## Phụ lục B — `demo/uart_decode.py` (file sửa, toàn bộ nội dung)

```python
#!/usr/bin/env python3
"""Offline decoder + capture checker for the demo UART result packets.

The parser is testable WITHOUT a board: it operates on a raw byte stream
(a .bin capture, the demo testbench's dumped bytes, or a live serial port if
pyserial is available — optional, not required).

Protocol (see demo/demo_uart_packetizer.v):
    33 bytes, 16-bit fields little-endian, features two's complement:
      [0]=0xE7 [1]=0xA5 [2]=type 0x01 [3]=len 28
      [4..5]=win_index [6..29]=f0..f11 (12 x 16-bit)
      [30]=class_code(2b) [31]=flags(bit0 adc,bit1 feat,bit2 mlp overflow)
      [32]=checksum = sum(bytes[2..31]) mod 256

The checksum scope is bytes 2..31 INCLUSIVE, i.e. every byte actually
received in that range — including bytes the golden marks as "masked"
(open / tool-dependent, e.g. f_crest). The checksum is therefore verified
against the REAL received bytes, never against golden values.

Usage:
    python -I demo/uart_decode.py                  -> self-test
    python -I demo/uart_decode.py capture.bin      -> decode & print packets
    python -I demo/uart_decode.py --check capture.bin
        -> full acceptance check against demo/golden/expected_packets.json.
           Exit code 0 = capture meets the acceptance criteria, 1 = it does
           not, 2 = usage / IO error.

Acceptance criteria for --check (a clean demo capture):
    * exactly 231 bytes total (7 packets x 33 bytes)
    * exactly 7 packets, each 33 bytes, correct framing
      (sync 0xE7 0xA5, type 0x01, len 28)
    * window indices 1..7, in order
    * every packet's checksum verifies against its own received bytes
    * every STRICT byte equals the golden byte (byte position, expected and
      actual are reported on mismatch)
    * MASKED bytes (golden strict_mask == 0: f_crest and the checksum) are
      REPORTED when they differ, but do NOT fail the check: those bytes are
      open / tool-dependent by owner decision (see docs/AUTOMATION_STATUS.md
      §3.3, §9.4). The golden and the mask are never loosened here.
"""
import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent

SYNC1, SYNC2, PKTLEN = 0xE7, 0xA5, 33
N_PACKETS = 7
CAPTURE_BYTES = N_PACKETS * PKTLEN          # 231


def checksum_of(body: bytes) -> int:
    """checksum = sum(bytes[2..31]) mod 256 — the bytes actually received."""
    return sum(body[2:32]) & 0xFF


def decode_stream(data: bytes):
    """Yield (offset, packet_dict) for every valid packet found in `data`.

    Resyncs on E7 A5 after any garbage; a packet is accepted only when its
    checksum verifies. Never raises on malformed input.
    """
    i, n = 0, len(data)
    while i + PKTLEN <= n:
        if data[i] == SYNC1 and data[i + 1] == SYNC2:
            body = data[i:i + PKTLEN]
            chk = checksum_of(body)
            if chk == body[32] and body[2] == 0x01 and body[3] == 28:
                feats = []
                for k in range(12):
                    lo, hi = body[6 + 2 * k], body[7 + 2 * k]
                    v = hi * 256 + lo
                    feats.append(v - 65536 if v & 0x8000 else v)
                yield i, {
                    "win_index": body[4] | (body[5] << 8),
                    "features": feats,
                    "class": body[30] & 0x3,
                    "flags": body[31] & 0x7,
                    "checksum": body[32],
                }
                i += PKTLEN
            else:
                i += 2
        else:
            i += 1


def find_packets(data: bytes):
    """Return the list of (offset, raw 33-byte body) for every frame found.

    Unlike decode_stream() this does NOT require a valid checksum, so a
    corrupt packet is still REPORTED (as a bad frame) instead of silently
    vanishing from the packet count.
    """
    out = []
    i, n = 0, len(data)
    while i + PKTLEN <= n:
        if data[i] == SYNC1 and data[i + 1] == SYNC2:
            out.append((i, data[i:i + PKTLEN]))
            i += PKTLEN
        else:
            i += 1
    return out


def check_capture(data: bytes, golden: dict):
    """Full acceptance check of a capture against the golden.

    Returns (ok: bool, lines: list[str]). `lines` is the report to print.
    """
    lines = []
    ok = True

    def fail(msg):
        nonlocal ok
        ok = False
        lines.append(f"FAIL {msg}")

    def info(msg):
        lines.append(f"     {msg}")

    wins = golden["windows"]
    exp_packets = [bytes(w["packet"]) for w in wins]
    exp_masks = [w["strict_mask"] for w in wins]

    # ---- 1. total size -----------------------------------------------------
    if len(data) != CAPTURE_BYTES:
        fail(f"capture size {len(data)} bytes, expected exactly "
             f"{CAPTURE_BYTES} ({N_PACKETS} packets x {PKTLEN})")
    else:
        info(f"size {len(data)} bytes = {N_PACKETS} x {PKTLEN}  OK")

    # ---- 2. packet count ----------------------------------------------------
    frames = find_packets(data)
    if len(frames) != N_PACKETS:
        fail(f"found {len(frames)} packet frames, expected {N_PACKETS}")
    else:
        info(f"packet frames {len(frames)}  OK")

    # ---- 3. per-packet framing + checksum ----------------------------------
    for idx, (off, body) in enumerate(frames):
        tag = f"pkt#{idx} @{off}"
        if len(body) != PKTLEN:
            fail(f"{tag}: length {len(body)} != {PKTLEN}")
            continue
        if body[0] != SYNC1 or body[1] != SYNC2:
            fail(f"{tag}: bad sync {body[0]:02X} {body[1]:02X} "
                 f"(expected {SYNC1:02X} {SYNC2:02X})")
        if body[2] != 0x01:
            fail(f"{tag}: bad type 0x{body[2]:02X} (expected 0x01)")
        if body[3] != 28:
            fail(f"{tag}: bad len {body[3]} (expected 28)")
        chk = checksum_of(body)
        if chk != body[32]:
            fail(f"{tag}: checksum 0x{body[32]:02X} != computed 0x{chk:02X} "
                 f"(sum of received bytes 2..31)")
        else:
            info(f"{tag}: framing + checksum 0x{chk:02X}  OK")

    # ---- 4. window index order ---------------------------------------------
    got_idx = [body[4] | (body[5] << 8) for _, body in frames]
    want_idx = [w["win_index"] for w in wins]
    if got_idx != want_idx:
        fail(f"window index order {got_idx}, expected {want_idx}")
    else:
        info(f"window indices {got_idx} in order  OK")

    # ---- 5. strict byte comparison + masked differences --------------------
    for idx, (off, body) in enumerate(frames):
        if idx >= len(wins):
            fail(f"pkt#{idx}: more packets than golden windows")
            break
        mask = exp_masks[idx]
        strict_bad, open_bad = [], []
        for k in range(PKTLEN):
            if body[k] != exp_packets[idx][k]:
                if mask[k]:
                    strict_bad.append(k)
                else:
                    open_bad.append(k)
        if strict_bad:
            for k in strict_bad:
                fail(f"pkt#{idx} @{off} byte[{k}] strict mismatch: "
                     f"expected 0x{exp_packets[idx][k]:02X}, "
                     f"actual 0x{body[k]:02X}")
        if open_bad:
            names = {16: "f_crest[7:0]", 17: "f_crest[15:8]", 32: "checksum"}
            desc = ", ".join(
                f"byte[{k}]({names.get(k, 'masked')}) expected "
                f"0x{exp_packets[idx][k]:02X} actual 0x{body[k]:02X}"
                for k in open_bad)
            info(f"pkt#{idx} @{off} MASKED difference (reported, not fatal): "
                 f"{desc}")
        if not strict_bad and not open_bad:
            info(f"pkt#{idx} @{off}: all 33 bytes match golden  OK")

    lines.append("CHECK RESULT: " + ("PASS" if ok else "FAIL"))
    return ok, lines


def _load_golden():
    return json.loads((HERE / "golden" / "expected_packets.json").read_text())


def _rebuild(body: bytes) -> bytes:
    """Return body with a freshly computed checksum (bytes 2..31 scope)."""
    b = bytearray(body)
    b[32] = checksum_of(bytes(b))
    return bytes(b)


def self_test():
    golden = _load_golden()
    wins = golden["windows"]
    exp_packets = [bytes(w["packet"]) for w in wins]
    stream = b"".join(exp_packets)

    # --- case 1: a clean capture must PASS --------------------------------
    ok, lines = check_capture(stream, golden)
    assert ok, "clean capture must pass:\n" + "\n".join(lines)
    assert len(list(decode_stream(stream))) == N_PACKETS

    # --- case 2: a missing packet must FAIL --------------------------------
    ok2, _ = check_capture(b"".join(exp_packets[:3] + exp_packets[4:]), golden)
    assert not ok2, "missing packet must fail the check"

    # --- case 3: reordered packets must FAIL -------------------------------
    reordered = [exp_packets[1], exp_packets[0]] + exp_packets[2:]
    ok3, _ = check_capture(b"".join(reordered), golden)
    assert not ok3, "reordered packets must fail the check"

    # --- case 4: a corrupt checksum must FAIL ------------------------------
    bad = bytearray(stream)
    bad[32] ^= 0xFF
    ok4, _ = check_capture(bytes(bad), golden)
    assert not ok4, "bad checksum must fail the check"

    # --- case 5: a wrong STRICT byte with a RECOMPUTED checksum must FAIL --
    tampered = bytearray(exp_packets[0])
    tampered[6] ^= 0x01                 # f_rms low byte — a strict byte
    p5 = _rebuild(bytes(tampered)) + b"".join(exp_packets[1:])
    ok5, lines5 = check_capture(p5, golden)
    assert not ok5, "wrong strict byte must fail even with a valid checksum"
    assert any("strict mismatch" in l for l in lines5), lines5

    # --- case 6: a MASKED byte changed with a valid checksum -> reported ---
    tampered2 = bytearray(exp_packets[0])
    tampered2[16] ^= 0x20              # f_crest low byte — a masked byte
    p6 = _rebuild(bytes(tampered2)) + b"".join(exp_packets[1:])
    ok6, lines6 = check_capture(p6, golden)
    assert ok6, "masked-byte change must not fail the check:\n" + \
        "\n".join(lines6)
    assert any("MASKED difference" in l for l in lines6), lines6

    # --- the parser still rejects a corrupt checksum -----------------------
    assert len(list(decode_stream(bytes(bad)))) == N_PACKETS - 1
    # --- resync after garbage prefix ---------------------------------------
    assert len(list(decode_stream(b"\x00\x01\x02" + stream))) == N_PACKETS

    print(f"PASS uart_decode self-test: {N_PACKETS} golden packets decoded, "
          f"corrupt-checksum rejected, resync ok")
    print("PASS uart_decode check cases: clean=PASS missing=FAIL "
          "reorder=FAIL badsum=FAIL strict-byte=FAIL masked-byte=reported")


if __name__ == "__main__":
    args = sys.argv[1:]
    if args and args[0] == "--check":
        if len(args) != 2:
            print("usage: uart_decode.py --check <capture.bin>",
                  file=sys.stderr)
            sys.exit(2)
        path = Path(args[1])
        try:
            blob = path.read_bytes()
        except OSError as e:
            print(f"ERROR cannot read {path}: {e}", file=sys.stderr)
            sys.exit(2)
        ok, report = check_capture(blob, _load_golden())
        print(f"== capture check: {path} ({len(blob)} bytes) ==")
        for line in report:
            print(line)
        sys.exit(0 if ok else 1)
    elif args:
        blob = Path(args[0]).read_bytes()
        for off, pkt in decode_stream(blob):
            print(f"@{off:6d} win={pkt['win_index']} class={pkt['class']} "
                  f"flags={pkt['flags']:b} feats={pkt['features']}")
    else:
        self_test()
```

## Phụ lục C — script kiểm INIT_RAM (dùng ở lần synthesis tới)

```python
import re, sys
from pathlib import Path
net = Path(sys.argv[1]).read_text(errors='replace')
hexf = Path(sys.argv[2]).read_text().split()
d = {int(m.group(1),16): int(m.group(2),16)
     for m in re.finditer(r"INIT_RAM_([0-9A-Fa-f]+)=256'h([0-9A-Fa-f]+)", net)}
data = [int(x,16) for x in hexf if x.strip()]
print("INIT_RAM words:", len(d), " hex samples:", len(data))
def le(v,n=32): return [(v>>(8*i))&0xFF for i in range(n)]
def be(v,n=32): return [(v>>(8*(n-1-i)))&0xFF for i in range(n)]
for name, fn in (("LE",le),("BE",be)):
    ok = all(fn(d[i]) == data[i*32:(i+1)*32] for i in sorted(d) if i*32 < len(data))
    print(f"  {name}: {'MATCH' if ok else 'no match'}")
```
