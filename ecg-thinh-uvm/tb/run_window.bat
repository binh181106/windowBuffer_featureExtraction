@echo off
cd /d D:\OneDrive\research\rtl\tb
del tb_window.vvp >nul 2>&1
del tb_window_buffer.vcd >nul 2>&1
E:\iverilog\bin\iverilog.exe -g2005-sv -o tb_window.vvp tb_window_buffer.sv ..\window\window_buffer.v
if %ERRORLEVEL% EQU 0 (
    E:\iverilog\bin\vvp.exe tb_window.vvp
)
