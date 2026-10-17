# Feature Extraction

## Module: feature_extraction.v

## Chức năng
Trích xuất 12 features từ 512 ECG samples.

## Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| DATA_IN_WIDTH | 8 | Input sample width |
| DATA_OUT_WIDTH | 16 | Output feature width |
| NUM_SAMPLES | 512 | Samples per window |

## 12 Features (phải giữ thứ tự)

| Index | Feature | Format | Description |
|-------|---------|--------|-------------|
| 0 | f_rms | Signed | Root Mean Square |
| 1 | f_var | Signed | Variance |
| 2 | f_peak | Signed | Peak value |
| 3 | f_zc | Unsigned | Zero crossing count |
| 4 | f_ptp | Signed | Peak-to-Peak |
| 5 | f_crest | Q4.12 | Crest Factor |
| 6 | f_half_ratio | Q4.12 | Positive sample ratio |
| 7 | f_max | Signed | Maximum value |
| 8 | f_rr | Unsigned | Current RR interval |
| 9 | f_rr_prev | Unsigned | Previous RR interval |
| 10 | f_rr_ratio | Q4.12 | RR ratio |
| 11 | f_rr_diff | Signed | RR difference |

**⚠️ Không được đổi thứ tự feature** - phải khớp với thứ tự lúc training (mean, scale, weights).

## Ports

### Input
- clk, rst_n: clock và reset
- start_compute: bắt đầu tính feature
- ppg_threshold: ngưỡng R-peak detection
- read_enable, sample_addr, sample_in: đọc từ window buffer

### Output
- 12 features: f_rms, f_var, ..., f_rr_diff
- feature_valid: features ready
- overflow: tràn số

## Latency
~512 cycles

## Xem thêm
- Testbench: `tb/tb_feature_extraction.sv`
- Interface contract: `docs/interfaces.md`
