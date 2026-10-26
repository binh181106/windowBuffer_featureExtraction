`timescale 1ns / 1ps

// =============================================================================
// Top Level ECG Classifier SoC
// =============================================================================
// Module: top_ecg_classifier
// Description: Complete ECG classification system with APB interface
// Sample Rate: 360 Hz (ECG standard, MIT-BIH)
// System Clock: 50.4 MHz
// Target: FPGA/ASIC implementation
// =============================================================================

module top_ecg_classifier #(
    // (fix v3.0) System Parameters tập trung (BƯỚC 1.3):
    //   SYS_SAMPLE_RATE_DIV = 140000 -> 50.4 MHz / 140000 = 360 Hz.
    //   TB có thể override để sim nhanh (ví dụ 200); phần cứng dùng mặc định.
    parameter SYS_SAMPLE_RATE_DIV = 140000
) (
    // =============================================================================
    // Clock and Reset
    // =============================================================================
    input  wire              sys_clk,         // System clock (50.4MHz)
    input  wire              sys_rst_n,       // Active-low reset

    // =============================================================================
    // APB Interface (AMBA3) - Configuration Plane
    // =============================================================================
    input  wire [31:0]      paddr,           // APB address
    input  wire              psel,            // Peripheral select
    input  wire              penable,          // Enable
    input  wire              pwrite,          // Write enable
    input  wire [31:0]      pwdata,          // Write data
    output wire [31:0]      prdata,           // Read data

    // =============================================================================
    // ADC Interface (8-bit Parallel)
    // =============================================================================
    input  wire [7:0]        adc_data,        // 8-bit ADC data
    input  wire              adc_valid,       // Data valid strobe

    // =============================================================================
    // UART Interface (for Bluetooth)
    // =============================================================================
    output wire              uart_txd,        // UART TX
    input  wire              uart_rxd,        // UART RX

    // =============================================================================
    // Interrupt
    // =============================================================================
    output wire              irq,              // Interrupt request

    // =============================================================================
    // Status LEDs (for debugging)
    // =============================================================================
    output wire [3:0]        status_led        // Status indicators
);

    // =============================================================================
    // Internal Clock and Reset
    // =============================================================================
    wire              clk;
    wire              rst_n;
    wire              clk_locked;

    assign clk = sys_clk;
    assign clk_locked = 1'b1;   // TODO(hw): nối tín hiệu lock của PLL khi dùng PLL.
                                // Hiện chưa có PLL trong top nên lock = 1 (luôn sẵn sàng).
    assign rst_n = sys_rst_n & clk_locked;

    // Reset mềm (CSR CTRL bit4) — pulse 1 chu kỳ từ apb_slave_if.
    // Scope (chốt với owner BƯỚC 0): reset toàn bộ pipeline (FSM, AI,
    // feature, window) về IDLE. Truyền tới từng module qua port soft_reset
    // (synchronous reset, clock domain 50.4 MHz duy nhất).

    // =============================================================================
    // APB CSR Signals
    // =============================================================================
    wire [31:0]      csr_prdata;
    wire              csr_pready;
    wire              csr_pslverr;
    wire              csr_irq;

    wire              sys_enable;
    wire              sys_start;
    wire [15:0]      ecg_threshold;
    wire [15:0]      baud_div;
    wire              ble_enable;
    wire              uart_enable;
    wire              soft_reset;

    wire              sys_busy;
    wire              sys_done;
    wire [1:0]       sys_class_code;
    wire              sys_overflow;

    // =============================================================================
    // ADC Interface Signals
    // =============================================================================
    wire [7:0]       adc_sample;
    wire              adc_sample_valid;
    wire              adc_overflow;     // fix: trước đây port bị bỏ hở

    // =============================================================================
    // Window Buffer Signals
    // =============================================================================
    wire              window_enable;
    wire              window_ready;
    wire [8:0]       window_read_addr;
    wire [7:0]       window_frame_out;
    wire [31:0]      samples_collected;

    // =============================================================================
    // Feature Extraction Signals
    // =============================================================================
    wire              feature_start;
    wire              feature_read_en;   // debug/debug-alias (feature không dùng nội bộ)
    wire              feat_read_en;      // (fix v3.0) read strobe thực từ feature ra window
    wire              feature_valid;
    // Feature là signed Q4.12 (16-bit) — giữ signed để khớp ai_classifier
    // (features[] cũng signed). Trước đây khai báo unsigned -> casting ngầm.
    wire signed [15:0] f_rms, f_var, f_peak, f_zc, f_ptp;
    wire signed [15:0] f_crest, f_half_ratio, f_max;
    wire signed [15:0] f_rr, f_rr_prev, f_rr_ratio, f_rr_diff;
    wire              feature_overflow;

    // =============================================================================
    // AI Classifier Signals
    // =============================================================================
    wire              mlp_start;
    wire              mlp_enable;
    wire [1:0]       mlp_class_code;
    wire              mlp_done;
    wire              mlp_overflow;
    // (fix v3.0) fc1_out/fc2_out của ai_classifier là SIGNED (MAC Q4.12 có
    // dấu) -> wire phải signed, nếu không sẽ lỗi elaboration.
    wire signed [31:0] mlp_fc1_out [0:7];
    wire signed [31:0] mlp_fc2_out [0:3];

    // Feature array for MLP
    wire signed [15:0] features [0:11];

    assign features[0]  = f_rms;
    assign features[1]  = f_var;
    assign features[2]  = f_peak;
    assign features[3]  = f_zc;
    assign features[4]  = f_ptp;
    assign features[5]  = f_crest;
    assign features[6]  = f_half_ratio;
    assign features[7]  = f_max;
    assign features[8]  = f_rr;
    assign features[9]  = f_rr_prev;
    assign features[10] = f_rr_ratio;
    assign features[11] = f_rr_diff;

    // =============================================================================
    // Control FSM Signals
    // =============================================================================
    wire              fsm_idle;
    wire              window_en;
    wire              feat_start;
    wire              uart_send;

    // =============================================================================
    // UART TX Signals
    // =============================================================================
    wire              uart_tx_busy;
    wire              uart_tx_done;
    wire [7:0]       uart_tx_data;

    // =============================================================================
    // Control FSM State
    // =============================================================================
    wire [3:0]       current_state;
    wire [3:0]       next_state;

    // =============================================================================
    // APB Slave Interface
    // =============================================================================
    apb_slave_if #(
        .ADDR_WIDTH(8),
        .DATA_WIDTH(32)
    ) u_apb_slave (
        .pclk(clk),
        .presetn(rst_n),
        .paddr(paddr[7:0]),   // fix: cắt tường minh 32->8 (không bỏ hở/implicit)
        .psel(psel),
        .penable(penable),
        .pwrite(pwrite),
        .pwdata(pwdata),
        .prdata(prdata),
        .pready(csr_pready),
        .pslverr(csr_pslverr),
        .p_irq(csr_irq),
        .sys_enable(sys_enable),
        .sys_start(sys_start),
        .ecg_threshold(ecg_threshold),
        .baud_div(baud_div),
        .ble_enable(ble_enable),
        .uart_enable(uart_enable),
        .soft_reset(soft_reset),
        .sys_busy(sys_busy),
        .sys_done(sys_done),
        .sys_class_code(sys_class_code),
        .sys_overflow(sys_overflow)
    );

    // =============================================================================
    // ADC Interface
    // =============================================================================
    // SYS_SAMPLE_RATE_DIV: parameter tập trung (header module), mặc định
    // 140000 (50.4 MHz / 140000 = 360 Hz); TB override để sim nhanh.

    adc_interface #(
        .DATA_WIDTH(8),
        .DIV_WIDTH(18)
    ) u_adc_if (
        .clk(clk),
        .rst_n(rst_n),
        .sample_rate_div(SYS_SAMPLE_RATE_DIV),
        .adc_data_in(adc_data),
        .adc_data_valid(adc_valid),
        .adc_clk(1'b0),           // (chết) top không có ADC clock riêng
        .sample_out(adc_sample),
        .sample_valid(adc_sample_valid),
        .adc_overflow(adc_overflow),   // (fix: không để hở) gộp vào sys_overflow
        .sample_count()
    );

    // =============================================================================
    // Window Buffer
    // =============================================================================
    window_buffer #(
        .DATA_WIDTH(8),
        .WINDOW_SIZE(512),
        .OVERLAP(256)
    ) u_window (
        .clk(clk),
        .rst_n(rst_n),
        .enable(window_enable),
        .soft_reset(soft_reset),
        .sample_in(adc_sample),
        .sample_valid(adc_sample_valid),
        .read_en(feat_read_en),            // (fix v3.0) read strobe từ feature
        .read_addr(window_read_addr),
        .frame_out(window_frame_out),
        .window_ready(window_ready),
        .samples_collected(samples_collected),
        .ready_bank()
    );

    // =============================================================================
    // Feature Extraction
    // =============================================================================
    feature_extraction #(
        .DATA_IN_WIDTH(8),
        .DATA_OUT_WIDTH(16),
        .NUM_SAMPLES(512)
    ) u_feature (
        .clk(clk),
        .rst_n(rst_n),
        .soft_reset(soft_reset),          // (fix v3.0) scope reset đã chốt
        .start_compute(feature_start),
        .ecg_threshold(ecg_threshold),
        .read_enable(feature_read_en),    // debug, không dùng nội bộ
        .sample_addr(window_read_addr),
        .sample_in(window_frame_out),
        .read_en(feat_read_en),          // (fix v3.0) read strobe ra window
        .f_rms(f_rms),
        .f_var(f_var),
        .f_peak(f_peak),
        .f_zc(f_zc),
        .f_ptp(f_ptp),
        .f_crest(f_crest),
        .f_half_ratio(f_half_ratio),
        .f_max(f_max),
        .f_rr(f_rr),
        .f_rr_prev(f_rr_prev),
        .f_rr_ratio(f_rr_ratio),
        .f_rr_diff(f_rr_diff),
        .feature_valid(feature_valid),
        .overflow(feature_overflow)
    );

    // =============================================================================
    // Control FSM
    // =============================================================================
    control_fsm u_ctrl_fsm (
        .clk(clk),
        .rst_n(rst_n),
        .start(sys_start),
        .feat_valid(feature_valid),
        .apb_enable(sys_enable),
        .window_ready(window_ready),      // (fix v3.0) trigger khi cửa sổ đầy
        .mlp_done(mlp_done),             // (fix v3.0) handshake với ai_classifier
        .soft_reset(soft_reset),          // (fix v3.0) đưa FSM về IDLE
        .fsm_idle(fsm_idle),
        .window_en(window_enable),
        .feature_start(feature_start),
        .feature_read_en(feature_read_en), // debug, không dùng nội bộ
        .mlp_start(mlp_start),
        .mlp_valid(),                     // debug, ghi interfaces.md
        .uart_send(uart_send),
        .done(sys_done),
        .read_addr(),                     // (chết, đọc interfaces.md)
        .current_state(current_state),
        .next_state_debug(next_state)
    );

    // =============================================================================
    // AI Classifier (MLP)
    // =============================================================================
    ai_classifier #(
        .FEATURE_WIDTH(16),
        .HIDDEN_NEURONS(8),
        .OUTPUT_NEURONS(4)
    ) u_ai (
        .clk(clk),
        .rst_n(rst_n),
        .soft_reset(soft_reset),       // (fix v3.0) port mới
        .start(mlp_start),
        .enable(sys_enable),
        .features(features),
        .class_code(sys_class_code),
        .done(mlp_done),                 // (fix v3.0) trước đây bỏ hở -> FSM không có handshake
        .overflow(mlp_overflow),
        .fc1_out(mlp_fc1_out),
        .fc2_out(mlp_fc2_out)
    );

    // Route overflow to status (fix: gộp cả adc_overflow)
    assign sys_overflow = feature_overflow | mlp_overflow | adc_overflow;

    // =============================================================================
    // UART TX Engine
    // =============================================================================
    uart_tx #(
        .CLKS_PER_BIT(437)  // 115200 @ 50.4MHz
    ) u_uart_tx (
        .clk(clk),
        .rst_n(rst_n),
        .baud_div(baud_div),
        .tx_data(uart_tx_data),
        .tx_start(uart_send),
        .tx_enable(uart_enable),
        .tx_busy(uart_tx_busy),
        .tx_done_tick(uart_tx_done),
        .uart_txd(uart_txd)
    );

    // Format UART data: [class_code][status][heart_rate]
    assign uart_tx_data = {6'b0, sys_class_code};

    // =============================================================================
    // System Status
    // =============================================================================
    assign sys_busy = ~fsm_idle;

    // Status LEDs mapping
    assign status_led[0] = fsm_idle;              // Idle state
    assign status_led[1] = window_ready;           // Window ready
    assign status_led[2] = feature_valid;         // Features ready
    assign status_led[3] = sys_done;              // Classification done

    // Interrupt output
    assign irq = csr_irq;

endmodule
