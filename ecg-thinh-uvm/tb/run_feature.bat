@echo off
cd /d D:\OneDrive\research\rtl\tb
del tb_feature.vvp >nul 2>&1
E:\iverilog\bin\iverilog.exe -g2005-sv -o tb_feature.vvp tb_feature_extraction.sv ..\feature\feature_extraction.v
if %ERRORLEVEL% EQU 0 E:\iverilog\bin\vvp.exe tb_feature.vvp
