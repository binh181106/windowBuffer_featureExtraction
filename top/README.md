# Top Level

## Module: top_ecg_classifier.v

**Lưu ý:** Trước đây tên file là `top_ppg_classifier.v`; đã đổi thành `top_ecg_classifier.v` cho khớp với dự án ECG.

## Chức năng
Tích hợp toàn bộ hệ thống ECG classification SoC.

## Architecture
```
APB → [APB Slave] → [Control FSM]
ADC → [Window Buffer] → [Feature Extraction] → [AI Classifier] → [UART TX]
```

## Ports

### Clock & Reset
- sys_clk: 50.4 MHz system clock
- sys_rst_n: active-low reset

### APB Interface
- paddr[31:0], psel, penable, pwrite, pwdata[31:0]
- prdata[31:0]

### ADC Interface
- adc_data[7:0]: 8-bit parallel ADC data
- adc_valid: data valid strobe

### UART Interface
- uart_txd: TX to BLE/HC-05
- uart_rxd: RX (reserved)

### Status
- irq: interrupt request
- status_led[3:0]: debug LEDs

## Sample Rate
- Default: 360 Hz (ECG) — `sample_rate_div` = 140000
- Configurable via `sample_rate_div` (18-bit)

## Xem thêm
- Testbench: `tb/tb_top_ecg_classifier.sv`
- Interface contract: `docs/interfaces.md`
