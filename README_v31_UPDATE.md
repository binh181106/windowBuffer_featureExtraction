# v3.1 — ECG Classifier (cập nhật full project trên branch newest-update)

> File này bổ sung cho `README.md` gốc (quy tắc đọc-trước-khi-sửa của team giữ nguyên).
> Nội dung: toàn bộ dự án đã nâng lên **v3.1**, top testbench **8/8 PASSED**, kèm fix quan trọng
> trong `control/control_fsm.v`. Chi tiết debug: [`docs/BUGFIX_8_8_top_tb.md`](docs/BUGFIX_8_8_top_tb.md).

## Thay đổi so với baseline (main)

| Phần | Trước (main) | Sau (branch này) |
|---|---|---|
| `control/control_fsm.v` | FSM 2-giai NBA (bug timing) | **v3.1**: `next_state` blocking, commit `state` 1 lần; ports mới `window_ready`, `mlp_done`, `soft_reset`; timeout chống deadlock |
| `window/window_buffer.v` | trigger overlap theo `sample_cnt` (bug) | theo tổng mẫu đã ghi: `total≥512 && (total−512)%256==0`; read combinational |
| `feature/feature_extraction.v` | alignment mẫu/địa chỉ lệch | cùng cạnh, `read_en` strobe, signed RR, guard rr_prev=0 |
| `ai/ai_classifier.v` | — | `soft_reset`, saturate MAC + overflow, argmax tie-break giữ index thấp, class_code reset |
| `apb/apb_slave_if.v` | — | `soft_reset` pulse (bit4 CTRL), IRQ = done & irq_en |
| `adc/adc_interface.v` | rate gate lệch 1 clock | chu kỳ đúng = `sample_rate_div` (360 Hz) |
| `top/top_ecg_classifier.v` | wiring cũ | wire `window_ready`/`mlp_done`/`soft_reset` |
| Renames | `sim/tb_top.sv`, `tb/tb_top_ppg_classifier.sv` | `sim/tb_top_ecg.sv`, `tb/tb_top_ecg_classifier.sv` (đúng như interfaces.md đã tuyên bố) |

## Từng phần — chức năng & điểm chính

1. **`adc/`** — latch 8-bit ECG (AD8232) + rate gate: mỗi `sample_rate_div` clock phát `sample_valid` (mặc định 140000 @ 50.4 MHz = 360 Hz; TB override = 20 để sim nhanh).
2. **`window/`** — circular buffer 512×8, baseline subtract (~169), `window_ready` pulse mỗi 256 mẫu overlap; `frame_out` combinational.
3. **`feature/`** — 12 features × 16-bit (Q4.12): RMS, Var, Peak, ZC, PTP, Crest, Half-ratio, Max, RR, RR-prev, RR-ratio, RR-diff.
4. **`ai/`** — MLP 12→8→4 fixed-point Q4.12, FSM nội bộ ~161 cycle, `done` pulse; `mlp_weights_rom` 164 từ × 16-bit (**placeholder — cần retrain data 360 Hz**).
5. **`control/` (v3.1)** — FSM 10 trạng thái; handshake `window_ready`/`feat_valid`/`mlp_done` kèm timeout; `soft_reset` về IDLE. Xem bugfix report.
6. **`apb/`** — CSR map: CTRL 0x00 (en/start/soft_reset/irq_en), STATUS 0x04, THRESH 0x08, BAUD 0x0C, RESULT 0x10, VERSION 0x14, CONFIG 0x18.
7. **`uart/`** — TX 8N1 115200 (`CLKS_PER_BIT=437`), khung `{6'b0, class_code}`.
8. **`top/`** — wire tất cả + ports PL-USB (xem `docs/step1_port_mapping.md`).
9. **`tb/`** — unit TB mỗi module + `tb_top_ecg_classifier.sv` (E2E 8 tests) + UVM env APB (`tb/uvm/`). Chạy: `cd tb && make top` (Icarus) hoặc lệnh Questa bên dưới.

## Chạy test (Questa 25.1, Windows — kết quả đã verify ở branch này)

```bat
cd tb
vlog -sv -mfcu -work f_top ..\apb\apb_slave_if.v ..\adc\adc_interface.v ..\window\window_buffer.v ^
     ..\feature\feature_extraction.v ..\ai\ai_classifier.v ..\ai\mlp_weights_rom.v ^
     ..\control\control_fsm.v ..\uart\uart_tx.v ..\top\top_ecg_classifier.v tb_top_ecg_classifier.sv
vsim -c -work f_top tb_top_ecg_classifier -do "run -all; quit -f"
```
Kết quả: `Test Summary: 8/8 PASSED`, `Interrupt received!`, `class_code = 00` (pipeline OK;
weight ROM placeholder nên không cam kết giá trị ML).

## Việc còn lại (ngoài scope branch này)

- [ ] retrain `mlp_weights_rom.hex` với data 360 Hz (164 từ × 16-bit)
- [ ] nối `clk_locked` thật khi dùng PLL (hiện tie 1 trong top)
- [ ] hoàn thành mục bit-map CTRL/STATUS/CONFIG đang ❓ trong `docs/interfaces.md`
- [ ] synthesis Gowin + port mapping PL-USB (`docs/step1_port_mapping.md`)
