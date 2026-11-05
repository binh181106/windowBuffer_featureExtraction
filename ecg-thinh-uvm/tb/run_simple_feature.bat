@echo off
cd /d D:\OneDrive\research\rtl\tb
E:\iverilog\bin\iverilog.exe -g2005-sv -o tb_feature_simple.vvp tb_feature_simple.sv ..\feature\feature_extraction.v
E:\iverilog\bin\vvp.exe tb_feature_simple.vvp
