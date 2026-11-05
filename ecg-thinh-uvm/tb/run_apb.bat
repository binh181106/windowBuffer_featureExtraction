@echo off
cd /d D:\OneDrive\research\rtl\tb
E:\iverilog\bin\iverilog.exe -g2005-sv -o tb_apb.vvp tb_apb_slave_if.sv ..\apb\apb_slave_if.v
E:\iverilog\bin\vvp.exe tb_apb.vvp
