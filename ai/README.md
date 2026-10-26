# AI Classifier (MLP)

## Modules
- `ai_classifier.v`: MLP Neural Network 12→8→4 (Q4.12 fixed-point)
- `mlp_weights_rom.v`: Weights ROM (164 từ × 16-bit)

## Chức năng
Phân loại ECG bằng MLP:
- Input: 12 features × 16-bit (Q4.12)
- Hidden: 8 neurons, ReLU
- Output: 4 classes (argmax, tie-break giữ index thấp)

## Pipeline
```
12 features → Normalize → FC1 + bias → ReLU → FC2 + bias → Argmax
```

> **v3.0:**
> - Port `soft_reset` (đưa FSM nội bộ về IDLE).
> - Saturate MAC + cờ `overflow`.
> - `done` pulse 1 cycle khi inference xong → top nối ra `mlp_done` cho
>   control_fsm (handshake chống deadlock).
> - `class_code` reset về 0.
> - Argmax tie-break giữ index thấp (đã đúng trong RTL, giữ nguyên).

## Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| FEATURE_WIDTH | 16 | Feature width |
| HIDDEN_NEURONS | 8 | Hidden layer size |
| OUTPUT_NEURONS | 4 | Số classes |

## Ports

### Input
| Port | Width | Description |
|------|-------|-------------|
| clk, rst_n | 1 | Clock và reset |
| soft_reset | 1 | Đưa FSM MLP về IDLE (v3.0) |
| start | 1 | Start inference (từ control_fsm `mlp_start`) |
| enable | 1 | Module enable (từ `apb_enable`) |
| features[0:11] | 16 × 12 | 12 features signed Q4.12 |

### Output
| Port | Width | Description |
|------|-------|-------------|
| class_code | 2 | Kết quả: 00 Normal / 01 Fast / 10 Slow / 11 Abnormal |
| done | 1 | Inference complete (pulse; top nối ra mlp_done) |
| overflow | 1 | Tràn phát hiện (v3.0) |
| fc1_out[0:7] | 32 × 8 | Debug: out FC1 trước ReLU |
| fc2_out[0:3] | 32 × 4 | Debug: out FC2 |

## Weights Format
- File: `weights/weight.hex`
- Format: Q4.12, 16-bit hex, tổng 164 từ.
- **Placeholder hiện tại — phải retrain với data 360 Hz trước khi chạy trên board.**

### Memory Map
| Address | Content | Words |
|---------|---------|-------|
| 0–11 | Mean values | 12 |
| 12–23 | Inverse Scale | 12 |
| 24–119 | FC1 Weights (8×12) | 96 |
| 120–127 | FC1 Biases | 8 |
| 128–159 | FC2 Weights (4×8) | 32 |
| 160–163 | FC2 Biases | 4 |

## ⚠️ Quan trọng
**KHÔNG tự ý thay đổi `weight.hex`** — file này do người phụ trách AI cập nhật,
kèm ghi chú nguồn huấn luyện (AGENTS.md §4.6).

## Latency
~161 cycles cho một lần inference (FSM nội bộ: LOAD→NORM→FC1→…→ARGMAX).

## Xem thêm
- Testbench: `tb/tb_ai_classifier.sv`
- Interface contract: `docs/interfaces.md`
