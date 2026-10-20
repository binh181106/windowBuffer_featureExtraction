# docs/interfaces.md — Interface giữa các module (dự án phân loại ECG)

**Đây là nguồn sự thật duy nhất cho interface.** Mọi thay đổi port, độ rộng bit, thứ tự feature hoặc định dạng số phải sửa file này **trong cùng PR** và cần người sở hữu cả hai phía của interface duyệt.

Quy ước trạng thái:
- ✅ Đã có trong README hiện tại.
- ❓ **CẦN ĐIỀN**: chưa có trong README. Chủ sở hữu module đọc code `.v` rồi điền (không đoán).

## 1. Thông số hệ thống

| Mục | Giá trị | Trạng thái |
|---|---|---|
| System clock | **50.4 MHz** (Gowin GW5A-LV25) | ✅ |
| Tốc độ lấy mẫu ECG | **360 Hz** (chuẩn MIT-BIH Arrhythmia Database) | ✅ |
| `sample_rate_div` | **140000** (= 50.4 MHz / 360 Hz) | ✅ |
| ADC | 8-bit song song (ECG từ AD8232) | ✅ |
| Cửa sổ | 512 mẫu, overlap 50% | ✅ |
| Số feature | 12, mỗi feature 16-bit | ✅ |
| Định dạng số của feature/MLP | Q4.12, 16-bit (một số feature là signed/unsigned nguyên, xem mục 4) | ✅ |
| MLP | 12 → 8 → 4 (FC1 + bias, ReLU, FC2 + bias, argmax) | ✅ |
| Latency | Trích feature ~512 chu kỳ, MLP ~150 chu kỳ, tổng ~662 chu kỳ (~13.13 µs @ 50.4 MHz) | ✅ |
| Reset | Đồng bộ, active-low (`rst_n`) | ✅ |
| ADC | 8-bit signed (mẫu ECG có thể âm/dương) | ✅ |
| Baud rate UART | 115200, `clks_per_bit = 437` (50.4 MHz / 115200) | ✅ |
| `weight.hex` | 164 từ 16-bit, **phải retrain với data 360 Hz** (không thuộc PR này) | ✅ |

**Lưu ý quan trọng:**
- Dự án **CHỈ** nhận tín hiệu ECG. Mọi tham chiếu PPG đã được bỏ.
- Tên file `top_ppg_classifier.v` là tên lịch sử, không đổi trong PR này.

## 2. Luồng dữ liệu

```
adc_interface -> window_buffer -> feature_extraction -> ai_classifier -> uart_tx
                                        ^                    ^
                                   control_fsm ---------------+   (10 trạng thái)
apb_slave_if (CSR) -> cấu hình (threshold, baud, ...) -> control_fsm / uart_tx
```

Trạng thái FSM: `IDLE → LOAD → NORM → FC1 → FC1_B → RELU → FC2 → FC2_B → ARGMAX → DONE`

## 3. Port từng module

### 3.1 `apb_slave_if` (APB AMBA3 slave)

| Tín hiệu | Rộng | Hướng | Mô tả | TT |
|---|---|---|---|---|
| paddr | 32 | In | Địa chỉ APB | ✅ |
| psel | 1 | In | Peripheral select | ✅ |
| penable | 1 | In | APB enable | ✅ |
| pwrite | 1 | In | Write enable | ✅ |
| pwdata | 32 | In | Dữ liệu ghi | ✅ |
| prdata | 32 | Out | Dữ liệu đọc | ✅ |
| pready / pslverr / interrupt / các tín hiệu khác | ? | ? | ❓ | ❓ |
| Tín hiệu nối sang control/uart/window | ? | Out | ❓ | ❓ |

**Bản đồ thanh ghi CSR** ✅

| Offset | Thanh ghi | Mô tả |
|---|---|---|
| 0x00 | CTRL | enable, start, reset |
| 0x04 | STATUS | busy, done, error |
| 0x08 | **ECG_THRESH** | **Ngưỡng phát hiện đỉnh R của ECG (đổi tên từ THRESH/PPG_THRESH).** |
| 0x0C | BAUD | hệ số chia baud UART |
| 0x10 | RESULT | kết quả phân loại |
| 0x14 | VERSION | phiên bản IP |
| 0x18 | CONFIG | cấu hình hệ thống |

❓ Điền thêm: vị trí từng bit trong CTRL/STATUS/CONFIG, giá trị reset, trường nào read-only.

### 3.2 `adc_interface`

| Tín hiệu | Rộng | Hướng | Mô tả | TT |
|---|---|---|---|---|
| clk | 1 | In | System clock (50.4 MHz) | ✅ |
| rst_n | 1 | In | Reset active-low | ✅ |
| sample_rate_div | 16 | In | Clock divider (= 140000 cho 360 Hz) | ✅ |
| **adc_data_in** | 8 | In | **Dữ liệu ADC ECG song song (đổi tên từ mode_ppg_ecg đã bỏ)** | ✅ |
| adc_data_valid | 1 | In | Data valid strobe từ ADC | ✅ |
| adc_clk | 1 | In | ADC conversion clock | ✅ |
| sample_out | 8 | Out | Sample tới window_buffer | ✅ |
| sample_valid | 1 | Out | Sample valid strobe | ✅ |
| adc_overflow | 1 | Out | Overflow flag | ✅ |
| sample_count | 32 | Out | Tổng số sample | ✅ |

**Đã bỏ port `mode_ppg_ecg`** - hệ thống chỉ dùng ECG.

### 3.3 `window_buffer`

| Mục | Giá trị | TT |
|---|---|---|
| Kích thước cửa sổ | 512 mẫu | ✅ |
| Overlap | 50% (bước trượt 256 mẫu) | ✅ |
| Port vào (mẫu, valid) | ❓ | ❓ |
| Port ra (mẫu, địa chỉ/đọc tuần tự, `window_ready`...) | ❓ | ❓ |
| Cách `feature_extraction` đọc dữ liệu (stream hay đọc ngẫu nhiên) | ❓ | ❓ |

### 3.4 `feature_extraction`

| Mục | Giá trị | TT |
|---|---|---|
| Đầu vào | cửa sổ 512 mẫu từ `window_buffer`, ngưỡng `ECG_THRESH` từ CSR | ✅ (ý chung) |
| Đầu ra | 12 feature × 16-bit (mục 4) | ✅ |
| Tín hiệu start/done/valid | start_compute, feature_valid, overflow | ✅ |
| Cách xuất 12 feature | 12 port riêng (f_rms, f_var, ..., f_rr_diff), mỗi port 16-bit | ✅ |

**Port cụ thể** (xem thêm `feature/README.md`):

| Tín hiệu | Rộng | Hướng | Mô tả |
|---|---|---|---|
| clk, rst_n | 1 | In | Clock, reset |
| start_compute | 1 | In | Bắt đầu tính feature |
| **ecg_threshold** | 16 | In | **Ngưỡng R-peak (đổi từ ppg_threshold)** |
| read_enable | 1 | In | Yêu cầu đọc sample |
| sample_addr | 9 | Out | Address gửi tới window_buffer |
| sample_in | 8 | In | Sample từ window_buffer |
| f_rms..f_rr_diff | 16×12 | Out | 12 features |
| feature_valid | 1 | Out | Features ready |
| overflow | 1 | Out | Tràn số |

### 3.5 `ai_classifier` và `mlp_weights_rom`

| Mục | Giá trị | TT |
|---|---|---|
| Đầu vào | 12 feature × 16-bit (đúng thứ tự mục 4) | ✅ |
| Đầu ra | `class_code[1:0]` (mục 5) | ✅ |
| Các bước | Normalization → FC1 + bias → ReLU → FC2 + bias → Argmax | ✅ |
| Tín hiệu điều khiển từ `control_fsm` (start, state, done...) | ❓ | ❓ |
| Cổng đọc ROM | ❓ | ❓ |

### 3.6 `control_fsm`

| Mục | Giá trị | TT |
|---|---|---|
| Trạng thái | 10 trạng thái (IDLE→LOAD→NORMALIZE→FC1→FC1_B→RELU→FC2→FC2_B→ARGMAX→DONE) | ✅ |
| Tín hiệu vào/ra | clk, rst_n, start, feat_valid, apb_enable, fsm_idle, window_en, feature_start, feature_read_en, mlp_start, mlp_valid, uart_send, done, read_addr | ✅ |

### 3.7 `uart_tx`

| Mục | Giá trị | TT |
|---|---|---|
| Baud | chia theo thanh ghi `BAUD` (0x0C), default 437 (cho 115200 @ 50.4 MHz) | ✅ |
| Dữ liệu gửi | kết quả phân loại `class_code[1:0]` | ✅ |
| Định dạng khung | 8N1 (8 data bits, no parity, 1 stop bit), LSB first | ✅ |
| Đích | module BLE/HC-05 | ✅ |

### 3.8 `top_ppg_classifier` (tên file lịch sử, dự án là ECG)

| Mục | Giá trị | TT |
|---|---|---|
| Vai trò | tích hợp toàn bộ hệ thống (SoC) | ✅ |
| System clock | 50.4 MHz | ✅ |
| `sample_rate_div` | 140000 (cho 360 Hz ECG) | ✅ |
| Port ngoài | sys_clk, sys_rst_n, paddr, psel, penable, pwrite, pwdata, prdata, adc_data[7:0], adc_valid, uart_txd, uart_rxd, irq, status_led[3:0] | ✅ |

## 4. 12 feature — thứ tự là hợp đồng giữa `feature` và `ai`

**Không đổi thứ tự index.** Thứ tự này phải khớp với thứ tự lúc huấn luyện (mean, inverse scale, và trọng số FC1 trong `weight.hex`).

| Index | Feature | Định dạng | Mô tả |
|---|---|---|---|
| 0 | f_rms | Signed | Root Mean Square |
| 1 | f_var | Signed | Phương sai |
| 2 | f_peak | Signed | Giá trị đỉnh |
| 3 | f_zc | Unsigned | Số lần cắt không |
| 4 | f_ptp | Signed | Peak-to-Peak |
| 5 | f_crest | Q4.12 | Crest factor |
| 6 | f_half_ratio | Q4.12 | Tỷ lệ mẫu dương |
| 7 | f_max | Signed | Giá trị lớn nhất |
| 8 | f_rr | Unsigned | Khoảng RR hiện tại |
| 9 | f_rr_prev | Unsigned | Khoảng RR trước |
| 10 | f_rr_ratio | Q4.12 | Tỷ số RR |
| 11 | f_rr_diff | Signed | Hiệu RR |

❓ Cần ghi thêm: đơn vị của các feature "Signed/Unsigned" (đếm mẫu hay Q-format nào), cách xử lý tràn/bão hòa, giá trị khi chưa có RR trước đó.

## 5. Kết quả phân loại

**Áp dụng cho bài toán ECG** (đã xác nhận với bộ dữ liệu MIT-BIH Arrhythmia Database 360 Hz):

| `class_code[1:0]` | Ý nghĩa |
|---|---|
| 00 | Normal (bình thường) |
| 01 | Fast (nhịp nhanh, Tachycardia) |
| 10 | Slow (nhịp chậm, Bradycardia) |
| 11 | Abnormal (loạn nhịp, Arrhythmia) |

## 6. Trọng số MLP (`weight.hex`)

- Định dạng: Q4.12, 16-bit hex, tổng 164 từ. ✅
- **Vị trí file: `ai/weights/weight.hex`** (đường dẫn tương đối trong repo, đề xuất thay cho đường dẫn ngoài repo hiện tại). ❓ Xác nhận khi đã chuyển file vào repo.
- ⚠️ **Phải retrain với data 360 Hz** - không thuộc PR này. Người phụ trách AI cập nhật sau.

| Địa chỉ | Nội dung | Số từ |
|---|---|---|
| 0–11 | Mean | 12 |
| 12–23 | Inverse scale | 12 |
| 24–119 | Trọng số FC1 | 96 (8×12) |
| 120–127 | Bias FC1 | 8 |
| 128–159 | Trọng số FC2 | 32 (4×8) |
| 160–163 | Bias FC2 | 4 |

❓ Ghi rõ thứ tự lưu ma trận FC1/FC2 (theo hàng hay theo cột), vì lệch ở đây sẽ cho kết quả sai nhưng không báo lỗi.

## 7. Quy trình đổi interface

1. Mở issue nêu rõ: module nào, port/định dạng nào đổi, vì sao.
2. Người sở hữu cả hai phía đồng ý.
3. Một PR duy nhất sửa: `docs/interfaces.md`, module phát, module nhận, testbench liên quan.
4. CI/`make all` phải pass trước khi merge.

## 8. Nhật ký thay đổi

| Ngày | Thay đổi | Người |
|---|---|---|
| 2026-10-17 | Tạo file từ README hiện tại; các mục ❓ chờ chủ module điền | |
| 2025 | **Cập nhật spec mới**: system clock 100→50.4 MHz, sample rate 500→360 Hz, baud divisor 868→437, version 0x0100→0x0200 | |
| 2025 | **Bỏ tham chiếu PPG**: `ppg_threshold`→`ecg_threshold`, thanh ghi `THRESH`→`ECG_THRESH`, bỏ port `mode_ppg_ecg` | |
| 2025 | Cập nhật chi tiết port cho adc_interface, feature_extraction, control_fsm, uart_tx, top | |
| 2025 | Áp dụng bảng 4 lớp ECG (Normal/Fast/Slow/Abnormal) với MIT-BIH 360 Hz | |
