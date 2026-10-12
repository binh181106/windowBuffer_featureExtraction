# PPG AI Classifier RTL Design

## Overview
This is the RTL design for a PPG (Photoplethysmography) blood pressure classification system with AI acceleration.

## Project Structure

```
rtl/
├── README.md              # This file
│
├── apb/                   # APB AMBA3 Slave Interface
│   └── apb_slave_if.v    # CSR registers & configuration
│
├── adc/                   # ADC Interface
│   └── adc_interface.v   # 8-bit parallel ADC input
│
├── window/                # Window Buffer
│   └── window_buffer.v   # 512-sample sliding window
│
├── feature/              # Feature Extraction
│   └── feature_extraction.v  # 12 features extraction
│
├── ai/                   # AI Neural Network
│   ├── ai_classifier.v  # MLP 12→8→4 classifier
│   └── mlp_weights_rom.v  # Weights ROM (loads weight.hex)
│
├── control/              # Control FSM
│   └── control_fsm.v    # 10-state master FSM
│
├── uart/                 # UART Interface
│   └── uart_tx.v        # UART transmitter
│
├── top/                  # Top Level
│   └── top_ppg_classifier.v  # Full SoC integration
│
├── tb/                   # Testbenches
│   ├── tb_apb_slave_if.sv
│   ├── tb_adc_interface.sv
│   ├── tb_window_buffer.sv
│   ├── tb_feature_extraction.sv
│   ├── tb_control_fsm.sv
│   ├── tb_uart_tx.sv
│   ├── tb_ai_classifier.sv
│   ├── tb_top_ppg_classifier.sv
│   ├── Makefile
│   └── run_all.sh
│
└── synthesis/            # Synthesis scripts
    └── run_synth.tcl
```

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                    PPG CLASSIFIER SoC                                │
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
│  │ 50% Overlap │                    ▼                              │
│  └─────────────┘           ┌───────────────────────────────────┐  │
│         │                 │        CONTROL FSM (10-state)       │  │
│         ▼                 │  IDLE→LOAD→NORM→FC1→FC1_B→RELU→   │  │
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
│         ▼                           │                              │
│  ┌─────────────┐                    ▼                              │
│  │    UART     │          ┌───────────────────────────────────┐  │
│  │    TX       │◀─────────│      CLASSIFICATION RESULT        │  │
│  │  BLE/HC-05 │          │  00=Normal 01=Fast 10=Slow 11=Ab│  │
│  └─────────────┘          └───────────────────────────────────┘  │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

## Module Hierarchy

```
rtl/
├── apb/
│   └── apb_slave_if.v        # APB AMBA3 slave interface + CSR
│
├── adc/
│   └── adc_interface.v         # 8-bit parallel ADC input
│
├── window/
│   └── window_buffer.v         # 512-sample sliding window
│
├── feature/
│   └── feature_extraction.v    # 12 features extraction
│
├── ai/
│   ├── ai_classifier.v        # MLP Neural Network
│   └── mlp_weights_rom.v      # Weight/Bias ROM
│
├── control/
│   └── control_fsm.v          # 10-state master FSM
│
├── uart/
│   └── uart_tx.v              # UART transmitter
│
└── top/
    └── top_ppg_classifier.v    # Top-level integration
```

## Signal Descriptions

### APB Interface
| Signal | Width | Direction | Description |
|--------|-------|-----------|-------------|
| paddr | 32 | Input | APB address |
| psel | 1 | Input | Peripheral select |
| penable | 1 | Input | APB enable |
| pwrite | 1 | Input | Write enable |
| pwdata | 32 | Input | Write data |
| prdata | 32 | Output | Read data |

### CSR Register Map
| Offset | Register | Description |
|--------|----------|-------------|
| 0x00 | CTRL | Control: enable, start, reset |
| 0x04 | STATUS | Status: busy, done, error |
| 0x08 | THRESH | PPG threshold for RR detection |
| 0x0C | BAUD | UART baud rate divisor |
| 0x10 | RESULT | Classification result |
| 0x14 | VERSION | IP version |
| 0x18 | CONFIG | System configuration |

### Feature Output (12 features × 16-bit)
| Index | Feature | Format | Description |
|-------|---------|--------|-------------|
| 0 | f_rms | Signed | Root Mean Square |
| 1 | f_var | Signed | Variance |
| 2 | f_peak | Signed | Peak value |
| 3 | f_zc | Unsigned | Zero crossing count |
| 4 | f_ptp | Signed | Peak-to-Peak |
| 5 | f_crest | Q4.12 | Crest Factor |
| 6 | f_half_ratio | Q4.12 | Positive sample ratio |
| 7 | f_max | Signed | Maximum value |
| 8 | f_rr | Unsigned | Current RR interval |
| 9 | f_rr_prev | Unsigned | Previous RR interval |
| 10 | f_rr_ratio | Q4.12 | RR ratio |
| 11 | f_rr_diff | Signed | RR difference |

## Classification Output
| class_code[1:0] | Classification |
|------------------|----------------|
| 00 | Normal (Healthy) |
| 01 | Fast (Tachycardia) |
| 10 | Slow (Bradycardia) |
| 11 | Abnormal (Arrhythmia) |

## Timing

- System Clock: 100 MHz
- PPG Sample Rate: 250 Hz
- Feature Extraction: ~512 cycles
- MLP Inference: ~150 cycles
- Total Latency: ~662 cycles (~6.6 μs)

## Resources (Estimated for GW5A-LV25)

- LUT: ~2000
- DFF: ~1500
- BSRAM: 2 blocks (18K)
- DSP: 4 (for MAC operations)

## Running Tests

### Prerequisites
- Icarus Verilog installed (`iverilog` and `vvp` commands)

### Run Individual Tests

```bash
cd rtl/tb

# APB test
make apb

# ADC test
make adc

# Window Buffer test
make window

# Feature Extraction test
make feature

# Control FSM test
make control

# UART TX test
make uart

# AI Classifier test
make ai

# Top-level test
make top
```

### Run All Tests

```bash
cd rtl/tb
make all

# Or use batch script (Windows)
run_all.bat
```

### View Waveforms

After running tests, view VCD files with GTKWave:

```bash
gtkwave tb_top_ppg_classifier.vcd &
```

## Testbench Coverage

| Module | Testbench | Description |
|--------|----------|-------------|
| apb_slave_if | tb_apb_slave_if.sv | CSR read/write, interrupt |
| adc_interface | tb_adc_interface.sv | Data forwarding, overflow |
| window_buffer | tb_window_buffer.sv | 512 samples, 50% overlap |
| feature_extraction | tb_feature_extraction.sv | 12 features, reference model |
| control_fsm | tb_control_fsm.sv | 10-state FSM, timing |
| uart_tx | tb_uart_tx.sv | Serial transmission, framing |
| ai_classifier | tb_ai_classifier.sv | MLP inference, classification |
| top | tb_top_ppg_classifier.sv | Full system integration |

## Weight Loading

Weights are loaded from the hex file generated during training:
- Path: `../AI_FSM_ECG-main/AI_FSM_ECG-main/weight.hex`
- Format: Q4.12 fixed-point (16-bit hex)
- Total: 164 words

Memory Map:
- [0-11]: Mean values (12)
- [12-23]: Inverse Scale (12)
- [24-119]: FC1 Weights (96)
- [120-127]: FC1 Biases (8)
- [128-159]: FC2 Weights (32)
- [160-163]: FC2 Biases (4)
