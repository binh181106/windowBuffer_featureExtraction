`ifndef APB_SLAVE_IF_ENV_PKG_SV
`define APB_SLAVE_IF_ENV_PKG_SV

// =============================================================================
// apb_slave_if_env_pkg - UVM environment cho module apb_slave_if
// Spec v3.0 (docs/MODULE_REPORT.md): clock 50.4 MHz, ECG_THRESH @0x08,
// VERSION 0x0200, BAUD default 437.
//
// Compile:
//   +define+APB_RTL_V30 -> RTL v3.0: port .ecg_threshold, VERSION 0x0200,
//                           BAUD 437
//   (mac dinh)          -> RTL cu : port .ppg_threshold, VERSION 0x0100,
//                           BAUD 856
//
// Thanh phan: cfg, item, sequencer, driver, monitor, agent, scoreboard,
//             coverage, base test + 3 sequence.
// =============================================================================
package apb_slave_if_env_pkg;

  import uvm_pkg::*;
  `include "uvm_macros.svh"

  // ---------------------------------------------------------------------------
  // Dia chi thanh ghi (offset)
  // ---------------------------------------------------------------------------
  localparam bit [7:0] ADDR_CTRL    = 8'h00;
  localparam bit [7:0] ADDR_STATUS  = 8'h04;
  localparam bit [7:0] ADDR_THRESH  = 8'h08;  // ECG_THRESH
  localparam bit [7:0] ADDR_BAUD    = 8'h0C;
  localparam bit [7:0] ADDR_RESULT  = 8'h10;
  localparam bit [7:0] ADDR_VERSION = 8'h14;
  localparam bit [7:0] ADDR_CONFIG  = 8'h18;

  // ---------------------------------------------------------------------------
  // Gia tri reset / ky vong theo phien ban RTL
  // ---------------------------------------------------------------------------
`ifdef APB_RTL_V30
  localparam bit [15:0] RESET_VERSION     = 16'h0200;
  localparam bit [31:0] RESET_BAUD_REG    = 32'h0000_01B5;  // 437
  localparam bit [15:0] RESET_BAUD_DIV    = 16'd437;
  localparam bit [15:0] WRITE_BAUD_VALUE  = 16'h01B5;
`else
  localparam bit [15:0] RESET_VERSION     = 16'h0100;
  localparam bit [31:0] RESET_BAUD_REG    = 32'h0000_0358;  // 856
  localparam bit [15:0] RESET_BAUD_DIV    = 16'd856;
  localparam bit [15:0] WRITE_BAUD_VALUE  = 16'h0358;
`endif
  localparam bit [31:0] RESET_THRESH_REG  = 32'h0000_0050;
  localparam bit [15:0] RESET_THRESH_OUT  = 16'd80;
  localparam bit [31:0] RESET_CTRL_REG    = 32'h0000_0000;
  localparam bit [31:0] RESET_CONFIG_REG  = 32'h0000_0000;

  // ---------------------------------------------------------------------------
  // Cau hinh ky vong
  // ---------------------------------------------------------------------------
  class apb_cfg extends uvm_object;

    uvm_active_passive_enum is_active = UVM_ACTIVE;

    bit [15:0] expected_version     = RESET_VERSION;
    bit [31:0] expected_baud_reg    = RESET_BAUD_REG;
    bit [15:0] expected_baud_div    = RESET_BAUD_DIV;
    bit [31:0] expected_thresh_reg  = RESET_THRESH_REG;
    bit [15:0] expected_thresh_out  = RESET_THRESH_OUT;
    bit [31:0] expected_ctrl_reg    = RESET_CTRL_REG;
    bit [31:0] expected_config_reg  = RESET_CONFIG_REG;

    function new(string name = "apb_cfg");
      super.new(name);
    endfunction

  endclass : apb_cfg

  // ---------------------------------------------------------------------------
  // Sequence item: mot giao dich APB
  // ---------------------------------------------------------------------------
  class apb_item extends uvm_sequence_item;

    rand bit [31:0] paddr;
    rand bit [31:0] pwdata;
    rand bit        pwrite;

    bit [31:0] rdata;
    bit        ready;
    bit        err;
    bit        completed;
    string     op_name;
    int unsigned latency;

    // Gia tri quan sat tren DUT tai canh ACCESS (monitor latch).
    // Dung de kiem tra side-effect cua ghi thanh ghi.
    bit        obs_enable;
    bit        obs_start;
    bit        obs_soft_reset;
    bit        obs_ble_enable;
    bit        obs_uart_enable;
    bit [15:0] obs_baud_div;
    bit [15:0] obs_thresh_out;
    bit        obs_busy;
    bit        obs_done;
    bit        obs_overflow;
    bit [1:0]  obs_class_code;

    `uvm_object_utils_begin(apb_item)
      `uvm_field_int(paddr,   UVM_ALL_ON)
      `uvm_field_int(pwdata,  UVM_ALL_ON)
      `uvm_field_int(pwrite,  UVM_ALL_ON)
      `uvm_field_int(rdata,   UVM_ALL_ON)
      `uvm_field_int(ready,   UVM_ALL_ON)
      `uvm_field_int(err,     UVM_ALL_ON)
      `uvm_field_string(op_name, UVM_ALL_ON)
    `uvm_object_utils_end

    constraint c_addr  { paddr[7:0] inside {[ADDR_CTRL:ADDR_CONFIG]}; paddr[1:0] == 0; }
    constraint c_write { pwrite dist { 1 := 60, 0 := 40 }; }
    constraint c_data  { pwrite -> pwdata[1:0] == 0; }

    function new(string name = "apb_item");
      super.new(name);
    endfunction

    function string convert2string();
      return $sformatf("%s %-11s @0x%02h%s",
                        pwrite ? "WRITE" : "READ ",
                        op_name, paddr[7:0],
                        pwrite ? $sformatf(" <= 0x%08h", pwdata)
                               : $sformatf(" => 0x%08h", rdata));
    endfunction

  endclass : apb_item

  // ---------------------------------------------------------------------------
  // Sequencer
  // ---------------------------------------------------------------------------
  class apb_sequencer extends uvm_sequencer #(apb_item);
    `uvm_component_utils(apb_sequencer)
    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction
  endclass : apb_sequencer

  // ---------------------------------------------------------------------------
  // Driver: dieu khien bus APB dung 2 phase AMBA3
  //   SETUP  (psel=1, penable=0) -> ACCESS (psel=1, penable=1)
  //   -> cho pready (co guard chong treo) -> ket thuc (psel=0, penable=0)
  // Chi doc prdata khi pwrite = 0.
  // ---------------------------------------------------------------------------
  class apb_driver extends uvm_driver #(apb_item);

    `uvm_component_utils(apb_driver)

    virtual apb_slave_if_if vif;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db#(virtual apb_slave_if_if)::get(this, "", "vif", vif))
        `uvm_fatal(get_type_name(), "virtual interface 'vif' chua duoc set")
    endfunction

    task run_phase(uvm_phase phase);
      apb_item req;
      forever begin
        seq_item_port.get_next_item(req);
        drive_transfer(req);
        seq_item_port.item_done();
      end
    endtask

    task drive_transfer(apb_item req);
      int unsigned guard;

      req.latency   = 0;
      req.completed = 0;

      // ---- PHASE 1: SETUP (psel=1, penable=0) ----
      @(vif.drv_cb);
      vif.drv_cb.paddr   <= req.paddr;
      vif.drv_cb.pwdata  <= req.pwrite ? req.pwdata : 32'h0;
      vif.drv_cb.pwrite  <= req.pwrite;
      vif.drv_cb.psel    <= 1'b1;
      vif.drv_cb.penable <= 1'b0;

      // ---- PHASE 2: ACCESS (psel=1, penable=1) ----
      @(vif.drv_cb);
      vif.drv_cb.penable <= 1'b1;

      // ---- Cho pready ----
      guard = 0;
      do begin
        @(vif.drv_cb);
        req.latency++;
        guard++;
      end while (!vif.drv_cb.pready && guard < 200);

      if (!vif.drv_cb.pready)
        `uvm_error(get_type_name(),
          $sformatf("Timeout cho pready khi giao dich @0x%02h", req.paddr[7:0]))

      // Chi doc du lieu khi giao dich doc
      if (!req.pwrite) req.rdata = vif.drv_cb.prdata;
      req.ready     = vif.drv_cb.pready;
      req.err       = vif.drv_cb.pslverr;
      req.completed = 1;

      // ---- Ket thuc transfer ----
      @(vif.drv_cb);
      vif.drv_cb.psel    <= 1'b0;
      vif.drv_cb.penable <= 1'b0;
    endtask : drive_transfer

  endclass : apb_driver

  // ---------------------------------------------------------------------------
  // Monitor
  //   - Vong lap phat hien SETUP (psel=1, penable=0) -> tao giao dich moi
  //   - Vong lap phat hien ACCESS (psel=1, penable=1) -> latch gia tri DUT
  //     va phat giao dich khi pready = 1
  // ---------------------------------------------------------------------------
  class apb_monitor extends uvm_monitor;

    `uvm_component_utils(apb_monitor)

    virtual apb_slave_if_if vif;
    uvm_analysis_port #(apb_item) ap;
    int unsigned xfer_count;

    function new(string name, uvm_component parent);
      super.new(name, parent);
      ap = new("ap", this);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db#(virtual apb_slave_if_if)::get(this, "", "vif", vif))
        `uvm_fatal(get_type_name(), "virtual interface 'vif' chua duoc set")
    endfunction

    task run_phase(uvm_phase phase);
      apb_item tr;
      bit        seen_setup;
      bit        latched;
      int unsigned ticks;
      int unsigned t_setup;

      seen_setup = 0;
      latched    = 0;
      ticks      = 0;

      forever begin
        @(vif.mon_cb);
        ticks++;

        if (vif.mon_cb.psel && !vif.mon_cb.penable) begin
          // ---- SETUP phase: tao giao dich moi ----
          seen_setup = 1;
          latched    = 0;
          t_setup    = ticks;
          tr = apb_item::type_id::create("tr");
          tr.paddr  = vif.mon_cb.paddr;
          tr.pwrite = vif.mon_cb.pwrite;
          tr.pwdata = vif.mon_cb.pwdata;
        end
        else if (seen_setup && vif.mon_cb.psel && vif.mon_cb.penable) begin
          // ---- ACCESS phase: latch gia tri quan sat tren DUT ----
          if (!latched) begin
            latched      = 1;
            tr.rdata      = vif.mon_cb.prdata;
            tr.obs_enable = vif.mon_cb.sys_enable;
            tr.obs_start  = vif.mon_cb.sys_start;
            tr.obs_soft_reset = vif.mon_cb.soft_reset;
            tr.obs_ble_enable  = vif.mon_cb.ble_enable;
            tr.obs_uart_enable = vif.mon_cb.uart_enable;
            tr.obs_baud_div    = vif.mon_cb.baud_div;
            // RTL moi dung ecg_threshold, RTL cu dung ppg_threshold.
            // Bien khong noi vao DUT se giu gia tri X -> bo qua qua do.
            if (vif.mon_cb.ecg_threshold !== 16'hxxxx)
              tr.obs_thresh_out = vif.mon_cb.ecg_threshold;
            else
              tr.obs_thresh_out = vif.mon_cb.ppg_threshold;
            tr.obs_busy       = vif.mon_cb.sys_busy;
            tr.obs_done       = vif.mon_cb.sys_done;
            tr.obs_overflow   = vif.mon_cb.sys_overflow;
            tr.obs_class_code = vif.mon_cb.sys_class_code;
          end

          if (vif.mon_cb.pready) begin
            tr.ready     = 1;
            tr.err       = vif.mon_cb.pslverr;
            tr.completed = 1;
            tr.op_name   = reg_name(tr.paddr);
            tr.latency   = ticks - t_setup;
            `uvm_info(get_type_name(), tr.convert2string(), UVM_HIGH)
            ap.write(tr);
            xfer_count++;
            seen_setup = 0;
            latched    = 0;
          end
        end
      end
    endtask

    function string reg_name(bit [31:0] a);
      case (a[7:0])
        ADDR_CTRL:    return "CTRL";
        ADDR_STATUS:  return "STATUS";
        ADDR_THRESH:  return "ECG_THRESH";
        ADDR_BAUD:    return "BAUD";
        ADDR_RESULT:  return "RESULT";
        ADDR_VERSION: return "VERSION";
        ADDR_CONFIG:  return "CONFIG";
        default:      return "UNKNOWN";
      endcase
    endfunction

  endclass : apb_monitor

  // ---------------------------------------------------------------------------
  // Agent
  // ---------------------------------------------------------------------------
  class apb_agent extends uvm_agent;

    `uvm_component_utils(apb_agent)

    apb_sequencer sequencer;
    apb_driver    driver;
    apb_monitor   monitor;
    uvm_analysis_port #(apb_item) ap;

    function new(string name, uvm_component parent);
      super.new(name, parent);
      ap = new("ap", this);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      sequencer = apb_sequencer::type_id::create("sequencer", this);
      monitor   = apb_monitor::type_id::create("monitor", this);
      if (is_active == UVM_ACTIVE)
        driver = apb_driver::type_id::create("driver", this);
    endfunction

    function void connect_phase(uvm_phase phase);
      super.connect_phase(phase);
      monitor.ap.connect(ap);
      if (is_active == UVM_ACTIVE)
        driver.seq_item_port.connect(sequencer.seq_item_export);
    endfunction

  endclass : apb_agent

  // ---------------------------------------------------------------------------
  // Scoreboard: mo hinh tham chieu 7 thanh ghi
  // ---------------------------------------------------------------------------
  class apb_scoreboard extends uvm_scoreboard;

    `uvm_component_utils(apb_scoreboard)

    uvm_analysis_imp #(apb_item, apb_scoreboard) analysis_export;
    apb_cfg cfg;

    bit [31:0] ctrl_reg;
    bit [31:0] thresh_reg;
    bit [31:0] baud_reg;
    bit [31:0] config_reg;

    int unsigned n_write;
    int unsigned n_read;
    int unsigned n_error;

    function new(string name, uvm_component parent);
      super.new(name, parent);
      analysis_export = new("analysis_export", this);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db#(apb_cfg)::get(this, "", "cfg", cfg))
        `uvm_fatal(get_type_name(), "apb_cfg chua duoc set")
    endfunction

    function void reset_model();
      ctrl_reg   = cfg.expected_ctrl_reg;
      thresh_reg = cfg.expected_thresh_reg;
      baud_reg   = cfg.expected_baud_reg;
      config_reg = cfg.expected_config_reg;
    endfunction

    function void write(apb_item tr);
      bit [31:0] expected;

      if (!tr.completed) return;

      if (tr.pwrite) begin
        n_write++;
        case (tr.paddr[7:0])
          ADDR_CTRL: begin
            ctrl_reg = tr.pwdata;
            if (tr.obs_enable !== tr.pwdata[0])
              `uvm_error(get_type_name(),
                $sformatf("CTRL: sys_enable=%b, mong doi %b", tr.obs_enable, tr.pwdata[0]))
            if (tr.pwdata[1] && (tr.obs_start !== 1'b1))
              `uvm_error(get_type_name(), "CTRL: khong thay xung sys_start khi ghi bit[1]")
            if (tr.pwdata[4] && (tr.obs_soft_reset !== 1'b1))
              `uvm_error(get_type_name(), "CTRL: khong thay xung soft_reset khi ghi bit[4]")
          end
          ADDR_THRESH: begin
            thresh_reg = tr.pwdata;
            if (tr.obs_thresh_out !== tr.pwdata[15:0])
              `uvm_error(get_type_name(),
                $sformatf("ECG_THRESH: output=%0h, mong doi %0h",
                          tr.obs_thresh_out, tr.pwdata[15:0]))
          end
          ADDR_BAUD: begin
            baud_reg = tr.pwdata;
            if (tr.obs_baud_div !== tr.pwdata[15:0])
              `uvm_error(get_type_name(),
                $sformatf("BAUD: baud_div=%0d, mong doi %0d",
                          tr.obs_baud_div, tr.pwdata[15:0]))
          end
          ADDR_CONFIG: begin
            config_reg = tr.pwdata;
            if (tr.obs_ble_enable !== tr.pwdata[0])
              `uvm_error(get_type_name(),
                $sformatf("CONFIG: ble_enable=%b, mong doi %b", tr.obs_ble_enable, tr.pwdata[0]))
            if (tr.obs_uart_enable !== tr.pwdata[1])
              `uvm_error(get_type_name(),
                $sformatf("CONFIG: uart_enable=%b, mong doi %b", tr.obs_uart_enable, tr.pwdata[1]))
          end
          // STATUS / RESULT / VERSION: chi doc, ghi bi bo qua
          default: ;
        endcase
      end
      else begin
        n_read++;
        expected = predict_read(tr);
        if (tr.rdata !== expected) begin
          n_error++;
          `uvm_error(get_type_name(),
            $sformatf("%s @0x%02h: doc 0x%08h, mong doi 0x%08h",
                      tr.op_name, tr.paddr[7:0], tr.rdata, expected))
        end
        else begin
          `uvm_info(get_type_name(), tr.convert2string(), UVM_MEDIUM)
        end
      end
    endfunction

    function bit [31:0] predict_read(apb_item tr);
      bit [31:0] r;
      r = 32'h0;
      case (tr.paddr[7:0])
        ADDR_CTRL:    r = ctrl_reg;
        ADDR_STATUS:  begin
          r[0] = tr.obs_busy;
          r[1] = tr.obs_done;
          r[3] = tr.obs_overflow;
        end
        ADDR_THRESH:  r = thresh_reg;
        ADDR_BAUD:    r = baud_reg;
        ADDR_RESULT:  r = {30'h0, tr.obs_class_code};
        ADDR_VERSION: r = {16'h0, cfg.expected_version};
        ADDR_CONFIG:  r = config_reg;
        default:      r = 32'h0;
      endcase
      return r;
    endfunction

    function void report_phase(uvm_phase phase);
      `uvm_info(get_type_name(),
        $sformatf("Scoreboard: %0d write, %0d read, %0d mismatch",
                  n_write, n_read, n_error), UVM_LOW)
    endfunction

  endclass : apb_scoreboard

  // ---------------------------------------------------------------------------
  // Coverage subscriber
  // ---------------------------------------------------------------------------
  class apb_coverage extends uvm_subscriber #(apb_item);

    `uvm_component_utils(apb_coverage)

    bit [7:0] last_addr;
    bit       last_write;
    int unsigned ready_latency;

    covergroup cg_apb;
      option.per_instance = 1;
      option.name         = "apb_cg";

      cp_addr : coverpoint last_addr {
        bins ctrl    = {ADDR_CTRL};
        bins status  = {ADDR_STATUS};
        bins thresh  = {ADDR_THRESH};
        bins baud    = {ADDR_BAUD};
        bins result  = {ADDR_RESULT};
        bins version = {ADDR_VERSION};
        bins cfg     = {ADDR_CONFIG};
        bins others  = default;
      }
      cp_op : coverpoint last_write {
        bins write = {1};
        bins read  = {0};
      }
      cp_lat : coverpoint ready_latency {
        bins fast = {[0:2]};
        bins mid  = {[3:5]};
        bins slow = {[6:20]};
      }
      x_read_write : cross cp_addr, cp_op;
    endgroup : cg_apb

    function new(string name, uvm_component parent);
      super.new(name, parent);
      cg_apb = new();
    endfunction

    function void write(apb_item tr);
      if (!tr.completed) return;
      last_addr     = tr.paddr[7:0];
      last_write    = tr.pwrite;
      ready_latency = tr.latency;
      cg_apb.sample();
    endfunction

    function void report_phase(uvm_phase phase);
      `uvm_info(get_type_name(),
        $sformatf("Coverage: %0.2f%%", cg_apb.get_inst_coverage()), UVM_LOW)
    endfunction

  endclass : apb_coverage

  // ---------------------------------------------------------------------------
  // Base test
  // ---------------------------------------------------------------------------
  class apb_base_test extends uvm_test;

    `uvm_component_utils(apb_base_test)

    apb_cfg        cfg;
    apb_agent      agent;
    apb_scoreboard sb;
    apb_coverage   cov;

    virtual apb_slave_if_if vif;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);

      cfg = apb_cfg::type_id::create("cfg");
      cfg.expected_version   = RESET_VERSION;
      cfg.expected_baud_reg  = RESET_BAUD_REG;
      cfg.expected_baud_div  = RESET_BAUD_DIV;
      cfg.expected_thresh_reg = RESET_THRESH_REG;
      cfg.expected_thresh_out = RESET_THRESH_OUT;
      cfg.expected_ctrl_reg   = RESET_CTRL_REG;
      cfg.expected_config_reg = RESET_CONFIG_REG;

      uvm_config_db#(apb_cfg)::set(this, "*", "cfg", cfg);

      if (!uvm_config_db#(virtual apb_slave_if_if)::get(this, "", "vif", vif))
        `uvm_fatal(get_type_name(), "virtual interface 'vif' chua duoc set")
      uvm_config_db#(virtual apb_slave_if_if)::set(this, "*", "vif", vif);

      agent = apb_agent::type_id::create("agent", this);
      sb    = apb_scoreboard::type_id::create("sb", this);
      cov   = apb_coverage::type_id::create("cov", this);
    endfunction

    function void connect_phase(uvm_phase phase);
      super.connect_phase(phase);
      agent.ap.connect(sb.analysis_export);
      agent.ap.connect(cov.analysis_export);
    endfunction

    function void end_of_elaboration_phase(uvm_phase phase);
      super.end_of_elaboration_phase(phase);
      sb.reset_model();
    endfunction

    task reset_dut();
      vif.presetn <= 1'b0;
      repeat (5) @(posedge vif.pclk);
      vif.presetn <= 1'b1;
      repeat (2) @(posedge vif.pclk);
    endtask

    function void report_phase(uvm_phase phase);
      uvm_report_server svr;
      super.report_phase(phase);
      svr = uvm_report_server::get_server();
      `uvm_info("SUMMARY",
        $sformatf("UVM_ERROR=%0d  UVM_FATAL=%0d",
                  svr.get_severity_count(UVM_ERROR),
                  svr.get_severity_count(UVM_FATAL)), UVM_NONE)
    endfunction

  endclass : apb_base_test

  // ---------------------------------------------------------------------------
  // Sequence 1: doc het 7 thanh ghi, roi ghi va doc lai
  // ---------------------------------------------------------------------------
  class apb_reg_seq extends uvm_sequence #(apb_item);

    `uvm_object_utils(apb_reg_seq)

    function new(string name = "apb_reg_seq");
      super.new(name);
    endfunction

    task body();
      apb_item it;
      bit [31:0] addrs[7];
      addrs[0] = ADDR_CTRL;
      addrs[1] = ADDR_STATUS;
      addrs[2] = ADDR_THRESH;
      addrs[3] = ADDR_BAUD;
      addrs[4] = ADDR_RESULT;
      addrs[5] = ADDR_VERSION;
      addrs[6] = ADDR_CONFIG;

      // 1) Doc tat ca thanh ghi (kiem tra readback sau reset)
      foreach (addrs[i]) begin
        it = apb_item::type_id::create($sformatf("rd_%0d", i));
        start_item(it);
        it.pwrite = 1'b0;
        it.paddr  = addrs[i];
        finish_item(it);
      end

      // 2) Ghi roi doc lai
      foreach (addrs[i]) begin
        it = apb_item::type_id::create($sformatf("wr_%0d", i));
        start_item(it);
        it.pwrite = 1'b1;
        it.paddr  = addrs[i];
        it.pwdata = (i == 0) ? 32'h0000_0003         // CTRL: enable + start
               : (i == 2) ? 32'h0000_00A0             // ECG_THRESH
               : (i == 3) ? {16'h0, WRITE_BAUD_VALUE} // BAUD
               : (i == 6) ? 32'h0000_0003             // CONFIG: ble + uart
                          : 32'h0000_0000;
        finish_item(it);

        it = apb_item::type_id::create($sformatf("rdback_%0d", i));
        start_item(it);
        it.pwrite = 1'b0;
        it.paddr  = addrs[i];
        finish_item(it);
      end
    endtask

  endclass : apb_reg_seq

  // ---------------------------------------------------------------------------
  // Sequence 2: doc/ghi ngau nhien tren ca 7 thanh ghi
  // ---------------------------------------------------------------------------
  class apb_random_seq extends uvm_sequence #(apb_item);

    `uvm_object_utils(apb_random_seq)

    int unsigned n_items = 40;

    function new(string name = "apb_random_seq");
      super.new(name);
    endfunction

    task body();
      apb_item it;
      repeat (n_items) begin
        it = apb_item::type_id::create("it");
        start_item(it);
        it.pwrite = $urandom_range(0, 1);
        it.paddr  = 32'h00 + 4 * $urandom_range(0, 6);
        if (it.pwrite) it.pwdata = $urandom;
        finish_item(it);
      end
    endtask

  endclass : apb_random_seq

  // ---------------------------------------------------------------------------
  // Sequence 3: dieu khien status roi doc STATUS va RESULT
  // ---------------------------------------------------------------------------
  class apb_status_seq extends uvm_sequence #(apb_item);

    `uvm_object_utils(apb_status_seq)

    virtual apb_slave_if_if vif;

    function new(string name = "apb_status_seq");
      super.new(name);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db#(virtual apb_slave_if_if)::get(this, "", "vif", vif))
        `uvm_fatal(get_type_name(), "virtual interface 'vif' chua duoc set")
    endfunction

    task body();
      apb_item it;

      // busy = 1, done = 0
      vif.sys_busy       = 1'b1;
      vif.sys_done       = 1'b0;
      vif.sys_overflow   = 1'b0;
      vif.sys_class_code = 2'b10;
      repeat (3) @(posedge vif.pclk);

      it = apb_item::type_id::create("rd_status_busy");
      start_item(it);
      it.pwrite = 1'b0;
      it.paddr  = ADDR_STATUS;
      finish_item(it);

      // busy = 0, done = 1, overflow = 1
      vif.sys_busy     = 1'b0;
      vif.sys_done     = 1'b1;
      vif.sys_overflow = 1'b1;
      repeat (3) @(posedge vif.pclk);

      it = apb_item::type_id::create("rd_status_done");
      start_item(it);
      it.pwrite = 1'b0;
      it.paddr  = ADDR_STATUS;
      finish_item(it);

      // RESULT phai tra ve sys_class_code
      it = apb_item::type_id::create("rd_result");
      start_item(it);
      it.pwrite = 1'b0;
      it.paddr  = ADDR_RESULT;
      finish_item(it);

      // tra ve trang thai ban dau
      vif.sys_busy       = 1'b0;
      vif.sys_done       = 1'b0;
      vif.sys_overflow   = 1'b0;
      vif.sys_class_code = 2'b00;
      repeat (3) @(posedge vif.pclk);
    endtask

  endclass : apb_status_seq

  // ---------------------------------------------------------------------------
  // Smoke test: chay ca 3 sequence
  // ---------------------------------------------------------------------------
  class apb_smoke_test extends apb_base_test;

    `uvm_component_utils(apb_smoke_test)

    apb_reg_seq    reg_seq;
    apb_random_seq rnd_seq;
    apb_status_seq status_seq;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
      phase.raise_objection(this);

      reset_dut();

      reg_seq = apb_reg_seq::type_id::create("reg_seq");
      reg_seq.start(this.sequencer);

      status_seq = apb_status_seq::type_id::create("status_seq");
      status_seq.start(this.sequencer);

      rnd_seq = apb_random_seq::type_id::create("rnd_seq");
      rnd_seq.start(this.sequencer);

      #(200 * 1ns);
      phase.drop_objection(this);
    endtask

  endclass : apb_smoke_test

endpackage : apb_slave_if_env_pkg

`endif
