# Testbenches

## Cấu trúc
Mỗi module có testbench riêng trong folder này.

## Danh sách Testbench

| Testbench | Module | Description |
|-----------|--------|-------------|
| tb_apb_slave_if.sv | apb_slave_if | CSR read/write, interrupt |
| tb_adc_interface.sv | adc_interface | Data forwarding, overflow |
| tb_window_buffer.sv | window_buffer | 512 samples, 50% overlap |
| tb_feature_extraction.sv | feature_extraction | 12 features extraction |
| tb_control_fsm.sv | control_fsm | 10-state FSM |
| tb_uart_tx.sv | uart_tx | Serial transmission |
| tb_ai_classifier.sv | ai_classifier | MLP inference |
| tb_top_ppg_classifier.sv | top_ppg_classifier | Full system |

## Chạy tests

```bash
cd tb
make apb
make adc
make window
make feature
make control
make uart
make ai
make top
make all       # chạy tất cả
```

## Công cụ
- Icarus Verilog (`iverilog`, `vvp`)
- GTKWave để xem VCD

## Xem thêm
- Interface contract: `docs/interfaces.md`
- AGENTS.md cho quy tắc test
