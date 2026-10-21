# ADC Interface

## Module: adc_interface.v

## Chức năng
Nhận dữ liệu từ ADC 8-bit parallel, forward dữ liệu với sample rate configurable.

## Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| DATA_WIDTH | 8 | ADC resolution |
| DIV_WIDTH | 18 | Sample rate divider width (140000 cần 18 bit) |

## Ports

### Input
| Port | Width | Description |
|------|-------|-------------|
| clk | 1 | System clock (50.4 MHz) |
| rst_n | 1 | Reset (active low) |
| sample_rate_div | 18 | Clock divider for sample rate |
| adc_data_in | 8 | ADC parallel data |
| adc_data_valid | 1 | Data valid strobe |
| adc_clk | 1 | ADC conversion clock |

### Output
| Port | Width | Description |
|------|-------|-------------|
| sample_out | 8 | Sample to window buffer |
| sample_valid | 1 | Sample valid strobe |
| adc_overflow | 1 | Data overflow indicator |
| sample_count | 32 | Tổng số sample đã gửi |

## Timing
- Sample rate configurable via `sample_rate_div`
- Default: 360 Hz cho ECG @ 50.4 MHz (div = 140000)

## Xem thêm
- Testbench: `tb/tb_adc_interface.sv`
- Interface contract: `docs/interfaces.md`
