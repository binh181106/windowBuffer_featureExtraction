# Top Level

## Module: top_ecg_classifier.v

**Lưu ý:** Trước đây tên file là `top_ppg_classifier.v`; đã đổi thành
`top_ecg_classifier.v` cho khớp dự án ECG.

## Chức năng
Tích hợp toàn bộ hệ thống ECG classification SoC ( Gowin GW5A-LV25,
50.4 MHz, 360 Hz).

## Architecture
```
APB → [apb_slave_if] ─┐
                      ├→ [control_fsm v3.1] ─→ [window_buffer] ← [adc_interface]
ADC ─→ [adc_interface] │        │ │ │
                      │        │ │ └→ [ai_classifier] ─done─→ control_fsm (mlp_done)
                      │        └─┘ → [feature_extraction]
                      └ p_irq (done & irq_en)
              control_fsm ─uart_send→ [uart_tx] → BLE
```

> **v3.0 wiring (branch này):**
> - `window_ready` (window_buffer) → control_fsm: trigger feature_start khi
>   cửa sổ đầy (trước đó bỏ hở → feature đọc cửa sổ rỗng).
> - `done` (ai_classifier) → `mlp_done` → control_fsm: handshake FC1
>   (trước đó bỏ hở → FSM không chờ được MLP).
> - `soft_reset` (APB) → control_fsm / ai / feature / window: đưa cả
>   pipeline về IDLE.
> - `clk_locked` hiện tie `1'b1` — **nối tín hiệu lock thật của PLL khi dùng
>   PLL trên board**.

## Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| SYS_SAMPLE_RATE_DIV | 140000 | 50.4 MHz / 140000 = 360 Hz. TB override (vd 20) để sim nhanh |

## Ports

### Clock & Reset
| Port | Width | Description |
|------|-------|-------------|
| sys_clk | 1 | System clock (50.4 MHz) |
| sys_rst_n | 1 | Reset active-low |

### APB (AMBA3)
| Port | Width | Description |
|------|-------|-------------|
| paddr | 32 | Địa chỉ (mục đích dùng 8-bit, tham chiếu docs/interfaces.md) |
| psel / penable / pwrite | 1 | APB handshake |
| pwdata | 32 | Dữ liệu ghi |
| prdata | 32 | Dữ liệu đọc |

### ADC
| Port | Width | Description |
|------|-------|-------------|
| adc_data | 8 | Dữ liệu ECG song song (AD8232) |
| adc_valid | 1 | Data valid strobe |

### UART / Status
| Port | Width | Description |
|------|-------|-------------|
| uart_txd | 1 | TX → BLE (HC-05) |
| uart_rxd | 1 | RX (reserved) |
| irq | 1 | Interrupt (`sys_done & irq_en`) |
| status_led | 4 | bit0 `fsm_idle`, bit1 `window_ready`, bit2 `feature_valid`, bit3 `sys_done` |

## Port mapping FPGA
Xem `docs/step1_port_mapping.md` (PL-USB Gowin).

## Xem thêm
- Testbench E2E: `tb/tb_top_ecg_classifier.sv` (8/8 PASSED trên branch này)
- Archive cũ: `sim/tb_top_ecg.sv`
- Interface contract: `docs/interfaces.md`
