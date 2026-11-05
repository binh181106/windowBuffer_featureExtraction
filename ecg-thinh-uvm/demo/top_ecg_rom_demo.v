`timescale 1ns / 1ps
// =============================================================================
// ECG ROM Demo Top — self-starting ROM -> pipeline -> UART demo
// =============================================================================
// A standalone demo that runs WITHOUT any external CPU. After reset it:
//   1. Loads an 8-bit ECG sample segment from ROM (ecg_rom, $readmemh).
//   2. Paces those samples at an average TARGET_HZ using a clock-enable
//      phase-accumulator (sample_pacer; no PLL, no slow clock).
//   3. Feeds them through the EXISTING pipeline (adc_interface with
//      SYS_SAMPLE_RATE_DIV=1 so every pacer pulse is forwarded, window_buffer
//      512/overlap-256, feature_extraction 12-feature, ai_classifier MLP,
//      control_fsm) — product modules reused unmodified.
//   4. Brings itself up and reads results via a small internal APB sequencer
//      (demo_apb_seq) — no external APB bus, no FPGA APB/ADC pins.
//   5. Serializes each window result as a binary packet over the existing
//      uart_tx (demo_uart_packetizer, the ONLY driver of uart_tx) to the PC.
//
// The product top's one-byte UART protocol and default behaviour are NOT
// touched; this is a SEPARATE top (top_ecg_rom_demo) with its own pins.
//
// FPGA-visible pins are intentionally minimal (demo only): sys_clk, sys_rst_n,
// uart_txd, and a few status LEDs. NO APB / ADC pins are brought out.
//
// Weights: the MLP runs on the placeholder zero weights built into
// ai_classifier -> any class_code=00 proves the pipeline, NOT classification
// quality (see docs/AUTOMATION_STATUS.md §4). No fake weights are introduced.
// =============================================================================

module top_ecg_rom_demo #(
    // 50.0 MHz board clock; pacer averages to TARGET_HZ (360 sps default).
    parameter integer CLK_HZ    = 50_000_000,
    parameter integer TARGET_HZ = 360,

    // ROM / pacing parameters (overridable in the fast-sim demo TB).
    parameter ROM_WORDS   = 2048,
    parameter ROM_DW      = 8,
    parameter ROM_HEX     = "demo/ecg_rom.hex",

    // UART 8N1: 115200 @ 50.4 MHz => 437 clocks/bit. The board clk is
    // 50.0 MHz, so the ACTUAL baud is 50e6/437 = 114416 bps
    // (-0.68% from 115200, within UART tolerance). Reported, not assumed.
    parameter integer UART_CLKS_PER_BIT = 437
) (
    input  wire             sys_clk,     // 50 MHz board clock
    input  wire             sys_rst_n,   // active-low reset

    // UART to the PC
    output wire             uart_txd,    // TX
    input  wire             uart_rxd,    // RX — unused in the demo

    // Demo status
    output wire [3:0]       status_led,
    output wire             demo_done,     // at least one window result emitted
    output wire             demo_overflow,
    output wire [1:0]       demo_class
);

    wire clk   = sys_clk;
    wire rst_n = sys_rst_n;

    // =========================================================================
    // ROM + pacer (ROM data is valid from time 0 in sim; on Gowin the RAM
    // is configured before the pacer's first pulse, > 138k cycles away).
    // =========================================================================
    wire [$clog2(ROM_WORDS)-1:0] rom_addr;
    wire [ROM_DW-1:0] rom_out;
    wire [ROM_DW-1:0] pace_data;
    wire pace_valid;
    wire pace_eod;

    ecg_rom #(
        .ROM_WORDS(ROM_WORDS),
        .ROM_DW(ROM_DW),
        .ROM_HEX(ROM_HEX)
    ) u_rom (
        .clk(clk),
        .rom_addr(rom_addr),
        .rom_out(rom_out)
    );

    sample_pacer #(
        .CLK_HZ(CLK_HZ),
        .TARGET_HZ(TARGET_HZ),
        .ROM_WORDS(ROM_WORDS),
        .ROM_DW(ROM_DW)
    ) u_pacer (
        .clk(clk),
        .rst_n(rst_n),
        .rom_out(rom_out),
        .rom_addr(rom_addr),
        .sample_data(pace_data),
        .sample_valid(pace_valid),
        .end_of_data(pace_eod)
    );

    // =========================================================================
    // Pipeline — EXISTING modules, unmodified (same wiring as the product top)
    // =========================================================================
    wire [ROM_DW-1:0] adc_sample;
    wire adc_sample_valid, adc_overflow;
    wire window_enable, window_ready;
    wire feature_start, feat_valid, feature_overflow;
    wire mlp_start, mlp_done, mlp_overflow;
    wire [1:0] sys_class_code;
    wire sys_done, sys_busy, sys_start, sys_enable;
    wire sys_overflow;
    wire [31:0] csr_prdata;
    wire csr_pready, csr_pslverr, csr_irq;
    wire uart_tx_busy, uart_tx_done;
    wire [15:0] ecg_threshold, baud_div;
    wire ble_enable, uart_enable, soft_reset;
    wire signed [15:0] f_rms, f_var, f_peak, f_zc, f_ptp, f_crest;
    wire signed [15:0] f_half_ratio, f_max, f_rr, f_rr_prev, f_rr_ratio, f_rr_diff;
    wire [8:0] feat_read_addr;
    wire feat_read_en;
    wire [ROM_DW-1:0] window_frame_wire;

    // APB signals driven by the demo sequencer (NOT brought to FPGA pins)
    wire [31:0] apb_paddr, apb_pwdata;
    wire apb_psel, apb_penable, apb_pwrite;

    // Demo window index (0-based: increments on every window_ready)
    reg [15:0] win_index;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            win_index <= 16'd0;
        else if (window_ready)
            win_index <= win_index + 16'd1;
    end

    // --- ADC interface (DIV_WIDTH=2: SYS_SAMPLE_RATE_DIV = 1 -> rate_tick
    //     every cycle, so every 1-cycle pacer pulse is forwarded exactly
    //     once — no double division, no dropped sample).
    adc_interface #(
        .DATA_WIDTH(ROM_DW),
        .DIV_WIDTH(2)
    ) u_adc_if (
        .clk(clk),
        .rst_n(rst_n),
        .sample_rate_div(2'd1),
        .adc_data_in(pace_data),
        .adc_data_valid(pace_valid),
        .adc_clk(1'b0),
        .sample_out(adc_sample),
        .sample_valid(adc_sample_valid),
        .adc_overflow(adc_overflow),
        .sample_count()
    );

    // --- Window buffer -------------------------------------------------------
    window_buffer #(
        .DATA_WIDTH(ROM_DW),
        .WINDOW_SIZE(512),
        .OVERLAP(256)
    ) u_window (
        .clk(clk),
        .rst_n(rst_n),
        .enable(window_enable),
        .soft_reset(soft_reset),
        .sample_in(adc_sample),
        .sample_valid(adc_sample_valid),
        .read_en(feat_read_en),
        .read_addr(feat_read_addr),
        .frame_out(window_frame_wire),
        .window_ready(window_ready),
        .samples_collected(),
        .ready_bank(),
        .sample_cnt()
    );

    // --- Feature extraction --------------------------------------------------
    wire signed [15:0] feat_vec [0:11];
    assign feat_vec[0]=f_rms;        assign feat_vec[1]=f_var;
    assign feat_vec[2]=f_peak;       assign feat_vec[3]=f_zc;
    assign feat_vec[4]=f_ptp;        assign feat_vec[5]=f_crest;
    assign feat_vec[6]=f_half_ratio; assign feat_vec[7]=f_max;
    assign feat_vec[8]=f_rr;         assign feat_vec[9]=f_rr_prev;
    assign feat_vec[10]=f_rr_ratio;  assign feat_vec[11]=f_rr_diff;

    feature_extraction #(
        .DATA_IN_WIDTH(ROM_DW),
        .DATA_OUT_WIDTH(16),
        .NUM_SAMPLES(512)
    ) u_feature (
        .clk(clk),
        .rst_n(rst_n),
        .soft_reset(soft_reset),
        .start_compute(feature_start),
        .ecg_threshold(ecg_threshold),
        .read_enable(1'b0),            // debug input, unused
        .sample_addr(feat_read_addr),
        .sample_in(window_frame_wire),
        .read_en(feat_read_en),
        .f_rms(f_rms), .f_var(f_var), .f_peak(f_peak), .f_zc(f_zc),
        .f_ptp(f_ptp), .f_crest(f_crest), .f_half_ratio(f_half_ratio),
        .f_max(f_max), .f_rr(f_rr), .f_rr_prev(f_rr_prev),
        .f_rr_ratio(f_rr_ratio), .f_rr_diff(f_rr_diff),
        .feature_valid(feat_valid),
        .overflow(feature_overflow)
    );

    // --- Control FSM ---------------------------------------------------------
    wire fsm_idle;
    control_fsm u_ctrl_fsm (
        .clk(clk),
        .rst_n(rst_n),
        .start(sys_start),
        .feat_valid(feat_valid),
        .apb_enable(sys_enable),
        .window_ready(window_ready),
        .mlp_done(mlp_done),
        .soft_reset(soft_reset),
        .fsm_idle(fsm_idle),
        .window_en(window_enable),
        .feature_start(feature_start),
        .feature_read_en(),
        .mlp_start(mlp_start),
        .mlp_valid(),
        .uart_send(),              // demo drives uart_tx itself; ignored here
        .done(sys_done),
        .read_addr(),
        .current_state(),
        .next_state_debug()
    );

    // --- AI classifier (placeholder zero weights: pipeline check only) -------
    ai_classifier #(
        .FEATURE_WIDTH(16),
        .HIDDEN_NEURONS(8),
        .OUTPUT_NEURONS(4)
    ) u_ai (
        .clk(clk),
        .rst_n(rst_n),
        .soft_reset(soft_reset),
        .start(mlp_start),
        .enable(sys_enable),
        .features(feat_vec),
        .class_code(sys_class_code),
        .done(mlp_done),
        .overflow(mlp_overflow),
        .fc1_out(),
        .fc2_out()
    );

    // --- APB slave + demo sequencer ----------------------------------------
    apb_slave_if #(
        .ADDR_WIDTH(8),
        .DATA_WIDTH(32)
    ) u_apb (
        .pclk(clk),
        .presetn(rst_n),
        .paddr(apb_paddr[7:0]),        // explicit 32->8 truncation (no implicit)
        .psel(apb_psel),
        .penable(apb_penable),
        .pwrite(apb_pwrite),
        .pwdata(apb_pwdata),
        .prdata(csr_prdata),
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

    wire pkt_req;
    demo_apb_seq u_seq (
        .pclk(clk),
        .presetn(rst_n),
        .paddr(apb_paddr[7:0]),       // explicit 32->8 truncation (no implicit)
        .psel(apb_psel),
        .penable(apb_penable),
        .pwrite(apb_pwrite),
        .pwdata(apb_pwdata),
        .pready(csr_pready),
        .prdata(csr_prdata),
        .sys_done(sys_done),
        .pkt_req(pkt_req)
    );

    // --- UART packetizer -> existing uart_tx (single TX controller) --------
    wire pkt_tx_start;
    wire [7:0]  pkt_tx_data;
    wire pkt_done_r, pkt_drop_r, pkt_busy_r;

    demo_uart_packetizer u_pz (
        .clk(clk),
        .rst_n(rst_n),
        .pkt_req(pkt_req),
        .win_index(win_index),
        .f0(f_rms), .f1(f_var), .f2(f_peak), .f3(f_zc), .f4(f_ptp),
        .f5(f_crest), .f6(f_half_ratio), .f7(f_max), .f8(f_rr),
        .f9(f_rr_prev), .f10(f_rr_ratio), .f11(f_rr_diff),
        .class_code(csr_prdata[1:0]),   // result read back over APB, as timed
                                         // by demo_apb_seq's pkt_req
        .err_adc(adc_overflow),
        .err_feat(feature_overflow),
        .err_mlp(mlp_overflow),
        .tx_start(pkt_tx_start),
        .tx_data(pkt_tx_data),
        .tx_done_tick(uart_tx_done),
        .pkt_busy(pkt_busy_r),
        .pkt_done(pkt_done_r),
        .pkt_drop(pkt_drop_r)
    );

    uart_tx #(
        .CLKS_PER_BIT(UART_CLKS_PER_BIT)
    ) u_uart_tx (
        .clk(clk),
        .rst_n(rst_n),
        .baud_div(baud_div),       // APB-configured; sequencer writes 437
        .tx_data(pkt_tx_data),
        .tx_start(pkt_tx_start),
        .tx_enable(1'b1),
        .tx_busy(uart_tx_busy),
        .tx_done_tick(uart_tx_done),
        .uart_txd(uart_txd)
    );

    // =========================================================================
    // APB STATUS sources
    // =========================================================================
    // Same semantics as the product top (top_ecg_classifier.v):
    //   busy     = control FSM is not idle
    //   overflow = numeric pipeline overflow (adc | feature | mlp)
    // pkt_drop (packetizer back-pressure) is a DIFFERENT meaning and is
    // deliberately NOT included in the APB STATUS overflow bit: a dropped
    // packet is a transport loss, not a numeric overflow. It stays visible on
    // the demo_overflow pin and in the packet flags.
    assign sys_busy     = ~fsm_idle;
    assign sys_overflow = adc_overflow | feature_overflow | mlp_overflow;

    // =========================================================================
    // Demo status
    // =========================================================================
    reg demo_done_r;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) demo_done_r <= 1'b0;
        else if (pkt_done_r) demo_done_r <= 1'b1;
    end
    assign demo_done     = demo_done_r;
    assign demo_overflow = adc_overflow | feature_overflow | mlp_overflow | pkt_drop_r;
    assign demo_class    = sys_class_code;
    assign status_led[0] = sys_done;
    assign status_led[1] = window_ready;
    assign status_led[2] = feat_valid;
    assign status_led[3] = demo_done_r;

endmodule
