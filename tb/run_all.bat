@echo off
cd /d %~dp0
echo ========================================
echo ECG Classifier RTL Test Suite
echo ========================================
echo.

echo [1/8] APB Slave Interface...
E:\iverilog\bin\iverilog.exe -g2005-sv -o tb_apb.vvp tb_apb_slave_if.sv ..\apb\apb_slave_if.v
E:\iverilog\bin\vvp.exe tb_apb.vvp
echo.

echo [2/8] ADC Interface...
E:\iverilog\bin\iverilog.exe -g2005-sv -o tb_adc.vvp tb_adc_interface.sv ..\adc\adc_interface.v
E:\iverilog\bin\vvp.exe tb_adc.vvp
echo.

echo [3/8] Window Buffer...
E:\iverilog\bin\iverilog.exe -g2005-sv -o tb_window.vvp tb_window_buffer.sv ..\window\window_buffer.v
E:\iverilog\bin\vvp.exe tb_window.vvp
echo.

echo [4/8] Feature Extraction...
E:\iverilog\bin\iverilog.exe -g2005-sv -o tb_feature.vvp tb_feature_extraction.sv ..\feature\feature_extraction.v
E:\iverilog\bin\vvp.exe tb_feature.vvp
echo.

echo [5/8] Control FSM...
E:\iverilog\bin\iverilog.exe -g2005-sv -o tb_control.vvp tb_control_fsm.sv ..\control\control_fsm.v
E:\iverilog\bin\vvp.exe tb_control.vvp
echo.

echo [6/8] UART TX...
E:\iverilog\bin\iverilog.exe -g2005-sv -o tb_uart.vvp tb_uart_tx.sv ..\uart\uart_tx.v
E:\iverilog\bin\vvp.exe tb_uart.vvp
echo.

echo ========================================
echo Tests Complete
echo ========================================
