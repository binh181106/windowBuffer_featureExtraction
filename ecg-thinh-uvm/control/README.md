# Control FSM

## Module: control_fsm.v

## Chức năng
Master FSM điều khiển toàn bộ pipeline classification 10 states.

## States
```
IDLE → LOAD → NORMALIZE → FC1 → FC1_B → RELU → FC2 → FC2_B → ARGMAX → DONE → IDLE
```

| State | Description |
|-------|-------------|
| IDLE | Chờ start |
| LOAD | Load window buffer |
| NORMALIZE | Normalize features |
| FC1 | Layer 1 multiply-accumulate |
| FC1_B | Add bias layer 1 |
| RELU | ReLU activation |
| FC2 | Layer 2 multiply-accumulate |
| FC2_B | Add bias layer 2 |
| ARGMAX | Find max logit |
| DONE | Classification complete |

## Ports

### Input
- clk, rst_n: clock và reset
- start: bắt đầu classification
- feat_valid: features ready
- apb_enable: enable từ CSR

### Output
- fsm_idle, window_en, feature_start, feature_read_en
- mlp_start, mlp_valid
- uart_send, done
- read_addr: address đọc window buffer
- current_state, next_state_debug

## Xem thêm
- Testbench: `tb/tb_control_fsm.sv`
- Interface contract: `docs/interfaces.md`
