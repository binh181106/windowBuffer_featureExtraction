# =============================================================================
# Makefile for ECG Classifier Testbenches
# =============================================================================
# Usage: make <target>
# Targets:
#   all      - Run all testbenches
#   apb      - Run APB slave interface test
#   adc      - Run ADC interface test
#   window   - Run window buffer test
#   feature  - Run feature extraction test
#   control  - Run control FSM test
#   uart     - Run UART TX test
#   ai       - Run AI classifier test
#   top      - Run top-level test
#   clean    - Clean simulation files
# =============================================================================

# Directories
RTL_DIR = ..
TB_DIR = .
VVP = vvp
IVL = iverilog

# Source files
RTL_SOURCES = $(RTL_DIR)/apb/apb_slave_if.v \
              $(RTL_DIR)/adc/adc_interface.v \
              $(RTL_DIR)/window/window_buffer.v \
              $(RTL_DIR)/feature/feature_extraction.v \
              $(RTL_DIR)/ai/ai_classifier.v \
              $(RTL_DIR)/ai/mlp_weights_rom.v \
              $(RTL_DIR)/control/control_fsm.v \
              $(RTL_DIR)/uart/uart_tx.v \
              $(RTL_DIR)/top/top_ecg_classifier.v

# Testbenches
TB_APB = tb_apb_slave_if.sv
TB_ADC = tb_adc_interface.sv
TB_WINDOW = tb_window_buffer.sv
TB_FEATURE = tb_feature_extraction.sv
TB_CONTROL = tb_control_fsm.sv
TB_UART = tb_uart_tx.sv
TB_AI = tb_ai_classifier.sv
TB_TOP = tb_top_ecg_classifier.sv

# Waveform files
VCD_FILES = tb_apb_slave_if.vcd \
            tb_adc_interface.vcd \
            tb_window_buffer.vcd \
            tb_feature_extraction.vcd \
            tb_control_fsm.vcd \
            tb_uart_tx.vcd \
            tb_ai_classifier.vcd \
            tb_top_ecg_classifier.vcd

# =============================================================================
# Targets
# =============================================================================

.PHONY: all clean apb adc window feature control uart ai top help

all: apb adc window feature control uart ai top

help:
	@echo "ECG Classifier Testbench Makefile"
	@echo ""
	@echo "Usage: make <target>"
	@echo ""
	@echo "Testbench targets:"
	@echo "  all     - Run all testbenches"
	@echo "  apb     - APB slave interface test"
	@echo "  adc     - ADC interface test"
	@echo "  window  - Window buffer test"
	@echo "  feature - Feature extraction test"
	@echo "  control - Control FSM test"
	@echo "  uart    - UART TX test"
	@echo "  ai      - AI classifier test"
	@echo "  top     - Top-level test"
	@echo "  clean   - Clean simulation files"

# APB Slave Interface Test
apb:
	@echo "=== Running APB Slave Interface Test ==="
	cd $(TB_DIR) && $(IVL) -g2005-sv -o tb_apb_slave_if.vvp $(TB_APB) $(RTL_DIR)/apb/apb_slave_if.v && $(VVP) tb_apb_slave_if.vvp

# ADC Interface Test
adc:
	@echo "=== Running ADC Interface Test ==="
	cd $(TB_DIR) && $(IVL) -g2005-sv -o tb_adc_interface.vvp $(TB_ADC) $(RTL_DIR)/adc/adc_interface.v && $(VVP) tb_adc_interface.vvp

# Window Buffer Test
window:
	@echo "=== Running Window Buffer Test ==="
	cd $(TB_DIR) && $(IVL) -g2005-sv -o tb_window_buffer.vvp $(TB_WINDOW) $(RTL_DIR)/window/window_buffer.v && $(VVP) tb_window_buffer.vvp

# Feature Extraction Test
feature:
	@echo "=== Running Feature Extraction Test ==="
	cd $(TB_DIR) && $(IVL) -g2005-sv -o tb_feature_extraction.vvp $(TB_FEATURE) $(RTL_DIR)/feature/feature_extraction.v && $(VVP) tb_feature_extraction.vvp

# Control FSM Test
control:
	@echo "=== Running Control FSM Test ==="
	cd $(TB_DIR) && $(IVL) -g2005-sv -o tb_control_fsm.vvp $(TB_CONTROL) $(RTL_DIR)/control/control_fsm.v && $(VVP) tb_control_fsm.vvp

# UART TX Test
uart:
	@echo "=== Running UART TX Test ==="
	cd $(TB_DIR) && $(IVL) -g2005-sv -o tb_uart_tx.vvp $(TB_UART) $(RTL_DIR)/uart/uart_tx.v && $(VVP) tb_uart_tx.vvp

# AI Classifier Test
ai:
	@echo "=== Running AI Classifier Test ==="
	cd $(TB_DIR) && $(IVL) -g2005-sv -o tb_ai_classifier.vvp $(TB_AI) $(RTL_SOURCES) && $(VVP) tb_ai_classifier.vvp

# Top-Level Test
top:
	@echo "=== Running Top-Level Test ==="
	cd $(TB_DIR) && $(IVL) -g2005-sv -o tb_top_ecg_classifier.vvp $(TB_TOP) $(RTL_SOURCES) && $(VVP) tb_top_ecg_classifier.vvp

# Clean
clean:
	@echo "Cleaning simulation files..."
	cd $(TB_DIR) && rm -f *.vvp *.vcd *.log

# =============================================================================

# =============================================================================
# UVM targets (Questa / ModelSim)
# -----------------------------------------------------------------------------
# uvapb      - chay voi RTL hien tai (trong apb/)
# uvapb_v30  - chay voi +define+APB_RTL_V30 (RTL v3.0: ecg_threshold,
#              VERSION 0x0200, BAUD 437)
#
# Bien UVM_HOME tro toi thu muc src chua uvm_pkg.sv.
# =============================================================================
QUESTA_HOME ?= H:/altera/25.1std/questa_fse/win64
QUESTA_BIN  ?= $(QUESTA_HOME)
UVM_HOME    ?= H:/altera/25.1std/questa_fse/verilog_src/uvm-1.2/src
VLOG  = $(QUESTA_BIN)/vlog
VSIM  = $(QUESTA_BIN)/vsim
UVM_INC = $(UVM_HOME)

UVM_TB_SRCS = uvm/apb_slave_if_if.sv \
              uvm/apb_slave_if_env_pkg.sv \
              uvm/tb_apb_uvm.sv

# RTL dung cho UVM: mac dinh la apb/ cua repo. Neu ban dich chay ngoai
# apb/ thi dat bien APB_RTL_V30=1 de doi sang RTL v3.0.
APB_RTL ?= $(RTL_DIR)/apb/apb_slave_if.v
UVM_DEFS = $(if $(V30),+define+APB_RTL_V30,)

uvapb:
	@echo "=== Running APB UVM Test (RTL hien tai) ==="
	cd $(TB_DIR) && $(VLOG) -sv -mfcu $(UVM_DEFS) \
	  +incdir+$(UVM_INC) $(UVM_HOME)/uvm_pkg.sv \
	  $(APB_RTL) $(UVM_TB_SRCS) && \
	$(VSIM) -c -sv_seed 1 tb.tb_apb_uvm -do "run -all; quit -f"

uvapb_v30:
	@echo "=== Running APB UVM Test (spec v3.0) ==="
	$(MAKE) uvapb V30=1

.PHONY: uvapb uvapb_v30
