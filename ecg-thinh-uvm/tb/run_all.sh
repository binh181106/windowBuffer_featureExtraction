@echo off
REM =============================================================================
REM Run all testbenches for ECG Classifier
REM Usage: run_all.bat
REM =============================================================================

echo ========================================
echo ECG Classifier Testbench Runner
echo ========================================
echo.

cd /d %~dp0

REM Check for Icarus Verilog
where iverilog >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo ERROR: Icarus Verilog not found!
    echo Please install Icarus Verilog and add to PATH
    echo Download: https://bleyer.org/icarus/
    exit /b 1
)

set RTL_DIR=..

REM APB Slave Interface Test
echo.
echo [1/8] Running APB Slave Interface Test...
iverilog -g2005-sv -o tb_apb_slave_if.vvp tb_apb_slave_if.sv %RTL_DIR%\apb\apb_slave_if.v
if %ERRORLEVEL% NEQ 0 (
    echo FAILED: APB test compilation error
    exit /b 1
)
vvp tb_apb_slave_if.vvp
echo.

REM ADC Interface Test
echo.
echo [2/8] Running ADC Interface Test...
iverilog -g2005-sv -o tb_adc_interface.vvp tb_adc_interface.sv %RTL_DIR%\adc\adc_interface.v
if %ERRORLEVEL% NEQ 0 (
    echo FAILED: ADC test compilation error
    exit /b 1
)
vvp tb_adc_interface.vvp
echo.

REM Window Buffer Test
echo.
echo [3/8] Running Window Buffer Test...
iverilog -g2005-sv -o tb_window_buffer.vvp tb_window_buffer.sv %RTL_DIR%\window\window_buffer.v
if %ERRORLEVEL% NEQ 0 (
    echo FAILED: Window test compilation error
    exit /b 1
)
vvp tb_window_buffer.vvp
echo.

REM Feature Extraction Test
echo.
echo [4/8] Running Feature Extraction Test...
iverilog -g2005-sv -o tb_feature_extraction.vvp tb_feature_extraction.sv %RTL_DIR%\feature\feature_extraction.v
if %ERRORLEVEL% NEQ 0 (
    echo FAILED: Feature test compilation error
    exit /b 1
)
vvp tb_feature_extraction.vvp
echo.

REM Control FSM Test
echo.
echo [5/8] Running Control FSM Test...
iverilog -g2005-sv -o tb_control_fsm.vvp tb_control_fsm.sv %RTL_DIR%\control\control_fsm.v
if %ERRORLEVEL% NEQ 0 (
    echo FAILED: Control FSM test compilation error
    exit /b 1
)
vvp tb_control_fsm.vvp
echo.

REM UART TX Test
echo.
echo [6/8] Running UART TX Test...
iverilog -g2005-sv -o tb_uart_tx.vvp tb_uart_tx.sv %RTL_DIR%\uart\uart_tx.v
if %ERRORLEVEL% NEQ 0 (
    echo FAILED: UART test compilation error
    exit /b 1
)
vvp tb_uart_tx.vvp
echo.

REM AI Classifier Test
echo.
echo [7/8] Running AI Classifier Test...
set RTL_SOURCES=%RTL_DIR%\apb\apb_slave_if.v %RTL_DIR%\adc\adc_interface.v %RTL_DIR%\window\window_buffer.v %RTL_DIR%\feature\feature_extraction.v %RTL_DIR%\ai\ai_classifier.v %RTL_DIR%\ai\mlp_weights_rom.v %RTL_DIR%\control\control_fsm.v %RTL_DIR%\uart\uart_tx.v %RTL_DIR%\top\top_ecg_classifier.v
iverilog -g2005-sv -o tb_ai_classifier.vvp tb_ai_classifier.sv %RTL_SOURCES%
if %ERRORLEVEL% NEQ 0 (
    echo FAILED: AI test compilation error
    exit /b 1
)
vvp tb_ai_classifier.vvp
echo.

REM Top-Level Test
echo.
echo [8/8] Running Top-Level Test...
iverilog -g2005-sv -o tb_top_ecg_classifier.vvp tb_top_ecg_classifier.sv %RTL_SOURCES%
if %ERRORLEVEL% NEQ 0 (
    echo FAILED: Top test compilation error
    exit /b 1
)
vvp tb_top_ecg_classifier.vvp
echo.

echo ========================================
echo All testbenches completed!
echo ========================================
