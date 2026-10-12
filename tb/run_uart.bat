@echo off
cd /d D:\OneDrive\research\rtl\tb
del tb_uart.vvp >nul 2>&1
E:\iverilog\bin\iverilog.exe -g2005-sv -o tb_uart.vvp tb_uart_tx.sv ..\uart\uart_tx.v
if %ERRORLEVEL% EQU 0 E:\iverilog\bin\vvp.exe tb_uart.vvp
