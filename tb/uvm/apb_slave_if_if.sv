`ifndef APB_SLAVE_IF_IF_SV
`define APB_SLAVE_IF_IF_SV

// =============================================================================
// apb_slave_if_if - Virtual interface cho testbench UVM cua apb_slave_if
// Spec v3.0 (docs/MODULE_REPORT.md): clock 50.4 MHz, ECG_THRESH @0x08,
// VERSION 0x0200, BAUD default 437.
//
// - APB AMBA3 2 phase: SETUP (psel=1, penable=0) / ACCESS (psel=1, penable=1)
// - Interface giu paddr 32-bit; DUT dung ADDR_WIDTH=8 -> tb noi paddr[7:0]
// - Khai bao ca hai bien ecg_threshold va ppg_threshold (logic [15:0]) de
//   interface dung duoc voi ca RTL cu (ppg_threshold) va RTL moi (ecg_threshold).
//   Bien nao khong noi vao DUT se giu gia tri X.
// =============================================================================
interface apb_slave_if_if (input logic pclk);

  // ---- Reset ---------------------------------------------------------------
  logic        presetn;

  // ---- APB bus ------------------------------------------------------------
  logic [31:0] paddr;
  logic        psel;
  logic        penable;
  logic        pwrite;
  logic [31:0] pwdata;
  logic [31:0] prdata;
  logic        pready;
  logic        pslverr;

  // ---- Control / status tu DUT ra ----------------------------------------
  logic        sys_enable;
  logic        sys_start;
  logic        soft_reset;
  logic        ble_enable;
  logic        uart_enable;
  logic [15:0] baud_div;
  logic [15:0] ecg_threshold;   // RTL v3.0
  logic [15:0] ppg_threshold;   // RTL cu

  // ---- Status dua vao DUT (test dieu khien) -------------------------------
  logic        sys_busy;
  logic        sys_done;
  logic [1:0]  sys_class_code;
  logic        sys_overflow;

  // ---- Clocking block cho driver -----------------------------------------
  clocking drv_cb @(posedge pclk);
    default input #1step output #1step;
    output paddr, pwrite, pwdata, psel, penable;
    input  prdata, pready, pslverr;
    input  sys_enable, sys_start, soft_reset, ble_enable, uart_enable;
    input  baud_div, ecg_threshold, ppg_threshold;
  endclocking

  // ---- Clocking block cho monitor ----------------------------------------
  // Lay mau o canh xuong (negedge) de gia tri da duoc DUT cap nhat o canh
  // len truoc do (sau NBA) - neu mau o posedge se doc prdata cu.
  clocking mon_cb @(negedge pclk);
    default input #1step;
    input paddr, pwrite, pwdata, psel, penable;
    input prdata, pready, pslverr;
    input sys_enable, sys_start, soft_reset, ble_enable, uart_enable;
    input baud_div, ecg_threshold, ppg_threshold;
    input sys_busy, sys_done, sys_class_code, sys_overflow;
  endclocking

  // ---- Modport cho DUT ----------------------------------------------------
  modport dut (
    input  pclk, presetn,
    input  paddr, psel, penable, pwrite, pwdata,
    input  sys_busy, sys_done, sys_class_code, sys_overflow,
    output prdata, pready, pslverr,
    output sys_enable, sys_start, soft_reset, ble_enable, uart_enable,
    output baud_div, ecg_threshold, ppg_threshold
  );

endinterface : apb_slave_if_if

`endif
