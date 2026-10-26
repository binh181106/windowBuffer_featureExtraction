# Window Buffer

## Module: window_buffer.v

## Chức năng
Circular buffer 512 mẫu ECG với 50% overlap (mỗi 256 mẫu mới một cửa sổ).
Đảm bảo R-peak (~100 ms ≈ 36 mẫu @ 360 Hz) không bị miss giữa hai cửa sổ.

> **v3.0 (fix trigger + read):**
> - `window_ready` phát theo **tổng số mẫu đã ghi** (`samples_collected`):
>   `total ≥ 512 && (total − 512) % 256 == 0` → pulse 1 cycle tại total =
>   512, 768, 1024, ... Bản cũ dùng `sample_cnt % 256 == 0` nhưng
>   `sample_cnt` bão hòa ở 511 → trigger bắn liên tục mọi cycle.
> - `frame_out` đọc **combinational** `ram[(oldest + read_addr) % 512]`
>   (bản cũ register read lệch 1 mẫu).
> - `soft_reset` → xóa write_ptr / sample_cnt / window_ready.

## Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| DATA_WIDTH | 8 | ADC resolution |
| WINDOW_SIZE | 512 | Số mẫu mỗi cửa sổ |
| OVERLAP | 256 | 50% overlap |
| BASELINE_OFFSET | 169 | AD8232 baseline (~169–170 @ 0 V) |

## Ports

### Input
| Port | Width | Description |
|------|-------|-------------|
| clk | 1 | System clock |
| rst_n | 1 | Reset (active low) |
| enable | 1 | Enable buffering (từ control_fsm `window_en`) |
| soft_reset | 1 | Soft reset → về trạng thái rỗng |
| sample_in | 8 | Mẫu từ ADC (đã baseline-corrected trong module) |
| sample_valid | 1 | Strobe mẫu hợp lệ |
| read_en | 1 | Read enable |
| read_addr | 9 | Địa chỉ đọc (0–511) |

### Output
| Port | Width | Description |
|------|-------|-------------|
| frame_out | 8 | Mẫu đọc (combinational, baseline-corrected) |
| window_ready | 1 | Cửa sổ đầy → phát pulse (mỗi 256 mẫu sau cửa sổ đầu) |
| ready_bank | 1 | Alias của window_ready (backward compat) |
| samples_collected | 32 | Tổng số mẫu đã ghi (không bão hòa) |
| sample_cnt | 9 | Debug (bão hòa ở 511) |

## Timing (ECG 360 Hz)
- 1 mẫu = 2.778 ms → 512 mẫu = 1.422 s, cửa sổ mới mỗi 711 ms (256 mẫu).

## Xem thêm
- Testbench: `tb/tb_window_buffer.sv`
- Interface contract: `docs/interfaces.md`
