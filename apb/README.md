# APB Slave Interface

## Module: apb_slave_if.v

## Chức năng
APB AMBA3 slave: cấu hình hệ thống (CSR), đọc trạng thái, phát IRQ khi
classification hoàn tất.

> **v3.0:**
> - `soft_reset`: ghi CTRL bit4 → pulse 1 cycle, tự hạ (đưa các module về IDLE).
> - `start`: ghi CTRL bit1 → pulse 1 cycle, tự hạ.
> - `p_irq = sys_done && irq_en` (level; irq_en = CTRL bit2), reset khi
>   `presetn` thấp.

## Ports

### Input
| Port | Width | Description |
|------|-------|-------------|
| pclk | 1 | APB clock |
| presetn | 1 | APB reset (active low) |
| paddr | 8 | Địa chỉ APB |
| psel | 1 | Peripheral select |
| penable | 1 | APB enable |
| pwrite | 1 | Write enable |
| pwdata | 32 | Dữ liệu ghi |
| sys_busy | 1 | Hệ thống đang chạy (từ FSM) |
| sys_done | 1 | Classification xong (từ FSM) |
| sys_class_code | 2 | Kết quả class (từ ai_classifier) |
| sys_overflow | 1 | Tràn (merge ADC/feature/AI) |

### Output
| Port | Width | Description |
|------|-------|-------------|
| prdata | 32 | Dữ liệu đọc |
| pready | 1 | Ready |
| pslverr | 1 | Slave error |
| p_irq | 1 | Interrupt (`sys_done & irq_en`, v3.0) |
| sys_enable | 1 | Enable hệ thống (CTRL bit0) |
| sys_start | 1 | Start pulse (CTRL bit1, v3.0) |
| ecg_threshold | 16 | Ngưỡng R-peak (THRESH, mặc định 80) |
| baud_div | 16 | UART baud divisor (BAUD, mặc định 437) |
| ble_enable | 1 | Bluetooth enable (CONFIG bit0) |
| uart_enable | 1 | UART enable (CONFIG bit1) |
| soft_reset | 1 | Soft reset pulse (CTRL bit4, v3.0) |

## Register Map

| Offset | Thanh ghi | R/W | Mô tả |
|--------|-----------|-----|-------|
| 0x00 | CTRL | R/W | bit0 `enable`, bit1 `start` (pulse), bit2 `irq_en`, bit4 `soft_reset` (pulse) |
| 0x04 | STATUS | R | bit0 busy, bit1 done, bit3 overflow |
| 0x08 | THRESH | R/W | [15:0] ngưỡng R-peak (mặc định 80) |
| 0x0C | BAUD | R/W | [15:0] baud divisor (mặc định 437 = 115200) |
| 0x10 | RESULT | R | [1:0] class_code (0 Normal, 1 Fast, 2 Slow, 3 Abnormal) |
| 0x14 | VERSION | R | 0x0200 |
| 0x18 | CONFIG | R/W | bit0 BLE, bit1 UART enable |

## Xem thêm
- Testbench: `tb/tb_apb_slave_if.sv` (unit) và `tb/uvm/tb_apb_uvm.sv` (UVM)
- Interface contract: `docs/interfaces.md`
