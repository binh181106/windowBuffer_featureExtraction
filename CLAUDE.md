# CLAUDE.md

Đọc và tuân thủ **`AGENTS.md`** ở gốc repo. Đó là bộ quy tắc chung cho mọi agent (Claude Code, Codex...).
Interface giữa các module nằm ở **`docs/interfaces.md`**.

@AGENTS.md

## Bổ sung riêng cho Claude Code

- Bắt đầu mỗi phiên: xác nhận với người dùng **bạn đang làm task nào, cho ai, trong thư mục nào** (xem bảng phân quyền ở `AGENTS.md` mục 3). Chưa rõ thì hỏi trước khi sửa file.
- Làm việc trong worktree/nhánh của task hiện tại. Không `git checkout` sang nhánh khác, không `git push --force`, không sửa `main`.
- Trước khi sửa một module, đọc `docs/interfaces.md` và testbench tương ứng trong `tb/`.
- Khi gặp merge conflict: không tự chọn một bên. Liệt kê các hunk xung đột, giải thích mỗi bên làm gì, rồi hỏi người dùng. Với file sinh ra thì chạy lại lệnh sinh thay vì sửa tay.
- Kết thúc task: tóm tắt ngắn gồm (1) file đã sửa, (2) port/hành vi có đổi không, (3) lệnh test đã chạy và kết quả thật.
