`timescale 1ns / 1ps

// =============================================================================
// tb_apb_uvm - Testbench UVM cho apb_slave_if
// Clock 50.4 MHz (19.84 ns) theo spec v3.0.
//
// Luu y: chi khoi tao cac input cua DUT trong initial block.
// psel/penable/paddr/pwdata/pwrite duoc driver UVM dieu khien qua clocking
// block; khoi tao o day se gay xung dot nhieu driver.
// =============================================================================
module tb_apb_uvm;

  import uvm_pkg::*;
  import apb_slave_if_env_pkg::*;
  `include "uvm_macros.svh"

  // ---- Clock 50.4 MHz ------------------------------------------------------
  logic pclk = 1'b0;
  always #9.92 pclk = ~pclk;   // 19.84 ns = 50.4 MHz

  // ---- Interface -----------------------------------------------------------
  apb_slave_if_if apb_if (.pclk(pclk));

  // ---- DUT ----------------------------------------------------------------
  apb_slave_if #(
      .ADDR_WIDTH(8),
      .DATA_WIDTH(32)
  ) dut (
      .pclk     (pclk),
      .presetn  (apb_if.presetn),
      .paddr    (apb_if.paddr[7:0]),
      .psel     (apb_if.psel),
      .penable  (apb_if.penable),
      .pwrite   (apb_if.pwrite),
      .pwdata   (apb_if.pwdata),
      .prdata   (apb_if.prdata),
      .pready   (apb_if.pready),
      .pslverr  (apb_if.pslverr),
      .sys_enable    (apb_if.sys_enable),
      .sys_start     (apb_if.sys_start),
`ifdef APB_RTL_V30
      .ecg_threshold (apb_if.ecg_threshold),
`else
      .ppg_threshold (apb_if.ppg_threshold),
`endif
      .baud_div      (apb_if.baud_div),
      .ble_enable    (apb_if.ble_enable),
      .uart_enable   (apb_if.uart_enable),
      .soft_reset    (apb_if.soft_reset),
      .sys_busy      (apb_if.sys_busy),
      .sys_done      (apb_if.sys_done),
      .sys_class_code(apb_if.sys_class_code),
      .sys_overflow  (apb_if.sys_overflow)
  );

  // ---- Khoi tao input cua DUT ---------------------------------------------
  initial begin
    apb_if.presetn        = 1'b0;
    apb_if.sys_busy       = 1'b0;
    apb_if.sys_done       = 1'b0;
    apb_if.sys_class_code = 2'b00;
    apb_if.sys_overflow   = 1'b0;
  end

  // ---- Waveform ------------------------------------------------------------
  initial begin
    $dumpfile("tb_apb_uvm.vcd");
    $dumpvars(0, tb_apb_uvm);
  end

  // ---- UVM -----------------------------------------------------------------
  initial begin
    uvm_config_db#(virtual apb_slave_if_if)::set(null, "*", "vif", apb_if);
    run_test("apb_smoke_test");
  end

endmodule : tb_apb_uvm
