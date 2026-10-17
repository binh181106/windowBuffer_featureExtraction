# APB Slave Interface

## Module: apb_slave_if.v

## Chức năng
APB AMBA3 slave interface cho việc cấu hình hệ thống và đọc trạng thái.

## Ports

### Input
| Port | Width | Description |
|------|-------|-------------|
| pclk | 1 | APB clock |
| presetn | 1 | APB reset (active low) |
| paddr | 8 | APB address |
| psel | 1 | Peripheral select |
| penable | 1 | APB enable |
| pwrite | 1 | Write enable |
| pwdata | 32 | Write data |

### Output
| Port | Width | Description |
|------|-------|-------------|
| prdata | 32 | Read data |
| pready | 1 | Ready signal |
| pslverr | 1 | Slave error |
| sys_enable | 1 | System enable |
| sys_start | 1 | Start pulse |
| ppg_threshold | 16 | PPG/ECG threshold |
| baud_div | 16 | UART baud divisor |
| ble_enable | 1 | Bluetooth enable |
| uart_enable | 1 | UART enable |
| soft_reset | 1 | Soft reset |

## Register Map

| Offset | Register | Description |
|--------|----------|-------------|
| 0x00 | CTRL | bit[0]=enable, bit[1]=start, bit[2]=irq_en, bit[4]=soft_reset |
| 0x04 | STATUS | bit[0]=busy, bit[1]=done, bit[2]=error, bit[3]=overflow |
| 0x08 | THRESH | Threshold for R-peak detection |
| 0x0C | BAUD | UART baud divisor |
| 0x10 | RESULT | Classification result |
| 0x14 | VERSION | IP version (0x0100) |
| 0x18 | CONFIG | bit[0]=ble_en, bit[1]=uart_en |

## Xem thêm
- Testbench: `tb/tb_apb_slave_if.sv`
- Interface contract: `docs/interfaces.md`
