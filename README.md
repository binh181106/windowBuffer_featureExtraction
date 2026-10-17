# ECG AI Classifier RTL Design

## ⚠️ QUAN TRỌNG: ĐỌC README TRƯỚC KHI SỬA FILE

**Mỗi module folder có README.md riêng.** AI agent phải đọc README.md trong folder trước khi sửa bất kỳ file nào.

```
AI Agent phải làm theo quy trình:
1. Đọc docs/interfaces.md (nguồn sự thật về interface)
2. Đọc README.md trong folder chứa module cần sửa
3. Đọc testbench tương ứng trong tb/
4. Mới được sửa code
```

## Overview

This is the RTL design for an ECG (Electrocardiogram) classification system with AI acceleration.
- Sample Rate: 500 Hz
- Window Size: 512 samples (1.024 seconds per window)
- 50% overlap for R-peak detection

## Project Structure

```
rtl/
├── README.md              # This file - MUST READ FIRST
│
├── apb/                   # APB AMBA3 Slave Interface
│   └── README.md         # Module documentation
│   └── apb_slave_if.v   # CSR registers & configuration
│
├── adc/                   # ADC Interface
│   └── README.md
│   └── adc_interface.v   # 8-bit parallel ADC input
│
├── window/                # Window Buffer
│   └── README.md
│   └── window_buffer.v   # 512-sample sliding window, 50% overlap
│
├── feature/              # Feature Extraction
│   └── README.md
│   └── feature_extraction.v  # 12 features extraction
│
├── ai/                   # AI Neural Network
│   └── README.md
│   ├── ai_classifier.v  # MLP 12→8→4 classifier
│   ├── mlp_weights_rom.v  # Weights ROM
│   └── weights/          # Model weights
│
├── control/              # Control FSM
│   └── README.md
│   └── control_fsm.v    # 10-state master FSM
│
├── uart/                 # UART Interface
│   └── README.md
│   └── uart_tx.v        # UART transmitter
│
├── top/                  # Top Level
│   └── README.md
│   └── top_ppg_classifier.v  # Full SoC integration
│
├── tb/                   # Testbenches
│   └── Makefile
│
├── synthesis/            # Synthesis scripts
│   └── README.md
│
└── docs/                # Documentation
    └── interfaces.md    # Interface contract (NGUỒN SỰ THẬT)
```

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                    ECG CLASSIFIER SoC                                │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  ┌─────────────┐    ┌──────────────────────────────────────────┐  │
│  │    ADC      │    │           APB SLAVE INTERFACE             │  │
│  │ 8-bit      │───▶│  • CSR Registers (CTRL, STATUS, etc.)    │  │
│  │ Parallel    │    │  • APB AMBA3 Protocol                     │  │
│  └─────────────┘    │  • Interrupt Generation                   │  │
│         │           └──────────────────────────────────────────┘  │
│         ▼                           │                              │
│  ┌─────────────┐                    │                              │
│  │   WINDOW    │                    │ Config                       │
│  │   BUFFER    │────────────────────┼───────────────────────────▶  │
│  │ 512 samples │                    │                              │
│  │ 50% Overlap│                    │                              │
│  └─────────────┘                    │                              │
│         │                           ▼                              │
│         │                  ┌───────────────────────────────────┐  │
│         │                  │        CONTROL FSM (10-state)       │  │
│         ▼                  │  IDLE→LOAD→NORM→FC1→FC1_B→RELU→   │  │
│  ┌─────────────┐          │  FC2→FC2_B→ARGMAX→DONE            │  │
│  │  FEATURE    │          └───────────────────────────────────┘  │
│  │ EXTRACTION │                    │                              │
│  │  12 feats  │                    ▼                              │
│  │ 16-bit     │          ┌───────────────────────────────────┐  │
│  └─────────────┘          │          AI CLASSIFIER             │  │
│         │                 │     MLP Neural Network 12→8→4     │  │
│         ▼                 │     • Normalization                │  │
│  ┌─────────────┐          │     • FC1 + Bias                  │  │
│  │     MLP     │          │     • ReLU Activation              │  │
│  │   12→8→4   │          │     • FC2 + Bias                  │  │
│  └─────────────┘          │     • Argmax Output               │  │
│         │                 └───────────────────────────────────┘  │
│         │                           │                              │
│         ▼                           ▼                              │
│  ┌─────────────┐          ┌───────────────────────────────────┐  │
│  │    UART     │          │      CLASSIFICATION RESULT          │  │
│  │    TX       │◀─────────│  00=Normal 01=Fast 10=Slow 11=Ab│  │
│  └─────────────┘          └───────────────────────────────────┘  │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

## Quy Tắc Bắt Buộc Cho AI Agent

### Trước Khi Sửa Bất Kỳ File Nào

1. **Đọc `docs/interfaces.md`** - Nguồn sự thật duy nhất về interface
2. **Đọc README.md trong folder chứa module** - Hiểu contract của module đó
3. **Đọc testbench trong `tb/`** - Hiểu cách test module đó

### Không Được Phép

- Đổi tên port, độ rộng bit, thứ tự feature mà không sửa `docs/interfaces.md`
- Sửa file ngoài phạm vi được giao (xem AGENTS.md)
- Thay đổi weight file (`weight.hex`)
- "Sửa cho testbench pass" bằng cách yếu testbench

## Running Tests

```bash
cd rtl/tb

# Run all tests
make all

# Or run individual test
make apb
make adc
make window
make feature
make control
make uart
make ai
make top
```

## Tài Liệu Tham Khảo

| File | Mô tả |
|------|--------|
| `docs/interfaces.md` | Interface contract (NGUỒN SỰ THẬT) |
| `AGENTS.md` | Quy tắc cho AI agent |
| Module README trong từng folder | Chi tiết từng module |

## Classification Output
| class_code[1:0] | Classification |
|------------------|----------------|
| 00 | Normal (Healthy) |
| 01 | Fast (Tachycardia) |
| 10 | Slow (Bradycardia) |
| 11 | Abnormal (Arrhythmia) |

## Timing

- System Clock: 100 MHz
- ECG Sample Rate: 500 Hz
- Window: 512 samples = 1.024s
- Overlap: 256 samples = 512ms
- Feature Extraction: ~512 cycles
- MLP Inference: ~150 cycles
- Total Latency: ~662 cycles (~6.6 μs)
