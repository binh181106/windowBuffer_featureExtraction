# Control FSM

## Module: control_fsm.v

## Chức năng
Master FSM điều khiển toàn bộ pipeline classification 10 trạng thái, kèm
handshake với `window_buffer`, `feature_extraction`, `ai_classifier` và
timeout chống deadlock.

> **v3.1 (fix quan trọng):** `next_state` được tính bằng **blocking** trong
> `case(state)`, `state` commit **NBA đúng một lần sau endcase**. Bản v2 đặt
> `state <= next_state;` đặt trước `case` (cả hai đều NBA) → FSM trễ chính nó
> 1 chu kỳ, dao động IDLE↔LOAD mỗi clock, bỏ lỡ mọi pulse 1-chu kỳ
> (`feat_valid`, `mlp_done`, `start`) → không bao giờ có IRQ.
> Chi tiết debug + bằng chứng: `docs/BUGFIX_8_8_top_tb.md`.

## States
```
IDLE → LOAD → NORM → FC1 → FC1_B → RELU → FC2 → FC2_B → ARGMAX → DONE → IDLE
```

| State | Hành động chính |
|-------|-----------------|
| IDLE | Chờ `start && apb_enable` → LOAD. `window_en = apb_enable` (buffer gom mẫu liên tục) |
| LOAD | Chờ `window_ready` → phát `feature_start` (1 cycle; `feat_started` chống re-trigger khi overlap buffer) → chờ `feat_valid` → NORM |
| NORM | Delay 12 cycle (normalize chạy trong ai_classifier) → FC1 |
| FC1 | Phát `mlp_start`, chờ `mlp_done` (kèm `MLP_TIMEOUT = 10000` chống deadlock) → FC1_B |
| FC1_B → RELU → FC2 → FC2_B → ARGMAX | Pass-through (ai_classifier tự chạy FSM nội bộ, control_fsm chỉ giữ chuỗi trạng thái) |
| DONE | `done = 1` (→ APB STATUS + IRQ), `uart_send` pulse; về IDLE khi không còn `start` |

## Ports

### Input
| Port | Width | Description |
|------|-------|-------------|
| clk | 1 | System clock (50.4 MHz) |
| rst_n | 1 | Reset (active low) |
| start | 1 | Bắt đầu classification (pulse từ APB CTRL bit1) |
| feat_valid | 1 | Features ready từ feature_extraction |
| apb_enable | 1 | Enable từ APB CSR (CTRL bit0) |
| window_ready | 1 | Window buffer đầy 512 mẫu (pulse 1 cycle) |
| mlp_done | 1 | ai_classifier xong inference (pulse 1 cycle) |
| soft_reset | 1 | Đưa FSM về IDLE ngay (APB CTRL bit4) |

### Output
| Port | Width | Description |
|------|-------|-------------|
| fsm_idle | 1 | FSM ở IDLE |
| window_en | 1 | Enable window buffer |
| feature_start | 1 | Start feature extraction (pulse) |
| feature_read_en | 1 | Read from window buffer |
| mlp_start | 1 | Start MLP inference |
| mlp_valid | 1 | Features valid for MLP |
| uart_send | 1 | Trigger UART TX |
| done | 1 | Classification complete |
| read_addr | 9 | Address đọc window buffer (v3.1: luôn = 0 — ai_classifier tự đọc features) |
| current_state | 4 | Debug: state hiện tại |
| next_state_debug | 4 | Debug: next state (registered 1 cycle) |

## Timeouts (chống deadlock)

| Constant | Giá trị | Dùng ở |
|----------|---------|--------|
| LOAD_TIMEOUT | 100000000 (28-bit) | LOAD: chờ window_ready + feat_valid |
| MLP_TIMEOUT | 10000 | FC1: chờ mlp_done |

## Xem thêm
- Testbench: `tb/tb_control_fsm.sv`
- Interface contract: `docs/interfaces.md`
- Bug report (v3.1): `docs/BUGFIX_8_8_top_tb.md`
