# ADC Interface

## Module: adc_interface.v

## Chức năng
Nhận dữ liệu từ ADC 8-bit parallel, forward dữ liệu với sample rate configurable.

## Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| DATA_WIDTH | 8 | ADC resolution |

## Ports

### Input
| Port | Width | Description |
|------|-------|-------------|
| clk | 1 | System clock |
| rst_n | 1 | Reset (active low) |
| sample_rate_div | 16 | Clock divider for sample rate |
| mode_ppg_ecg | 1 | 0=PPG, 1=ECG mode |
| adc_data_in | 8 | ADC parallel data |
| adc_data_valid | 1 | Data valid strobe |
| adc_clk | 1 | ADC conversion clock |

### Output
| Port | Width | Description |
|------|-------|-------------|
| sample_out | 8 | Sample to window buffer |
| sample_valid | 1 | Sample valid strobe |
| adc_overflow | 1 | Data overflow indicator |

## Timing
- Sample rate configurable via `sample_rate_div`
- Default: 500 Hz for ECG

## Xem thêm
- Testbench: `tb/tb_adc_interface.sv`
- Interface contract: `docs/interfaces.md`
