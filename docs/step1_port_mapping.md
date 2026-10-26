# BƯỚC 1 — Inspection & Port Mapping (đọc từ RTL thật, không suy diễn từ report)

Ngày: 2026-10-25 · Branch `feature/full-system-integration-v3`

## 1.1 Sự thật từ code (đối chiếu với report — chỗ lệch ghi rõ)

| # | Chủ đề | Report nói | Code thật | Kết luận |
|---|---|---|---|---|
| L1 | `sample_rate_div` | bug: 16-bit, 140000 bị cắt thành 8928 | `adc_interface.v` đã `DIV_WIDTH=18` (port 18-bit, `rate_timer` 18-bit); top nối `wire [17:0]` = 140000 | **Bug 16-bit KHÔNG còn tồn tại** trong code (đã fix sẵn). Chỉ cần giữ nguyên + test bảo vệ. |
| L2 | off-by-one `rate_timer` | công thức `f = f_clk/(div+1)` nhưng điều kiện `rate_timer >= div` | **Trace kỹ (đã hiệu đính):** `rate_timer >= div` → counter chạy 0..140000 (140001 giá trị) → chu kỳ = **div+1 = 140001 clock** → f = 50.4e6/140001 = 359.997 Hz (lệch ~0.0007%). Muốn **chu kỳ đúng 140000** (360.000 Hz) phải đổi điều kiện thành `rate_timer >= div - 1` (counter 0..139999). | **Quyết định: đổi điều kiện thành `>= (div-1)`** (div=140000) → chu kỳ = 140000 clock đúng = 360 Hz. Trace: tick khi v=139999, reset, lần sau tick sau đúng div edge. |
| L3 | `feature_extraction` FSM | "7 trạng thái" nhưng chỉ liệt kê 6 | Code thật: 7 localparam (S_IDLE,S_ACCUMULATE,S_CALC_BASE,S_CALC_VAR,S_CALC_RMS,S_CALC_CREST,S_DONE) — **S_CALC_CREST không dùng** (crest tính trong S_CALC_RMS) | Report số đúng (7), nhưng 1 state chết. Ghi chú, không xoá (tránh đổi encoding state ngoài task). |
| L4 | `window_ready` trigger | phát khi `sample_cnt` ≥ 256, chia hết 256 | Code: `if (sample_cnt >= 255 && (sample_cnt-255)%256==0)` với `sample_cnt` **bão hòa ở 511** → trigger đầu ở 255 (window mới nửa đầy), sau 511 thì **bắn liên tục mỗi cycle** | **BUG thật** (khớp baseline: "window_ready never asserted" ở tb kỳ vọng khác). Fix ở BƯỚC 2. |
| L5 | `clk_locked` ở top | không có trong report | `wire clk_locked;` **KHÔNG BẤT KỲ DRIVER** → `rst_n = sys_rst_n & clk_locked` = x trong sim → mọi register không reset → **gốc của hang/FAIL trong baseline** (adc valid=0, feature treo, control lệch) | **BUG thật, nghiêm trọng.** Fix: tie `clk_locked = 1'b1` (PLL lock do owner cấu hình — xem BƯỚC 4 TODO). |
| L6 | `apb_slave_if` không có port irq | top nối `.p_irq(csr_irq)` | `p_irq` chỉ là `reg` nội bộ, **không phải port** → **ELAB-FAIL top** (khớp baseline) | **BUG thật.** Thêm port `output reg p_irq` vào module (RTL đã compute sẵn, chỉ thiếu port). |
| L7 | `ai_classifier.done` | spec: `done` → control_fsm/APB | top nối `.done()` **bỏ trống** → control_fsm không bao giờ thấy MLP xong; `mlp_valid` cũng bỏ trống | **BUG thật (hệ thống).** Fix: thêm port `mlp_done` vào `control_fsm`, nối `ai.done → mlp_done`, dùng làm early-exit cho các state shadow (giữ cấu trúc 10 state). |
| L8 | `feature_extraction` đọc dữ liệu | `read_enable` do ai đó kích | top nối `window.read_en = feature_read_en` (từ control_fsm) nhưng **control_fsm không bao giờ assert** (mọi state để =0) → window không latch địa chỉ → `frame_out` đứng ở `ram[latched_addr=0]` forever | **BUG thật (datapath chết).** Fix: feature tự assert `read_en` khi ở S_ACCUMULATE (thêm port `read_en` ra — cập nhật interfaces.md). |
| L9 | `weight.hex` | `ai/weights/weight.hex`, 164 từ, đọc bằng `mlp_weights_rom` | `mlp_weights_rom.v` **không được instance ở đâu**; `weight.hex` **không có trong repo** (đường dẫn trỏ `../AI_FSM_ECG-main/...` — ngoài repo, không tồn tại). `ai_classifier` giữ weights là register nội bộ, initial = 0, cổng ghi ROM (rom_we/rom_addr/rom_wdata) **không có driver** (chết) | **Mở (open):** không có weights thật → MLP hiện ra luôn 0, argmax tie → class 0 (quy ước index thấp). Không tự bịa weights thật; golden model sẽ đọc weights từ file (chủ AI phải drop `weight.hex` vào repo — owner quyết định). |
| L10 | signed/unsigned feature port | interfaces.md: f_zc/f_rr/f_rr_prev "Unsigned" | Mọi feature port khai báo `signed [15:0]`; zc/rr thực ≤ 512 < 32768 nên top bit = 0, không sai số học, nhưng **tránh casting ngầm**: giữ signed thống nhất, ghi vào interfaces.md | Đối chiếu: giữ RTL (signed), sửa tài liệu. |
| L11 | `paddr` | top 32-bit, module 8-bit | top: `paddr[31:0]`, module: `ADDR_WIDTH=8` → nối `.paddr(paddr)` **bị cắt ngầm** 32→8 | Fix: nối tường minh `.paddr(paddr[7:0])`, giữ port top 32-bit (AMBA3 32-bit bus là chuẩn; ghi interfaces.md). |
| L12 | `adc_clk` | port của adc_interface | Module nhận `adc_clk` nhưng **không dùng** trong logic; top tie `1'b0` | Giữ tie, comment tường minh. |
| L13 | Variance formula | "variance = E[X²]−(E[X])²" | Code: `var_calc = (sum_square <<< 3) − ((mean_val*mean_val) >>> 12)` với `mean_val = sum <<< 3` → **không bằng** 512·var (kết quả ≈ 8·Σx² − mean²/64) | **Không tự đổi công thức** (đổi giá trị feature → đụng retrain của chủ AI). Ghi vào "Cần owner quyết định". Golden model **phản chiếu đúng công thức RTL** (bit-exact). |
| L14 | `f_var` lấy bit thấp | Q4.12 | `f_var <= var_calc[15:0]` — truncation không round; có thể âm (var_calc signed) | Audit bit-width: Σ² cần 64-bit ✓; f_var truncate [15:0] — ghi vào bảng audit, giữ hành vi, ghi chú "truncate, không round". |
| L15 | MAC MLP | Q4.12×Q4.12→32b, shift/round/saturate | `mac_temp[47:0]` (32×32 → 64b, dùng 48), `>>> 12`, **không saturate, không round** (chỉ floor shift) | Ghi vào bảng audit: Q24 sau MAC (feature_norm 16b×16b → 32b chưa shift), accumulate 32b không saturate. Golden mirror RTL. |
| L16 | APB `sys_start` | start là edge | `if (pwdata[1]) sys_start <= 1; ... if (sys_start) sys_start <= 0;` → **pulse 1 cycle** sau APB write cycle | Đúng. TB T7 sai vì check sai cycle → sửa TB (có lý do). |
| L17 | CTRL bit4 = soft_reset | register map | `if (pwdata[4]) soft_reset <= 1'b1` ✓ khớp map. soft_reset → `window_buffer` (reset ptr/cnt). **Chưa nối tới feature/fsm** — spec BƯỚC 2 yêu cầu `soft_reset` đưa FSM về IDLE | Nối `soft_reset` (từ APB, pulse 2 cycle) vào reset điều khiển của `control_fsm` + `ai_classifier` + `feature_extraction` (bổ sung vào `rst_n` composite). **Cần owner xác nhận** (đổi hành vi). |

## 1.2 Port Mismatch Table (từng instance trong top, đọc từ code)

### `u_apb_slave` (apb_slave_if)
| Port module (độ rộng thật) | Nối trong top | Sự thật | Xử lý |
|---|---|---|---|
| paddr[7:0] | `.paddr(paddr)` (wire 32b) | width cut ngầm 32→8 | `.paddr(paddr[7:0])` |
| p_irq (không tồn tại!) | `.p_irq(csr_irq)` | **port không có** → elaboration fail | thêm `output reg p_irq` vào module |
| các port còn lại | khớp 1:1 | ok | — |

### `u_adc_if` (adc_interface)
| Port | Nối | Sự thật | Xử lý |
|---|---|---|---|
| sample_rate_div[17:0] | `wire [17:0]` + `assign = 18'd140000` | **sai ngữ nghĩa**: 140000 = 0x22220, đúng trong 18b ✓ | giữ (đã đúng); thêm parameter tập trung |
| adc_clk | `1'b0` | port chết trong module | giữ, comment |
| adc_overflow / sample_count | `()` bỏ hở | spec: nối tường minh | nối sang wire (led/status hoặc tie) — nối `adc_overflow` vào `sys_overflow`, giữ `sample_count` làm wire debug |
| adc_data_in / adc_data_valid | ✓ | — | — |

### `u_window` (window_buffer)
| Port | Nối | Sự thật | Xử lý |
|---|---|---|---|
| read_en | `feature_read_en` (từ FSM, luôn 0) | datapath chết (L8) | đổi: lấy từ port `read_en` mới của feature (assert trong ACCUMULATE) |
| read_addr[8:0] | `window_read_addr` ← feature.sample_addr | ✓ (feature drive, window latch khi read_en) | giữ |
| frame_out | → feature.sample_in | ✓ | giữ |
| window_ready | chỉ → `status_led[1]` | **không trigger FSM** (report muốn window_ready → feature qua FSM) | giữ hiện trạng: FSM chờ `feature_valid` (an toàn hơn); ghi chú "window_ready chỉ là status" — **Cần owner quyết định** nếu muốn gate bằng window_ready |
| ready_bank | `()` | alias chết | giữ bỏ hở tường minh |
| samples_collected | wire, không dùng | debug | giữ |

### `u_feature` (feature_extraction)
| Port | Nối | Sự thật | Xử lý |
|---|---|---|---|
| start_compute | `feature_start` (pulse 1 cycle từ FSM LOAD) | ✓ | giữ; thêm port `read_en` (Out) mới |
| ecg_threshold[15:0] | wire 16b từ APB ✓ | — | — |
| 12 f_* [15:0] (signed) | wire **unsigned** 16b trong top → casting ngầm vào array signed `features[0:11]` | implicit cast (không lỗi compile, nhưng dấu sai nghĩa) | khai báo wire signed trong top |
| sample_addr[8:0] | out → window.read_addr ✓ | — | — |

### `u_ctrl_fsm` (control_fsm)
| Port | Nối | Sự thật | Xử lý |
|---|---|---|---|
| read_addr[8:0] (Out) | `()` | chết (feature tự ra địa chỉ) | giữ bỏ hở tường minh, ghi interfaces.md |
| mlp_valid (Out) | `()` | chết | giữ, ghi |
| **thiếu input mlp_done** | — | deadlock/early-exit (L7) | **thêm input `mlp_done`**, nối ai.done; early-exit mọi state shadow |
| current_state/next_state_debug | wire debug ✓ | — | — |

### `u_ai` (ai_classifier)
| Port | Nối | Sự thật | Xử lý |
|---|---|---|---|
| start | `mlp_start` (FSM, 96 cycle ở S_FC1) | ai chỉ start khi ở IDLE — mlp_start assertion dài vẫn ok (start ở các state khác bị bỏ qua) | giữ + mlp_done fix |
| enable | `sys_enable` | **risky**: enable=0 khi chưa write CTRL → ai không bao giờ start (IDLE cần `start && enable`) | **Cần owner quyết định**: thay `enable = sys_enable` bằng enable thường 1, hoặc ghi "phải enable trước khi start". Hiện giữ `sys_enable` + ghi chú |
| done | `()` | chết (L7) | → `mlp_done` của FSM |
| fc1_out/fc2_out [array 32b] | wire **unsigned** array trong top | signedness mismatch (Questa chỉ warning với tb; top compile được) | khai báo `wire signed [31:0]` |

### `u_uart_tx`
| Port | Nối | Sự thật | Xử lý |
|---|---|---|---|
| tx_data[7:0] | `{6'b0, sys_class_code}` ✓ | — | giữ |
| tx_start | `uart_send` (FSM, 1 cycle ở S_DONE) ✓ | — | giữ |
| tx_enable | `uart_enable` (APB CONFIG bit1, reset=1) ✓ | — | giữ |
| baud_div[15:0] | APB ✓ | — | giữ |

### Top ports ngoài
| Port | Sự thật |
|---|---|
| `uart_rxd` input | **không dùng** trong module (không có uart_rx) → giữ, comment "TBD — RX chưa thiết kế" |
| `pready/pslverr` | **bị treo** (module không expose ra top) — spec không yêu cầu; ghi interfaces.md |
| `irq` | = p_irq (sau fix) ✓ |
| `status_led[3:0]` | = {fsm_idle, window_ready, feature_valid, sys_done} ✓ khớp spec |

## 1.3 System Parameters chốt (sẽ đặt tập trung, không hard-code)

| Parameter | Giá trị | Ghi chú |
|---|---|---|
| `SYS_CLK_FREQ` | 50.4 MHz (chu kỳ 19.841 ns; sim half-period **9.92 ns**) | mọi tb `timescale 1ns/1ps` + `#9.92` |
| `SAMPLE_RATE` | 360 Hz | ECG, chuẩn project |
| `SAMPLE_RATE_DIV` | 140000 (18-bit) | f = 50.4e6/140000 = 360 Hz (chọn `timer >= div`, KHÔNG phải div+1 — xem L2) |
| `UART_CLKS_PER_BIT` | 437 (baud thực ≈115.27 k, sai ~0.14%) | 50.4e6/115200 = 437.5 |
| Feature/weight | Q4.12, 16-bit | signed thống nhất (L10) |
| VERSION register | 0x0200 | RTL đã đúng; TB cũ expect 0x0100 → sửa TB (spec v3.0) |

## 1.4 Danh mục ghi vào báo cáo cuối

- **Cần owner quyết định:** (1) variance formula L13, (2) ai.enable semantics L8/enable row, (3) soft_reset phạm vi L17, (4) window_ready gate FSM, (5) `weight.hex` (L9 — chủ AI drop file), (6) UART RX (port chết).
- **TODO phần cứng:** chân CST, PLL/oscillator, lệnh Gowin EDA (không có Gowin toolchain có license chạy được ở đây — ghi rõ chưa verify).
