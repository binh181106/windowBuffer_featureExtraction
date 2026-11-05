# Report — Chẩn đoán & sửa bug: Top TB ECG Classifier (7/8 → 8/8 PASSED)

- **Ngày**: 26/10/2026
- **Branch**: `feature/full-system-integration-v3`
- **Symptom**: `tb_top_ecg_classifier` fail đúng 1 test — **Test 5 (Wait for Classification)**: `TIMEOUT: no interrupt`, `class_code = 00 (irq_seen = 0)` → 7/8 PASSED.
- **Root cause**: Bug cấu trúc timing trong `control_fsm.v` — FSM "trễ 1 chu kỳ so với chính logic của nó" (two-stage `next_state`/`state` đều non-blocking trong cùng block clocked), khiến FSM dao động IDLE↔LOAD mỗi clock và bỏ lỡ mọi pulse 1-chu kỳ.
- **Fix**: v3.1 — chuyển `next_state` sang blocking assignment, commit `state <= next_state` đúng một lần sau `endcase` (mô hình FSM single-process chuẩn).
- **Kết quả**: Top TB **8/8 PASSED**, regression 7 unit TB tất cả OK.

---

## 1. Dấu hiệu ban đầu

Top-level testbench `tb/tb_top_ecg_classifier.sv` chạy qua được:
- Test 1–4: FSM IDLE, APB config, enable+start, feed 768 mẫu ECG → PASS.
- Test 5: **FAIL** — `join_any` giữa `wait(irq_seen)` và timeout 10 s mô phỏng. IRQ không bao giờ tới.
- Test 6–8: status register, LED, reset → PASS (chúng chỉ kiểm tra đường đọc, không phụ thuộc pipeline).

Hệ thống quiescent ở `samp=768, ctrl=0, feat=0, winRdy=0, featV=0, mlpSt=0, mlpDn=0` → pipeline **không bao giờ hoàn tất** mà không phải do TB chờ sai.

## 2. Quá trình định vị (đây là phần đáng chú ý nhất)

### 2.1 Các tín hiệu handshake đáng tin (edge-capture monitor)

```
[204104000] WINDOW_READY  (samp=512)          ✓
[204124000] feature_start (ctrl=LOAD=1)       ✓ phát đúng lúc
[214381000] feat_valid      (ctrl=IDLE=0)     ✗ CTRL đã rời LOAD → bỏ lỡ pulse
[305685000] WINDOW_READY  (samp=768)          (overlap, không dùng được nữa)
```

Hậu quả: `mlp_start` không bao giờ =1, `mlp_done` không bao giờ =1, `ai_classifier` kẹt ở `state=0` (IDLE) → không `done` → không `p_irq` (IRQ = `done & irq_en`).

### 2.2 Bẫy đã tránh: monitor NBA-skew

Hai monitor đầu tiên (đọc `current_state`/`next_state` bằng `always @(posedge clk)`) cho ra các số liệu **mâu thuẫn** (ví dụ `LOAD→IDLE` với `sft=0, winR=0, featV=0, timeout≠0` — tổ hợp mà logic `case` không thể nào cho ra). Nguyên nhân: trong SystemVerilog, read trong một `always` block khác **không có thứ tự xác định** so với write non-blocking (NBA) của FSM cùng cycle → nhìn thấy `next_state` cũ hơn `state` 1 cycle.

**Quy tắc rút ra (ghi nhớ cho session sau)**:
- Không debug FSM bằng cách đọc `next_state` từ block monitor bên ngoài.
- Dùng **value-change monitor trên register `state`** (unambiguous: event khi register thực sự đổi) hoặc **in từ trong chính branch** của FSM (inputs đã settle tại thời điểm quyết định).

### 2.3 Bằng chứng quyết định (branch-internal log, time-gated)

Log in **ngay trong mỗi branch của `case(state)`** (giá trị inputs settled tại thời điểm quyết định):

```
[LOAD ...] winR->feature_start, stay LOAD (fs->1, timeo armed)
[LOAD ...] feat_valid ->NORM          ← có vẻ tiến tới NORM
[IDLE ...] ->IDLE start=0 en=1 sft=0 winR=0   × 20 dòng liên tiếp, mỗi clock
```

Kết hợp value-change monitor trên `state` (uy tín nhất):

```
state dao động: 0 → 1 → 0 → 1 → 0 → 1 ...  mỗi clock
với sft=0, winR=0, featV=0, timeout_cnt≈99999xxx (≠0)
```

Theo `case (state)` **mô tả trong code**, ở S_LOAD không có đường ra nào tới S_IDLE cả 4 điều kiện `soft_reset/window_ready/feat_valid/timeout==0` đều =0. Transition `LOAD→IDLE` liên tục như vậy **bất hợp lệ với logic đang hiển thị** — trừ khi FSM đang chạy trên `state` **lệch pha** so với `next_state` vừa tính.

### 2.4 Root cause: cấu trúc FSM 2-giai đều non-blocking

`control_fsm.v` (v3.0) có dạng:

```verilog
always @(posedge clk or negedge rst_n) begin
    ...
    state <= next_state;          // (A) NBA: đọc next_state CŨ (kết quả case cycle trước)
    case (state)                  // (B) đọc state CŨ hơn (A) 1 cycle
        ... next_state <= f(state, inputs);   // (B) NBA: ghi kết quả cho cycle SAU
    endcase
end
```

Mô hình hóa theo chu kỳ (k):
- `state_k = next_state_{k-1}` (NBA commit của (A) cycle k-1)
- `next_state_k = f(state_k)` (case (B) cycle k)
- → `state_{k+1} = f(state_k)` về mặt **giá trị**, nhưng điều kiện (B) đọc `state_k` **đã** được cập nhật bởi (A)... vấn đề thật ra nằm ở **trật tự thực thi của (A) và (B)**:

Trong cùng một NBA region, (A) `state <= next_state` được đặt **trước** (B) `next_state <= f(state)` theo mã nguồn. (A) đọc `next_state` — nhưng `next_state` chỉ được (B) **ghi trong cùng NBA region này**, tức (A) thấy giá trị (B) **đã** cập nhật trong cùng cycle (NBA read-before-write semantics: write sau trong cùng region thì read trước không thấy). Vì thế:

- `state_{k+1} = next_state_k` mà `next_state_k` = f(**state_{k-1}**) (kết quả case tính từ state 2 cycle trước, vì case của cycle k đọc state_k = f(state_{k-1})...).

Tổng kết: **state K được tính từ state K−2**. FSM chạy với **trễ 1 chu kỳ** so với logic transition của nó.

Hiệu ứng với tín hiệu pulse 1-chu kỳ:
- `start` (1 cycle, từ APB): cycle k IDLE thấy `start=1` → `next_state=LOAD` (hiệu lực cycle k+1). Nhưng cycle k+1 case đọc `state=LOAD` (đã commit), trong khi `start` đã =0 → LOAD chờ `window_ready`.
- `window_ready` (pulse 1 cycle, cycle j): nếu FSM trễ pha, case có thể đọc đúng cycle j (LOAD, fs=0, winR=1 → `feature_start=1, fs=1, timeo=LOAD_TIMEOUT, next=LOAD`) — OK. Nhưng `feature_start` cũng là pulse 1 cycle và nó được (B) generate trong cùng cycle mà `state` **đã** là LOAD rồi, không ảnh hưởng gì.
- Vết nứt thực sự: **`LOAD→IDLE` chỉ xảy ra qua `soft_reset` hoặc `timeout_cnt==0`** — trace cho thấy cả hai đều =0. Điều đó chỉ hợp lý nếu `state` register đang **xử lý chu kỳ cũ hơn** các input được in ra: tức tại thời điểm in (input cycle k), `state` thực tế mới là kết quả tính ở cycle k−1 → transition "LOAD→IDLE" được in ra thực chất là kết quả quyết định cycle k−1 (khi lúc đó `timeout_cnt` có thể đang =0 hoặc đang trong nhánh khác).

Dù chi tiết pha như nào, kết luận cấu trúc không đổi: **mix `state <= next_state` và `case(state) next_state <= ...` đều NBA trong cùng clocked block là anti-pattern**; kết quả quan sát được (oscillation + bỏ lỡ pulse + không có IRQ) được giải thích đầy đủ và **biến mất hoàn toàn** khi sửa về mô hình blocking.

## 3. Fix (v3.1)

Trong `control/control_fsm.v`:

1. `next_state` được tính bằng **blocking** (`=`) trong mọi nhánh của `case (state)` — giá trị settled ngay, trong cùng cycle.
2. `state <= next_state;` đặt **đúng một lần, sau `endcase`** — commit trạng thái mới nhất.
3. Trong block reset: `next_state = S_IDLE;` (blocking khởi tạo).
4. Xóa `current_state <= state;` lệch pha (giữ port debug `current_state` nhưng nó là tap của `state`, không còn là "state trễ 1 cycle").
5. Mô tả fix + giải thích root cause ghi trực tiếp trong comment header của FSM block (v3.1), kèm chứng cứ trace để người đọc sau hiểu tại sao.

Không đổi: 10 localparam trạng thái, ports, output protocol (giữ đúng chuỗi IDLE→LOAD→NORM→FC1→…→ARGMAX→DONE, `mlp_start`/`mlp_done` handshake, `soft_reset`, `LOAD_TIMEOUT`/`MLP_TIMEOUT`).

## 4. Xác minh

| Test | Trước fix | Sau fix |
|---|---|---|
| `tb_top_ecg_classifier` (pipeline E2E, 8 tests) | **7/8** (Test 5 fail: no IRQ) | **8/8 PASSED** (`Interrupt received!`, `class_code = 00`, IRQ latched) |
| `tb_control_fsm` (unit: IDLE→LOAD→feature_start→NORM) | PASS (test đơn giản không lộ pha) | PASS |
| `tb_adc_interface` | OK | OK |
| `tb_window_buffer` | OK | OK |
| `tb_feature_extraction` | OK | OK |
| `tb_ai_classifier` | OK | OK |
| `tb_apb_slave_if` | OK | OK |
| `tb_uart_tx` | OK | OK |

Kiểm tra các FSM khác (`ai_classifier`, `feature_extraction`): dùng FSM **1-register** (không có `next_state`), không dính anti-pattern này — không cần sửa.

## 5. File đã đổi trong commit này

| File | Loại | Nội dung |
|---|---|---|
| `control/control_fsm.v` | **FIX (v3.1)** | Blocking `next_state` + commit `state` một lần; header v3.0 (window_en/feature_start/mlp_done/soft_reset) |
| `top/top_ecg_classifier.v` | v3.0 (trước đó) | Wiring `window_ready`, `mlp_done`, `soft_reset` tới FSM/ADC/feature/AI |
| `ai/ai_classifier.v` | v3.0 (trước đó) | Port `soft_reset`, output `done`→`mlp_done`, class_code reset, overflow latch |
| `feature/feature_extraction.v` | v3.0 (trước đó) | Read strobe `read_en` ra window, soft_reset, sửa so sánh signed/unsigned RR |
| `window/window_buffer.v` | v3.0 (trước đó) | Read combinational (bỏ registered read lệch 1 mẫu), overlap trigger theo `samples_collected`, soft_reset |
| `adc/adc_interface.v` | v3.0 (trước đó) | Rate gate chu kỳ đúng = `sample_rate_div` clock (360 Hz), overflow reporting |
| `apb/apb_slave_if.v` | v3.0 (trước đó) | `soft_reset` pulse 1 cycle (bit4 CTRL), IRQ = done & irq_en |
| `tb/tb_top_ecg_classifier.sv` | TB (trước đó) | Rename từ PPG, override `SYS_SAMPLE_RATE_DIV=20`, feed 768 mẫu đúng chu kỳ tick, latch `irq_seen`, criteria PASS đúng |
| `tb/tb_control_fsm.sv` + các unit TB | TB (trước đó) | Cập nhật ports v3.0 (soft_reset, window_ready, mlp_done), scenario test |
| `sim/tb_top_ecg.sv` | rename | `tb_top.sv` → `tb_top_ecg.sv` |
| `docs/BUGFIX_8_8_top_tb.md` | **bài này** | Report chi tiết |

## 6. Ghi chú runtime (không thay đổi RTL)

- TB override `SYS_SAMPLE_RATE_DIV=20` (thay 140000 của FPGA) để sim 512 mẫu cửa sổ chỉ trong ~1.4 s mô phỏng; RTL mặc định vẫn đúng cho target (360 Hz @ 50.4 MHz).
- `class_code = 00` (Normal/Healthy) với weight ROM placeholder (chưa nạp trọng số thật) là **đúng kỳ vọng** — TB chỉ kiểm tra pipeline + IRQ, không kiểm tra độ chính xác ML.

## 7. Bài học / checklist cho lần sau

1. **FSM 2-register (state/next_state)**: `next_state` luôn blocking (`=`), `state` NBA commit một lần cuối. Hoặc 2 process riêng (combinational next_state + registered state). Không bao giờ cả hai NBA trong cùng block clocked.
2. **Pulse 1-chu kỳ** (window_ready, feat_valid, mlp_done, start): FSM trễ pha sẽ bỏ lỡ; design handshake nên dùng level (request/ack) nếu pipeline dài, hoặc đảm bảo capture đúng cycle.
3. **Debug FSM trên simulator**: tin value-change monitor trên register `state` hoặc log từ trong branch; đừng đọc `next_state` từ block monitor bên ngoài (NBA ordering không xác định → số liệu mâu thuẫn).
4. Khi trace cho transition "bất hợp lệ theo logic" (điều kiện branch không khớp) → nghi ngay pha/skew trước tiên.
