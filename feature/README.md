# Feature Extraction

## Module: feature_extraction.v

## Chức năng
Trích xuất 12 features thống kê từ 512 mẫu ECG (đọc qua `read_en` strobe
+ `sample_addr`, lấy từ window buffer).

> **v3.0 (fix alignment + RR):**
> - Sample/địa chỉ **cùng cạnh**: chu kỳ ACCUMULATE cnt=k tiêu thụ mẫu có
>   địa chỉ k; `sample_addr` phát ra cnt+1 để chu kỳ sau có mẫu cnt+1.
>   (Bản cũ lệch pha → tính features trên sai cửa sổ.)
> - Port `read_en` ra window buffer (assert trong ACCUMULATE), `soft_reset`
>   đưa về IDLE.
> - Guard `rr_previous = 0` → `f_rr_ratio = 4096` (1.0 Q4.12), so sánh
>   RR signed/unsigned đúng kiểu.
> - Công thức variance **giữ nguyên RTL gốc** (quyết định owner: golden
>   model mirror bit-exact; sửa công thức → phải retrain AI).

## Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| DATA_IN_WIDTH | 8 | Input sample width |
| DATA_OUT_WIDTH | 16 | Output feature width |
| NUM_SAMPLES | 512 | Số mẫu mỗi cửa sổ |

## 12 Features (phải giữ nguyên thứ tự)

| Index | Port | Format | Description |
|-------|------|--------|-------------|
| 0 | f_rms | Signed | RMS (`sum_square >> 9`, truncation theo RTL gốc) |
| 1 | f_var | Signed | Variance (công thức gốc, golden bit-exact) |
| 2 | f_peak | Signed | Đỉnh cao nhất |
| 3 | f_zc | Unsigned | Số lần cắt zero |
| 4 | f_ptp | Signed | Peak-to-peak |
| 5 | f_crest | Q4.12 | Crest factor (guard divide-by-zero) |
| 6 | f_half_ratio | Q4.12 | Tỉ lệ mẫu dương |
| 7 | f_max | Signed | Giá trị max |
| 8 | f_rr | Unsigned | RR interval hiện tại |
| 9 | f_rr_prev | Unsigned | RR trước |
| 10 | f_rr_ratio | Q4.12 | RR/RR_prev (guard rr_prev=0 → 4096) |
| 11 | f_rr_diff | Signed | RR − RR_prev |

**⚠️ Không đổi thứ tự feature** — phải khớp thứ tự lúc training
(mean, scale, weights trong `mlp_weights_rom`).

## Ports

### Input
| Port | Width | Description |
|------|-------|-------------|
| clk, rst_n | 1 | Clock và reset |
| soft_reset | 1 | Đưa về IDLE (v3.0) |
| start_compute | 1 | Bắt đầu tính features |
| ecg_threshold | 16 | Ngưỡng R-peak cho RR detection (từ APB THRESH) |
| read_enable | 1 | Request mẫu từ buffer |
| sample_in | 8 | Mẫu 8-bit từ window buffer |

### Output
| Port | Width | Description |
|------|-------|-------------|
| sample_addr | 9 | Địa chỉ đọc buffer (phát cnt+1, v3.0) |
| read_en | 1 | Read strobe ra buffer (v3.0) |
| f_rms … f_rr_diff | 16 × 12 | 12 features (bảng trên) |
| feature_valid | 1 | Features ready (pulse 1 cycle) |
| overflow | 1 | Tràn khi tính |

## Latency
~512 cycles (ACCUMULATE từng mẫu) + tính các ratio.

## Xem thêm
- Testbench: `tb/tb_feature_extraction.sv`
- Interface contract: `docs/interfaces.md`
