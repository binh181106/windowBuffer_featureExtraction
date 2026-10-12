# =============================================================================
# Gowin Synthesis Script for PPG Classifier
# Target: GW5A-LV25UG324C2/I1
# =============================================================================

# Set device
set_device -family GW5A -device GW5A-25 -package UG324 -speed C2

# Set project name
set_project -name ppg_classifier

# =============================================================================
# Design Files
# =============================================================================

# APB Interface
add_file -format verilog rtl/apb/apb_slave_if.v

# ADC Interface
add_file -format verilog rtl/adc/adc_interface.v

# Window Buffer
add_file -format verilog rtl/window/window_buffer.v

# Feature Extraction
add_file -format verilog rtl/feature/feature_extraction.v

# AI Classifier
add_file -format verilog rtl/ai/ai_classifier.v
add_file -format verilog rtl/ai/mlp_weights_rom.v

# Control FSM
add_file -format verilog rtl/control/control_fsm.v

# UART
add_file -format verilog rtl/uart/uart_tx.v

# Top Level
add_file -format verilog rtl/top/top_ppg_classifier.v

# =============================================================================
# Synthesis Options
# =============================================================================

# Set top module
set_top top_ppg_classifier

# Timing constraints
# System clock: 100 MHz (10 ns period)
create_clock -name sys_clk -period 10.0 [get_ports sys_clk]

# Input delays (from ADC)
set_input_delay -clock sys_clk -value 2.0 [get_ports adc_data[*]]
set_input_delay -clock sys_clk -value 2.0 [get_ports adc_valid]

# Output delays (to UART)
set_output_delay -clock sys_clk -value 2.0 [get_ports uart_txd]

# =============================================================================
# Synthesis Options
# =============================================================================

# Enable physical optimization
set_option -physical_opto on

# Enable retiming
set_option -retiming on

# Resource sharing
set_option -resource_sharing on

# Enable FSM extraction
set_option -fsm_extr on

# =============================================================================
# Report Options
# =============================================================================

# Generate reports
report_timing -detail
report_area -hier
report_utilization

# =============================================================================
# Run Synthesis
# =============================================================================

# Run synthesis
run

# =============================================================================
