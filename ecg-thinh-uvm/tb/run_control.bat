@echo off
cd /d D:\OneDrive\research\rtl\tb
del tb_control.vvp >nul 2>&1
E:\iverilog\bin\iverilog.exe -g2005-sv -o tb_control.vvp tb_control_fsm.sv ..\control\control_fsm.v
if %ERRORLEVEL% EQU 0 E:\iverilog\bin\vvp.exe tb_control.vvp
