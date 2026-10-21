# Báo Cáo Chi Tiết Các Module ECG Classifier

**Phiên bản:** v3.0
**Ngày:** 2025
**Mục tiêu:** FPGA Gowin GW5A-LV25
**Dự án:** ECG Classification AI Accelerator (KHÔNG liên quan PPG)

---

## 0. Thay Đổi Spec (So Với Phiên Bản Cũ)

| Thông số | Phiên bản cũ | **Phiên bản mới** |
|----------|--------------|--------------------|
| System clock | 100 MHz | **50.4 MHz** |
| Sample rate (input) | 500 Hz | **360 Hz** (chuẩn MIT-BIH) |
| `sample_rate_div` | 200000 | **140000** |
| `clks_per_bit` UART | 868 | **437** |
| Weight.hex | Cũ | **Retrain với data 360 Hz** |
| Tín hiệu vào | PPG | **ECG 8-bit** |
| Module PPG | Có | **BỎ HOÀN TOÀN** |

**Lý do đổi spec:**
- Nâng clock Gowin lên 50.4 MHz (do khả năng PLL của GW5A)
- Nâng sample rate lên 360 Hz (chuẩn MIT-BIH Arrhythmia Database)
- Retrain model với data 360 Hz → `weight.hex` mới
- **Bỏ mọi tham chiếu PPG** vì hệ thống chỉ nhận tín hiệu ECG

**Công thức mới:**
- Sample rate: `f_sample = 50.4 MHz / 140000 = 360 Hz`
- Baud rate: `50.4 MHz / 115200 ≈ 437` → `clks_per_bit = 437`

---

## 1. Tổng Quan Hệ Thống

Hệ thống phân loại tín hiệu **ECG** với AI acceleration, thực hiện pipeline:

```
ADC 8-bit (360 Hz) → Window Buffer (512 mẫu, overlap 50%) 
  → Feature Extraction (12 features) 
  → AI Classifier (MLP 12→8→4) 
  → UART TX → BLE
```

**Thông số chính:**
- System clock: **50.4 MHz** (Gowin)
- Sample rate input: **360 Hz** (tăng từ 250 Hz)
- Window: 512 mẫu = 1.422s @ 360 Hz
- Overlap: 256 mẫu = 711ms
- Features: 12 × 16-bit
- MLP: 12 → 8 → 4
- Output: 4 lớp (Normal/Fast/Slow/Abnormal)

**Lưu ý:** Hệ thống **CHỈ** nhận tín hiệu ECG. Không có bất kỳ tín hiệu PPG nào được đưa vào.

---

## 2. Module: `adc_interface` (`adc/adc_interface.v`)

### 2.1 Nhiệm vụ
Nhận dữ liệu **ECG** ADC 8-bit song song từ AD8232, latching và forwarding với sample rate 360 Hz.

### 2.2 Cách hoạt động
- **Sample Rate Generator:** Chia clock 50.4 MHz xuống 360 Hz. Tạo `rate_tick` khi `rate_timer >= sample_rate_div`.
- **Rising Edge Detection:** Phát hiện cạnh lên của `adc_data_valid` để latch dữ liệu mới.
- **Data Buffering:** Lưu 1 mẫu vào `adc_data_latch`, đánh dấu `data_pending`.
- **Overflow Detection:** Nếu có data mới đến khi `data_pending=1` → bật `overflow_flag`.
- **Data Forwarding:** Khi `rate_tick` và `data_pending` → xuất `sample_out`, kéo `sample_valid` high 1 cycle.

### 2.3 Công thức
- `f_sample = f_clk / (sample_rate_div + 1)`
- `360 Hz = 50.4 MHz / 140000` → `sample_rate_div = 140000`

### 2.4 Input/Output

| Port | Width | Direction | Mô tả |
|------|-------|-----------|--------|
| clk | 1 | In | System clock (50.4 MHz) |
| rst_n | 1 | In | Reset active-low |
| sample_rate_div | 16 | In | Clock divider (= 140000) |
| adc_data_in | 8 | In | ADC ECG data parallel |
| adc_data_valid | 1 | In | Data valid strobe |
| adc_clk | 1 | In | ADC conversion clock |
| sample_out | 8 | Out | Sample tới Window Buffer |
| sample_valid | 1 | Out | Sample valid strobe |
| adc_overflow | 1 | Out | Overflow flag |
| sample_count | 32 | Out | Tổng số sample |

**Đã bỏ:** `mode_ppg_ecg` port (vì chỉ dùng ECG).

---

## 3. Module: `window_buffer` (`window/window_buffer.v`)

### 3.1 Nhiệm vụ
Lưu trữ 512 mẫu **ECG** gần nhất dưới dạng circular buffer, cho phép đọc tuần tự với 50% overlap. Đảm bảo R-peaks không bị miss.

### 3.2 Cách hoạt động
- **Circular Write:** Khi `sample_valid` và `enable` cùng active, ghi `sample_in` vào `ram[write_ptr]`. Sau khi ghi, tăng `write_ptr`. Khi đạt 511, quay về 0.
- **Sample Count:** Đếm `sample_cnt` từ 0 đến 511. Khi đạt 511 → `buffer_full=1`.
- **Window Ready Trigger:** Khi `sample_cnt` chia hết cho 256 (và ≥ 256) → phát `window_ready` 1 cycle. Vì sample_cnt liên tục tăng, điều kiện này xảy ra ở 256, 512, 768, ... → 50% overlap.
- **Read Address:** Tính `window_base` (vị trí cũ nhất trong window hiện tại). Khi buffer full, `window_base = write_ptr` (mẫu ngay sau write_ptr là cũ nhất).
- **Output:** `frame_out = ram[(window_base + read_addr) % 512]`.

### 3.3 Công thức
- Sample rate: 360 Hz
- Window fill time: `512 samples / 360 Hz = 1.422s`
- Overlap time: `256 samples / 360 Hz = 711ms`
- New window mỗi 711ms
- Số beat trong 1 window: ~1.5 beats (60-100 bpm)

### 3.4 Input/Output

| Port | Width | Direction | Mô tả |
|------|-------|-----------|--------|
| clk | 1 | In | System clock (50.4 MHz) |
| rst_n | 1 | In | Reset |
| enable | 1 | In | Enable buffering |
| soft_reset | 1 | In | Soft reset |
| sample_in | 8 | In | Sample ECG từ ADC |
| sample_valid | 1 | In | Sample valid |
| read_en | 1 | In | Read enable |
| read_addr | 9 | In | Read address 0-511 |
| frame_out | 8 | Out | Sample ra |
| window_ready | 1 | Out | Window đầy, sẵn sàng |
| samples_collected | 32 | Out | Tổng samples |
| ready_bank | 1 | Out | Bank ready (debug) |
| write_ptr_out | 9 | Out | Write pointer (debug) |

---

## 4. Module: `feature_extraction` (`feature/feature_extraction.v`)

### 4.1 Nhiệm vụ
Tính toán 12 đặc trưng thống kê từ 512 mẫu **ECG** trong 1 window.

### 4.2 Cách hoạt động
Module dùng FSM 7 trạng thái:
1. **IDLE:** Chờ `start_compute`
2. **ACCUMULATE:** Đọc 512 mẫu, tích lũy sum, sum_square, peak, min, zero-crossing, positive count, RR detection
3. **CALC_BASE:** Tính f_peak, f_max, f_ptp, f_zc, f_half_ratio, f_rr, f_rr_prev, f_rr_diff
4. **CALC_VAR:** Tính variance
5. **CALC_RMS:** Tính RMS và crest factor
6. **DONE:** Bật feature_valid, quay về IDLE

### 4.3 Công thức 12 Features

| # | Feature | Công thức | Format | Mô tả |
|---|---------|-----------|--------|--------|
| 0 | **f_rms** | √(Σx² / N) | Signed | Root Mean Square |
| 1 | **f_var** | E[X²] - (E[X])² | Signed | Phương sai |
| 2 | **f_peak** | max(x) | Signed | Giá trị đỉnh |
| 3 | **f_zc** | count(sign(x[i]) ≠ sign(x[i-1])) | Unsigned | Số lần qua zero |
| 4 | **f_ptp** | max(x) - min(x) | Signed | Peak-to-Peak |
| 5 | **f_crest** | f_peak / f_rms | Q4.12 | Crest factor |
| 6 | **f_half_ratio** | count(x ≥ 0) / N | Q4.12 | Tỷ lệ mẫu dương |
| 7 | **f_max** | max(x) | Signed | Max value |
| 8 | **f_rr** | rr_current | Unsigned | RR hiện tại (samples) |
| 9 | **f_rr_prev** | rr_previous | Unsigned | RR trước (samples) |
| 10 | **f_rr_ratio** | f_rr / f_rr_prev | Q4.12 | Tỷ số RR |
| 11 | **f_rr_diff** | f_rr - f_rr_prev | Signed | Hiệu RR |

**Trong đó:**
- `E[X]` = mean = Σx / N
- `E[X²]` = Σx² / N
- `N = 512`
- `sign(x)` = 0 nếu x < 0, 1 nếu x ≥ 0
- **RR detection** (dùng cho ECG): peak detection khi sample vượt ngưỡng R-peak và đang giảm

**Lưu ý với 360 Hz:**
- RR interval ở 60 bpm: 360/60 × 60 = 360 samples
- RR interval ở 100 bpm: 360/100 × 60 = 216 samples
- 1 window = 512 samples = chứa khoảng 1.5 beat

### 4.4 Input/Output

| Port | Width | Direction | Mô tả |
|------|-------|-----------|--------|
| clk, rst_n | 1 | In | Clock, reset |
| start_compute | 1 | In | Bắt đầu tính |
| **ecg_threshold** | 16 | In | **Ngưỡng R-peak (đổi từ ppg_threshold)** |
| read_enable | 1 | In | Yêu cầu đọc sample |
| sample_addr | 9 | Out | Address gửi tới window buffer |
| sample_in | 8 | In | Sample từ window buffer |
| f_rms..f_rr_diff | 16 | Out | 12 features |
| feature_valid | 1 | Out | Features ready |
| overflow | 1 | Out | Tràn số |

**Đã bỏ:** `ppg_threshold` port (đổi thành `ecg_threshold`).

---

## 5. Module: `ai_classifier` (`ai/ai_classifier.v`)

### 5.1 Nhiệm vụ
Phân loại 12 features thành 4 lớp **ECG** sử dụng MLP 12→8→4. Weights đã được retrain với data 360 Hz.

### 5.2 Cách hoạt động
Pipeline 10 states (điều khiển bởi `control_fsm`):

1. **IDLE:** Chờ `start` + `enable`
2. **LOAD:** Latch 12 features
3. **NORM:** Normalize: `x_norm[i] = (x[i] - mean[i]) * inv_scale[i]`
4. **FC1:** Tính 8 hidden logits qua MAC: `h[j] = Σ(W1[j][k] * x_norm[k])`, j∈[0,7], k∈[0,11]
5. **FC1_B:** Cộng bias: `h[j] += b1[j]`
6. **RELU:** `h[j] = max(0, h[j])`
7. **FC2:** Tính 4 output logits: `o[i] = Σ(W2[i][k] * h[k])`, i∈[0,3], k∈[0,7]
8. **FC2_B:** Cộng bias: `o[i] += b2[i]`
9. **ARGMAX:** Tìm class có logit lớn nhất → `class_code[1:0]`
10. **DONE:** Bật done, quay IDLE

### 5.3 Công thức

| Bước | Công thức |
|------|-----------|
| Normalize | `x_norm[i] = (x[i] - mean[i]) × inv_scale[i]` |
| FC1 (MAC) | `h_raw[j] = Σ(k=0..11) W1[j][k] × x_norm[k]` |
| FC1 + Bias | `h[j] = h_raw[j] + b1[j]` |
| ReLU | `h[j] = max(0, h[j])` |
| FC2 (MAC) | `o[i] = Σ(k=0..7) W2[i][k] × h[k]` |
| FC2 + Bias | `o[i] = o[i] + b2[i]` |
| Argmax | `class = argmax(o[0], o[1], o[2], o[3])` |

**Số lượng tham số:**
- W1: 8 × 12 = 96
- b1: 8
- W2: 4 × 8 = 32
- b2: 4
- Mean: 12, inv_scale: 12
- **Tổng: 164 words (16-bit)** - tổng số giữ nguyên

**⚠️ Lưu ý:** weights trong `weight.hex` phải được **retrain** với dataset ECG 360 Hz, vì các giá trị mean, inv_scale, weights đều thay đổi khi sample rate thay đổi từ 500 Hz → 360 Hz.

### 5.4 Input/Output

| Port | Width | Direction | Mô tả |
|------|-------|-----------|--------|
| clk, rst_n | 1 | In | Clock, reset |
| start | 1 | In | Bắt đầu inference |
| enable | 1 | In | Module enable |
| features[0:11] | 16×12 | In | 12 features |
| class_code | 2 | Out | Class 0-3 |
| done | 1 | Out | Inference complete |
| overflow | 1 | Out | Tràn số |
| fc1_out, fc2_out | 32 | Out | Debug |

---

## 6. Module: `mlp_weights_rom` (`ai/mlp_weights_rom.v`)

### 6.1 Nhiệm vụ
Lưu trữ 164 trọng số/bias Q4.12, load từ `weight.hex` (retrain cho ECG 360 Hz).

### 6.2 Cách hoạt động
- ROM 164 × 16-bit
- Address map:
  - `[0-11]`: Mean (12) - **giá trị mới cho 360 Hz**
  - `[12-23]`: Inverse Scale (12) - **giá trị mới cho 360 Hz**
  - `[24-119]`: FC1 weights (96) - **weights mới**
  - `[120-127]`: FC1 biases (8) - **biases mới**
  - `[128-159]`: FC2 weights (32) - **weights mới**
  - `[160-163]`: FC2 biases (4) - **biases mới**

### 6.3 Input/Output

| Port | Width | Direction | Mô tả |
|------|-------|-----------|--------|
| clk | 1 | In | Clock |
| addr | 8 | In | ROM address |
| data_out | 16 | Out | Data output |

**Lưu ý:** `weight.hex` không thay đổi trong PR này (do người phụ trách AI cập nhật sau với model đã retrain).

---

## 7. Module: `control_fsm` (`control/control_fsm.v`)

### 7.1 Nhiệm vụ
FSM master 10 trạng thái điều khiển toàn bộ pipeline classification **ECG**.

### 7.2 States
```
IDLE → LOAD → NORMALIZE → FC1 → FC1_B → RELU → FC2 → FC2_B → ARGMAX → DONE
```

| State | Chức năng |
|-------|-----------|
| IDLE | Chờ `start` |
| LOAD | Trigger Window Buffer |
| NORMALIZE | Bật feature computation |
| FC1..FC2_B | Điều khiển AI Classifier |
| ARGMAX | Đợi kết quả |
| DONE | Bật `done`, gửi UART |

### 7.3 Input/Output

| Port | Width | Direction | Mô tả |
|------|-------|-----------|--------|
| clk, rst_n | 1 | In | Clock, reset |
| start | 1 | In | Bắt đầu |
| feat_valid | 1 | In | Features ready |
| apb_enable | 1 | In | APB enable |
| fsm_idle | 1 | Out | FSM idle |
| window_en | 1 | Out | Enable window buffer |
| feature_start | 1 | Out | Start features |
| feature_read_en | 1 | Out | Read enable |
| mlp_start | 1 | Out | Start MLP |
| mlp_valid | 1 | Out | MLP valid |
| uart_send | 1 | Out | Trigger UART |
| done | 1 | Out | Classification done |
| read_addr | 9 | Out | Address read |
| current_state, next_state | 4 | Out | Debug |

---

## 8. Module: `apb_slave_if` (`apb/apb_slave_if.v`)

### 8.1 Nhiệm vụ
APB AMBA3 slave interface quản lý CSR (Configuration & Status Registers) để host cấu hình hệ thống **ECG**.

### 8.2 Cách hoạt động
- **Write:** Khi `psel && pwrite && !penable` (SETUP phase), latching data vào register tương ứng theo `paddr`. Pulse signals (start, soft_reset) được tạo 2-cycle.
- **Read:** Khi `psel && !pwrite` (SETUP phase), lách `prdata` với giá trị từ thanh ghi.
- **Ready:** `pready = psel && penable` (1 cycle latency trong ACCESS phase).

### 8.3 Register Map

| Offset | Register | Mô tả |
|--------|----------|-------|
| 0x00 | CTRL | bit[0]=enable, bit[1]=start, bit[2]=irq_en, bit[4]=soft_reset |
| 0x04 | STATUS | bit[0]=busy, bit[1]=done, bit[3]=overflow |
| 0x08 | **ECG_THRESH** | **Ngưỡng R-peak (đổi tên từ THRESH)** |
| 0x0C | BAUD | UART baud divisor (cho 50.4 MHz) |
| 0x10 | RESULT | Classification result (class_code) |
| 0x14 | VERSION | IP version 0x0200 (v2.0) |
| 0x18 | CONFIG | bit[0]=ble_en, bit[1]=uart_en |

**Lưu ý với clock mới 50.4 MHz:**
- BAUD register default: `50.4 MHz / 115200 = 437`

**Đã bỏ:** thanh ghi `THRESH` được đổi tên thành `ECG_THRESH` để phản ánh đúng chức năng (ngưỡng R-peak của ECG, không phải ngưỡng PPG).

### 8.4 Input/Output

| Port | Width | Direction | Mô tả |
|------|-------|-----------|--------|
| pclk, presetn | 1 | In | Clock (50.4 MHz), reset |
| paddr | 8 | In | APB address |
| psel, penable, pwrite | 1 | In | APB control |
| pwdata | 32 | In | Write data |
| prdata | 32 | Out | Read data |
| pready, pslverr | 1 | Out | APB status |
| sys_enable, sys_start, soft_reset | 1 | Out | Control |
| **ecg_threshold** | 16 | Out | **Ngưỡng R-peak (đổi từ ppg_threshold)** |
| baud_div | 16 | Out | Baud divisor |
| ble_enable, uart_enable | 1 | Out | Enable |
| sys_busy, sys_done, sys_class_code, sys_overflow | - | In | Status |

---

## 9. Module: `uart_tx` (`uart/uart_tx.v`)

### 9.1 Nhiệm vụ
Gửi classification result **ECG** qua UART đến module BLE (HC-05).

### 9.2 Cách hoạt động
- **Baud Generator:** Chia clock theo `baud_div` để tạo baud tick.
- **Transmit Shift Register:** Khi `tx_start` và `tx_enable`, load `tx_data` vào shift register.
- **Frame Format:** Start bit (0) → 8 data bits (LSB first) → Stop bit (1).
- **Status:** `tx_busy` trong khi gửi, `tx_done_tick` 1-cycle khi hoàn tất.

### 9.3 Công thức
- `clks_per_bit = f_clk / baud_rate`
- **Với clock mới 50.4 MHz:** `clks_per_bit = 50.4 MHz / 115200 = 437.5 ≈ 437`
- Default: `CLKS_PER_BIT = 437`

### 9.4 Input/Output

| Port | Width | Direction | Mô tả |
|------|-------|-----------|--------|
| clk, rst_n | 1 | In | Clock (50.4 MHz), reset |
| baud_div | 16 | In | Baud divisor (= 437) |
| tx_data | 8 | In | Data cần gửi |
| tx_start | 1 | In | Bắt đầu gửi |
| tx_enable | 1 | In | Enable |
| tx_busy | 1 | Out | Đang gửi |
| tx_done_tick | 1 | Out | Pulse khi xong |
| uart_txd | 1 | Out | UART TX line |

---

## 10. Module: `top_ecg_classifier` (`top/top_ecg_classifier.v`)

### 10.1 Nhiệm vụ
Top-level SoC tích hợp tất cả module: APB, ADC, Window Buffer, Feature Extraction, AI Classifier, Control FSM, UART TX.

**Lưu ý:** Đã đổi tên từ `top_ppg_classifier.v` → `top_ecg_classifier.v` (module `top_ecg_classifier`, tb `tb/tb_top_ecg_classifier.sv`).

### 10.2 Cách hoạt động
- Kết nối tất cả instance theo data flow.
- **`sample_rate_div = 140000`** (cho 360 Hz @ 50.4 MHz).
- Routing: `sys_overflow = feature_overflow | mlp_overflow`.
- `sys_busy = ~fsm_idle`.
- LEDs: fsm_idle, window_ready, feature_valid, sys_done.
- UART data: `{6'b0, sys_class_code}`.

### 10.3 Input/Output

| Port | Width | Direction | Mô tả |
|------|-------|-----------|--------|
| sys_clk | 1 | In | **50.4 MHz** (Gowin) |
| sys_rst_n | 1 | In | Reset |
| paddr[31:0] | 32 | In | APB address |
| psel, penable, pwrite | 1 | In | APB control |
| pwdata[31:0] | 32 | In | Write data |
| prdata[31:0] | 32 | Out | Read data |
| adc_data[7:0] | 8 | In | ADC parallel data (ECG) |
| adc_valid | 1 | In | ADC valid |
| uart_txd | 1 | Out | UART TX |
| uart_rxd | 1 | In | UART RX |
| irq | 1 | Out | Interrupt |
| status_led[3:0] | 4 | Out | Debug LEDs |

---

## 11. Triển Khai Trên Board Gowin

### 11.1 FPGA Target: Gowin GW5A-LV25

**Thông số clock mới:**
- Input clock: 50.4 MHz (qua PLL từ 100 MHz oscillator hoặc trực tiếp)
- System clock: 50.4 MHz cho toàn bộ logic

| Thông số | Giá trị |
|-----------|---------|
| LUTs | ~2,000 (dùng ~10% tài nguyên GW5A-LV25) |
| DFFs | ~1,500 |
| BSRAM | 2 blocks (18K) |
| DSP | 4 (cho MAC) |
| Max clock | 50.4 MHz (đáp ứng thoải mái, GW5A có thể lên đến 200+ MHz) |

### 11.2 Pinout đề xuất

| Tín hiệu | Pin | Mô tả |
|----------|-----|--------|
| sys_clk | dedicated CLK input | **50.4 MHz** oscillator (qua PLL) |
| sys_rst_n | general I/O | Nút nhấn reset |
| uart_txd | general I/O | Đến HC-05 RX |
| uart_rxd | general I/O | Từ HC-05 TX (optional) |
| adc_data[7:0] | general I/O | Từ **AD8232** OUT[7:0] (ECG chip) |
| adc_valid | general I/O | Từ AD8232 DRDY |
| status_led[3:0] | general I/O | 4 LEDs debug |
| irq | general I/O | Interrupt output |

### 11.3 Clock Structure

**Option 1: External 50.4 MHz oscillator**
- Thạch anh 50.4 MHz cấp trực tiếp vào FPGA CLK pin
- Không cần PLL

**Option 2: PLL từ 100 MHz**
- Thạch anh 100 MHz vào PLL
- PLL output: 50.4 MHz (chia từ 100 MHz × 504/1000)

### 11.4 Toolchain
- **Gowin EDA:** Synthesize, Place & Route, Bitstream
- **File input:** RTL files + constraints (.cst)
- **Output:** .fs bitstream

### 11.5 Build Flow
1. Tạo project Gowin EDA
2. Add source: tất cả file `.v`
3. Add constraint: pin assignments
4. Cấu hình PLL: input 100 MHz → output 50.4 MHz
5. Synthesize → check timing (target 50.4 MHz)
6. Place & Route → check resource usage
7. Generate bitstream `.fs`
8. Program board qua JTAG

### 11.6 Verification Plan
1. **Simulation:** chạy testbench trên Icarus Verilog (với clock 50.4 MHz)
2. **Testbench updates:**
   - Cập nhật clock period từ 10ns (100 MHz) → **19.84ns (50.4 MHz)**
   - Cập nhật `sample_rate_div` từ 200000 → **140000**
   - Cập nhật `clks_per_bit` UART từ 868 → **437**
3. **On-board:**
   - Test ADC: inject sine wave 360 Hz sample rate, kiểm tra UART output
   - Test APB: write/read CSR qua JTAG/UART
   - Test classifier: feed ECG known dataset (MIT-BIH 360 Hz), kiểm tra class_code

### 11.7 Risk & Notes
- **DSP blocks:** Gowin có DSP9KC, 4 blocks đủ cho MAC
- **BSRAM:** Cần cho ROM weight (164 × 16-bit = 328 bytes) → 1 block đủ
- **Timing:** 50.4 MHz dễ đạt timing slack
- **Power:** Có thể cần clock gating để giảm năng lượng
- **PLL configuration:** Cần tính toán PLL parameters cẩn thận

---

## 12. Tổng Kết

| Module | Complexity | Latency | Resources |
|--------|-----------|---------|-----------|
| adc_interface | Low | 2 cycles | - |
| window_buffer | Medium | 1 cycle | 1 BSRAM |
| feature_extraction | High | ~512 cycles | DSP, MULT |
| ai_classifier | Very High | ~150 cycles | 1 BSRAM (ROM) |
| control_fsm | Low | - | - |
| apb_slave_if | Low | 1 cycle | - |
| uart_tx | Low | ~10 cycles | - |
| top | Integration | - | - |

**Tổng tài nguyên ước tính cho GW5A-LV25:** ~10% LUTs, ~5% BSRAM, ~20% DSP.

**Clock budget @ 50.4 MHz:**
- 1 cycle = 19.84 ns
- 512 cycles feature extraction = 10.16 µs
- 150 cycles MLP = 2.98 µs
- Total pipeline latency = ~662 cycles = ~13.13 µs

**Sample rate budget @ 360 Hz:**
- 1 sample = 2.78 ms
- 512 samples = 1.422s (fill 1 window)
- 256 samples = 711ms (new window với 50% overlap)

---

## 13. Tóm Tắt Thay Đổi

### Thay đổi spec:
- ✅ System clock: 100 MHz → **50.4 MHz**
- ✅ Sample rate: 500 Hz → **360 Hz**
- ✅ `sample_rate_div`: 200000 → **140000**
- ✅ `clks_per_bit` UART: 868 → **437**
- ✅ `version`: 0x0100 → **0x0200**

### Bỏ tham chiếu PPG:
- ✅ `ppg_threshold` → **`ecg_threshold`** (in apb_slave_if, feature_extraction, top)
- ✅ Thanh ghi `THRESH` → **`ECG_THRESH`** (in apb_slave_if register map)
- ✅ `mode_ppg_ecg` port **bỏ** (trong adc_interface)
- ✅ Comments và tài liệu: thay "PPG" bằng "ECG"

### KHÔNG thay đổi trong PR này:
- ❌ `weight.hex` - do người phụ trách AI cập nhật sau khi retrain với data 360 Hz

### Đổi tên file top level (PR này):
- ✅ `top/top_ppg_classifier.v` → `top/top_ecg_classifier.v` (module `top_ecg_classifier`)
- ✅ `tb/tb_top_ppg_classifier.sv` → `tb/tb_top_ecg_classifier.sv` (module `tb_top_ecg_classifier`)
- ✅ `sim/tb_top.sv` → `sim/tb_top_ecg.sv`
- ✅ Cập nhật: `tb/Makefile`, `tb/run_all.sh`, `tb/run_all.bat`, `tb/README.md`,
  `synthesis/run_synth.tcl`, `docs/interfaces.md`, `AGENTS.md`, `README.md`, các `README.md` trong folder

### Checklist cập nhật code:
- [x] `top/top_ecg_classifier.v`: `sample_rate_div = 140000` (18-bit), đổi `ppg_threshold` → `ecg_threshold`
- [x] `uart/uart_tx.v`: `CLKS_PER_BIT = 437`
- [x] `apb/apb_slave_if.v`: baud default 437, `ppg_threshold` → `ecg_threshold`, VERSION 0x0200
- [x] `feature/feature_extraction.v`: `ppg_threshold` → `ecg_threshold`
- [x] `adc/adc_interface.v`: bỏ port `mode_ppg_ecg`, `sample_rate_div` mở rộng 16 → 18 bit
- [x] `tb/tb_*.sv`: clock period 19.84ns
- [x] `synthesis/run_synth.tcl`: timing constraint 50.4 MHz (19.84 ns)
- [x] `docs/interfaces.md`: cập nhật spec mới
- [x] `README.md` (root và mỗi folder): cập nhật thông số

**Ghi chú:** `sample_rate_div` phải mở rộng từ 16 → 18 bit vì 140000 > 65535
(giá trị cũ `16'd200000` cũng đã bị truncate âm thầm).

---

## 14. Liên Hệ Với AGENTS.md

Các thay đổi này tuân thủ:
- **Mục 4.1:** Đã đọc `docs/interfaces.md` và README trong từng folder trước khi sửa
- **Mục 4.2:** Đã cập nhật `docs/interfaces.md` cho mọi thay đổi port
- **Mục 4.6:** KHÔNG tự thay đổi `weight.hex`
- **Mục 4.7:** KHÔNG làm yếu testbench

Phạm vi: D (file dùng chung) - cần owner D duyệt khi merge.
