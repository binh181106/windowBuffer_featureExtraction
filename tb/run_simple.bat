@echo off
cd /d D:\OneDrive\research\rtl\tb
E:\iverilog\bin\iverilog.exe -g2005-sv -o tb_window_simple.vvp tb_window_simple.sv ..\window\window_buffer.v
E:\iverilog\bin\vvp.exe tb_window_simple.vvp
