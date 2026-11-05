@echo off
setlocal EnableExtensions
rem ============================================================================
rem ECG ROM Demo - QuestaSim GUI launcher (tb_demo_rom)
rem
rem Usage:   run_gui_demo.bat
rem
rem Behavior (mirrors scripts\gui\run_gui.bat but for the DEMO top):
rem   - Own library work_demo (simlib\work_demo) because the demo adds
rem     demo/*.v sources + the golden include (+incdir+..), so it is NOT
rem     the same build as the product work_reg lib.
rem   - Builds work_demo if missing, then opens ONE vsim GUI with Transcript,
rem     loads wave_tb_demo_rom.do (grouped signals), runs to completion,
rem     zooms the waveform to the first window's packet region, KEEPS open.
rem   - NOTE: the agent cannot read the desktop; the .do self-reports a final
rem     [wave] summary line in the Transcript (see AUTOMATION_STATUS §5).
rem ============================================================================

set QUESTA_ROOT=H:\questasim64_10.7c
set "VLOG=%QUESTA_ROOT%\win64\vlog.exe"
set "VSIM=%QUESTA_ROOT%\win64\vsim.exe"
set "VLIB=%QUESTA_ROOT%\win64\vlib.exe"
set REPO=H:\IC Design\Code\ECG\ecg-thinh-uvm
set SIMLIB=%REPO%\simlib

set "TB_TOP=tb_demo_rom"
set "WAVE_DO=%REPO%\scripts\gui\wave_tb_demo_rom.do"

if not exist "%SIMLIB%\work_demo\_lib.qdb" goto build
goto open

:build
echo [gui-demo] work_demo library missing - building ...
echo [gui-demo] regenerating demo ROM hex + golden first ...
pushd "%REPO%"
python -I demo\ecg_convert.py --start 1000 --n 2048 --channel 0 --out demo\ecg_rom.hex
python -I demo\golden_model.py
popd
pushd "%SIMLIB%"
"%VLIB%" work_demo
rem NB: relative ../ paths + +incdir+.. so no spaced absolute path reaches vlog
"%VLOG%" -sv -work work_demo ^
    "..\demo\ecg_rom.v" "..\demo\sample_pacer.v" ^
    "..\demo\demo_apb_seq.v" "..\demo\demo_uart_packetizer.v" ^
    "..\demo\top_ecg_rom_demo.v" ^
    "..\adc\adc_interface.v" "..\window\window_buffer.v" ^
    "..\feature\feature_extraction.v" "..\ai\ai_classifier.v" ^
    "..\control\control_fsm.v" "..\apb\apb_slave_if.v" ^
    "..\uart\uart_tx.v" ^
    "..\tb\%TB_TOP%.sv" +incdir+..
if errorlevel 1 goto buildfail
popd
goto open

:buildfail
popd
echo [gui-demo] build failed - see messages above.
exit /b 1

:open
echo [gui-demo] opening GUI for %TB_TOP% ...
pushd "%SIMLIB%"
if exist "%WAVE_DO%" (
    rem FAST demo config: 2048 samples @ gap ~1500 cyc + drain, 50 MHz.
    rem First packet region is well before the stream ends; zoom 0..300us.
    start "" "%VSIM%" -work work_demo %TB_TOP% -do "do \"%WAVE_DO%\"; run -all; wave zoom range 0ns 300000ns"
) else (
    start "" "%VSIM%" -work work_demo %TB_TOP% -do "run -all"
)
exit /b 0

:usage
echo Usage: run_gui_demo.bat
exit /b 1
