# UART TX

## Module: uart_tx.v

## Chức năng
UART transmitter gửi kết quả classification đến module BLE (HC-05).
Được trigger bởi `uart_send` từ control_fsm khi đến state DONE.

## Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| CLKS_PER_BIT | 437 | Clocks per bit (115200 @ 50.4 MHz = 50400000/115200 ≈ 437.5) |

## Ports

### Input
| Port | Width | Description |
|------|-------|-------------|
| clk | 1 | System clock |
| rst_n | 1 | Reset (active low) |
| baud_div | 16 | Baud rate divisor (từ APB CSR) |
| tx_data | 8 | Dữ liệu cần gửi |
| tx_start | 1 | Bắt đầu gửi (pulse từ `uart_send`) |
| tx_enable | 1 | Cho phép gửi (CONFIG bit1) |

### Output
| Port | Width | Description |
|------|-------|-------------|
| tx_busy | 1 | Đang gửi |
| tx_done_tick | 1 | Pulse khi gửi xong |
| uart_txd | 1 | UART TX line |

## Frame Format
- 8N1: 8 data bits, no parity, 1 stop bit, LSB first.
- Baud: 115200 mặc định (div 437), nạp được từ APB BAUD register.
- Khung dữ liệu: `{6'b0, class_code}` (2 byte cuối = class_code).

## Xem thêm
- Testbench: `tb/tb_uart_tx.sv`
- Interface contract: `docs/interfaces.md`
