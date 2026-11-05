# =============================================================================
# SDC for top_ecg_rom_demo — Gowin ACG525 board
# =============================================================================
# CONFIRMED: 50 MHz external oscillator on the board. This is the ONLY clock
# constraint asserted; the pacer is a clock-enable (no PLL) so no other clock
# needs defining.
#
# TODO before P&R (do NOT assume — confirm against board docs + Gowin package):
#   - target device/part/package/speed grade (ACG525 chip not found under
#     H:\Gowin\Gowin_V1.9.9_x64\IDE\data — blocked until user confirms)
#   - pin constraints: only demo pins are used:
#        sys_clk  (50 MHz XTAL),
#        sys_rst_n (polarity unconfirmed),
#        uart_txd / uart_rxd,
#        status_led[3:0], demo_done, demo_overflow, demo_class[1:0]
#     NO APB / ADC pins are brought out by the demo top.
#   - I/O voltage per bank (LVCMOS33 vs LVCMOS18 unconfirmed)
# =============================================================================
create_clock -name sys_clk -period 20.0 [get_ports sys_clk]
