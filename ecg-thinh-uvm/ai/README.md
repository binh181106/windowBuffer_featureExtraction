# AI Classifier (MLP)

## Modules
- `ai_classifier.v`: MLP Neural Network 12→8→4
- `mlp_weights_rom.v`: Weights ROM

## Chức năng
Phân loại ECG sử dụng MLP (Multi-Layer Perceptron):
- Input: 12 features × 16-bit
- Hidden: 8 neurons với ReLU
- Output: 4 classes (argmax)

## Pipeline
```
12 features → Normalize → FC1 + bias → ReLU → FC2 + bias → Argmax
```

## Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| FEATURE_WIDTH | 16 | Feature width |
| HIDDEN_NEURONS | 8 | Hidden layer size |
| OUTPUT_NEURONS | 4 | Output classes |

## Weights Format
- File: `weights/weight.hex`
- Format: Q4.12, 16-bit hex
- Total: 164 words

### Memory Map
| Address | Content | Words |
|---------|---------|-------|
| 0-11 | Mean values | 12 |
| 12-23 | Inverse Scale | 12 |
| 24-119 | FC1 Weights (8×12) | 96 |
| 120-127 | FC1 Biases | 8 |
| 128-159 | FC2 Weights (4×8) | 32 |
| 160-163 | FC2 Biases | 4 |

## Classification Output
| class_code[1:0] | Class |
|------------------|-------|
| 00 | Normal |
| 01 | Fast (Tachycardia) |
| 10 | Slow (Bradycardia) |
| 11 | Abnormal (Arrhythmia) |

## ⚠️ Quan trọng
**KHÔNG tự ý thay đổi `weight.hex`** - File này do người phụ trách AI cập nhật, kèm ghi chú nguồn huấn luyện.

## Latency
~150 cycles

## Xem thêm
- Testbench: `tb/tb_ai_classifier.sv`
- Interface contract: `docs/interfaces.md`
