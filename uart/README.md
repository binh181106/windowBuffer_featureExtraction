# UART TX

## Module: uart_tx.v

## Chức năng
UART transmitter gửi classification result đến BLE module (HC-05).

## Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| CLKS_PER_BIT | 868 | Clocks per bit (115200 @ 100MHz) |

## Ports

### Input
- clk, rst_n: clock và reset
- baud_div: baud rate divisor (từ CSR)
- tx_data: data cần gửi
- tx_start: bắt đầu gửi
- tx_enable: cho phép gửi

### Output
- tx_busy: đang gửi
- tx_done_tick: pulse khi gửi xong
- uart_txd: UART TX line

## Frame Format
- 8N1: 8 data bits, no parity, 1 stop bit
- Baud: 115200 (default)

## Xem thêm
- Testbench: `tb/tb_uart_tx.sv`
- Interface contract: `docs/interfaces.md`
