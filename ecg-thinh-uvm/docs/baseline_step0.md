# Baseline BƯỚC 0 — ECG Classifier (chưa sửa, trước mọi thay đổi)

- Branch: `feature/full-system-integration-v3` (tạo mới từ `master`)
- Simulator: **Questa/ModelSim 25.1** (`H:/altera/25.1std/questa_fse/win64/vlog`+`vsim`, UVM 1.2 có sẵn).
- **Icarus (iverilog/vvp): KHÔNG có trên máy** (PATH trỏ `H:\iverilog` nhưng thư mục không tồn tại).
- `tb/work/*`, `tb/*.vcd`, `*.vvp`, `transcript` là artifact sim cũ (chưa commit).
- Ghi chú git: file trỏ worktree cũ `ecg-thinh-uvm/.git` (chỉ trỏ repo cha không còn tồn tại
  `H:/IC Design/Code/ECG/windowBuffer_featureExtraction/.git`) đã **đổi tên** thành
  `.git.stale-worktree-pointer` để không phá metadata của repo. Có thể xoá hẳn khi owner xác nhận.

## Kết quả baseline từng testbench (Questa, `run -all`)

| Testbench | Kết quả | Ghi chú |
|---|---|---|
| `tb_apb_slave_if` | **5/7 PASSED** | T5 FAIL: VERSION got `0x0200` (TB kỳ vọng `0x0100` — TB cũ, spec v3.0 = 0x0200). T7 FAIL: "start pulse not detected". |
| `tb_adc_interface` | **3/5 PASSED** | T1 FAIL: `sample_out`/`valid` không thấy (off-by-one / timing trigger). T3 overflow chỉ in INFO. |
| `tb_window_buffer` | **2/5 PASSED** | T1 & T4 FAIL: **`window_ready` never asserted** (bug report: đếm 256 trong khi buffer 512). T5: 768 samples. |
| `tb_feature_extraction` | **HANG (không $finish)** | T1 FAIL: PEAK/PTP off-by-one (`6` thay vì `7`). T2 "All Zeros" treo — nghi `rr_prev=0` (chia 0). |
| `tb_control_fsm` | **PASS** (reached LOAD→NORMALIZE) | **8 warning**: TB chỉ nối 9/16 port (thiếu `next_state_debug`,`read_addr`,`uart_send`,`mlp_valid`,`mlp_start`,`feature_read_en`,`feature_start`). |
| `tb_uart_tx` | **PASS** (chỉ in, không self-check) | In "TX done: 0x55" — không có assert so khớp bit. |
| `tb_ai_classifier` | **ELAB-FAIL** | signed/unsigned mismatch nối `fc1_out`(reg signed) vs `wire`(unsigned) và `fc2_out`. Không chạy được. |
| `tb_top_ecg_classifier` | **ELAB-FAIL** | top nối port `p_irq` nhưng module `apb_slave_if` **không có** port `p_irq` (thiếu/đổi tên port). |

→ **Kết luận baseline:** chỉ 3/8 tb chạy và pass một phần; `ai_classifier` và `top` không elaborable;
`window_buffer`/`feature`/`adc` có bug thật (window_ready, off-by-one, chia 0). Đây là mức "trước khi sửa".
