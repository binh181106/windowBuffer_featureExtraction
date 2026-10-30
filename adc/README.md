# ADC Interface

## Module: adc_interface.v

## Chức năng
Nhận dữ liệu ECG từ ADC 8-bit song song (AD8232), rate-gate về 360 Hz và
forward mẫu cho window buffer.

> **v3.0 (fix rate gate):** `rate_timer` tick đúng mỗi `sample_rate_div`
> clock → `sample_valid` phát 1 cycle mỗi chu kỳ. Bản cũ dùng điều kiện
> `>= div` thay `>= (div-1)` nên chu kỳ lệch 140001 clock (không đúng
> 140000). `adc_overflow` merge vào `sys_overflow`.

## Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| DATA_WIDTH | 8 | Độ phân giải ADC |
| DIV_WIDTH | 18 | Width bộ chia (140000 cần 18 bit) |

## Ports

### Input
| Port | Width | Description |
|------|-------|-------------|
| clk | 1 | System clock (50.4 MHz) |
| rst_n | 1 | Reset (active low) |
| sample_rate_div | 18 | Bộ chia clock cho sample rate |
| adc_data_in | 8 | Dữ liệu ADC song song |
| adc_data_valid | 1 | Data valid strobe (từ ADC) |
| adc_clk | 1 | Clock chuyển đổi của ADC |

### Output
| Port | Width | Description |
|------|-------|-------------|
| sample_out | 8 | Mẫu gửi window buffer |
| sample_valid | 1 | Strobe mẫu hợp lệ (1 cycle mỗi 360 Hz) |
| adc_overflow | 1 | Tràn dữ liệu (data đến khi chưa kịp nhả mẫu) |
| sample_count | 32 | Tổng số mẫu đã gửi |

## Timing (ECG 360 Hz)
- Sample rate = `50400000 / sample_rate_div`.
- Mặc định `sample_rate_div = 140000` → 360 Hz.
- Trong sim, top override `SYS_SAMPLE_RATE_DIV = 20` để chạy nhanh.

## Xem thêm
- Testbench: `tb/tb_adc_interface.sv`
- Interface contract: `docs/interfaces.md`
