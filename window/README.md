# Window Buffer

## Module: window_buffer.v

## Chức năng
Collect 512 ECG samples với 50% overlap. Đảm bảo R-peaks không bị miss.

## Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| DATA_WIDTH | 8 | ADC resolution |
| WINDOW_SIZE | 512 | Samples per window |
| OVERLAP | 256 | 50% overlap |

## Ports

### Input
| Port | Width | Description |
|------|-------|-------------|
| clk | 1 | System clock |
| rst_n | 1 | Reset |
| enable | 1 | Enable buffering |
| soft_reset | 1 | Soft reset |
| sample_in | 8 | Sample from ADC |
| sample_valid | 1 | Sample valid strobe |
| read_en | 1 | Read enable |
| read_addr | 9 | Read address (0-511) |

### Output
| Port | Width | Description |
|------|-------|-------------|
| frame_out | 8 | Sample output |
| window_ready | 1 | Window full, ready to process |
| samples_collected | 32 | Total samples collected |
| ready_bank | 1 | Which bank is ready |

## Timing (ECG 360 Hz)
- 1 sample = 2.778ms
- 512 samples = 1.422s
- Overlap 256 = 711ms
- New window mỗi 711ms

## Xem thêm
- Testbench: `tb/tb_window_buffer.sv`
- Interface contract: `docs/interfaces.md`
