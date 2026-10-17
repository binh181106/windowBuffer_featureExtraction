# AGENTS.md — Quy tắc chung cho AI agent (Codex, Claude Code, ...)

Repo: ECG Classification AI Accelerator RTL (Verilog/SystemVerilog). Nhóm 4 người làm song song, mỗi người dùng AI agent riêng.
Mục tiêu của file này: các agent **không đạp lên nhau** và **không phá interface giữa các module**.

## 1. Tổng quan dự án

Hệ thống phân loại tín hiệu ECG với tăng tốc AI (dự án **không liên quan PPG**; README cũ ghi PPG là nhầm, tên file `top_ppg_classifier.v` chỉ là tên lịch sử):

```
ADC (8-bit) -> window_buffer (512 mẫu, overlap 50%) -> feature_extraction (12 feature, 16-bit)
            -> ai_classifier (MLP 12->8->4) -> UART TX
            điều khiển bởi control_fsm, cấu hình qua apb_slave_if (APB AMBA3)
```

Chi tiết port, định dạng số, thứ tự feature: xem **`docs/interfaces.md`** (nguồn sự thật duy nhất).

## 2. Cấu trúc thư mục

| Thư mục | Nội dung |
|---|---|
| `adc/` | `adc_interface.v` |
| `window/` | `window_buffer.v` |
| `feature/` | `feature_extraction.v` |
| `ai/` | `ai_classifier.v`, `mlp_weights_rom.v`, weights |
| `control/` | `control_fsm.v` |
| `apb/` | `apb_slave_if.v` |
| `uart/` | `uart_tx.v` |
| `top/` | `top_ppg_classifier.v` |
| `tb/` | testbench `tb_*.sv`, `Makefile`, `run_all.sh` |
| `sim/` | file/kết quả mô phỏng |
| `synthesis/` | `run_synth.tcl` |
| `docs/` | tài liệu, `interfaces.md` |

## 3. Ai sở hữu phần nào

> Điền tên thật vào bảng này khi nhóm đã chốt. Cập nhật cả `CODEOWNERS` cho khớp.

| Người | Phạm vi được sửa | Ghi chú |
|---|---|---|
| A: `<tên>` | `adc/`, `window/`, `tb/tb_adc_interface.sv`, `tb/tb_window_buffer.sv` | |
| B: `<tên>` | `feature/`, `tb/tb_feature_extraction.sv` | |
| C: `<tên>` | `ai/`, `tb/tb_ai_classifier.sv` | |
| D: `<tên>` | `top/`, `control/`, `apb/`, `uart/`, `sim/`, `synthesis/`, `tb/Makefile`, `tb/run_all.sh`, `tb/tb_top_*.sv`, `tb/tb_control_fsm.sv`, `tb/tb_apb_slave_if.sv`, `tb/tb_uart_tx.sv`, `.github/` | file dùng chung |

## 4. Quy tắc bắt buộc cho agent

1. **Chỉ sửa file trong phạm vi của người đang giao việc** (bảng ở mục 3). Cần sửa file ngoài phạm vi thì **dừng lại và hỏi người dùng**, không tự làm.
2. **Không đổi tên module, tên port, độ rộng bit, thứ tự feature, hoặc định dạng số** của bất kỳ module nào mà không có thay đổi tương ứng trong `docs/interfaces.md` đã được người dùng đồng ý.
3. **Không refactor lan man**: không đổi style, không đổi tên biến, không di chuyển file ngoài yêu cầu của task.
4. **Không sửa file dùng chung** (`top/`, `control/`, `apb/`, `tb/Makefile`, `synthesis/`, `.github/`) trừ khi task nói rõ và người dùng là chủ sở hữu.
5. **Không commit file sinh ra**: `*.vcd`, `*.vvp`, output synthesis, file tạm.
6. **Không tự thay đổi trọng số** (`weight.hex`) hoặc tham số mô hình. File này do người phụ trách AI cập nhật, kèm ghi chú nguồn huấn luyện.
7. Không "sửa cho testbench pass" bằng cách làm yếu testbench hoặc đổi giá trị kỳ vọng. Nếu testbench sai, giải thích vì sao và hỏi người dùng.

## 5. Quy ước code

- Verilog cho RTL (`.v`), SystemVerilog cho testbench (`.sv`).
- Tên module/file: `snake_case`, testbench đặt `tb_<ten_module>.sv`.
- Số thực dùng fixed-point **Q4.12, 16-bit** (xem `docs/interfaces.md`). Không dùng `real` trong RTL tổng hợp được.
- Reset đồng bộ/bất đồng bộ phải thống nhất với module hiện có trong cùng thư mục: đọc code cũ trước khi viết mới.
- Mỗi module có comment đầu file: chức năng, port chính, latency.

## 6. Build và test

Yêu cầu: Icarus Verilog (`iverilog`, `vvp`), GTKWave để xem sóng.

```bash
cd tb
make apb       # hoặc: adc | window | feature | control | uart | ai | top
make all       # chạy toàn bộ
```

Trước khi báo "xong", agent phải:
1. Chạy testbench của module mình sửa và **dán kết quả PASS/FAIL thật**.
2. Nếu sửa port hoặc hành vi ảnh hưởng module khác, chạy `make all` (hoặc `make top`).
3. Nêu rõ test nào chưa chạy được và lý do.

## 7. Git

- Nhánh: `feat/<ten>/<task-ngan>`, `fix/<ten>/<task-ngan>`. Không push thẳng `main`.
- Mỗi phiên làm việc bắt đầu bằng `git pull --rebase origin main`.
- Mỗi agent chạy trong **worktree riêng**, không cho hai agent cùng làm trong một thư mục:
  ```bash
  git worktree add ../ecg-<ten>-<task> -b feat/<ten>/<task>
  ```
- Commit nhỏ, một việc một commit, message ngắn gọn nói rõ module.
- PR phải nêu: module nào đổi, port có đổi không, test đã chạy.

## 8. Khi không chắc

Hỏi người dùng. Dừng và hỏi rẻ hơn nhiều so với một thay đổi âm thầm làm hỏng interface của người khác.
