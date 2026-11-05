@echo off
setlocal EnableExtensions
rem ============================================================================
rem ECG Classifier - QuestaSim GUI launcher (single window)
rem
rem Usage:
rem   run_gui.bat tb_control_fsm
rem   run_gui.bat tb_top_ecg_classifier
rem
rem Behavior:
rem   - Uses the SAME work_reg library as the batch regression (simlib\work_reg).
rem     Builds it first if missing (absolute paths; safe with spaces).
rem   - Opens ONE vsim GUI with Transcript, loads the saved waveform config
rem     (scripts\gui\wave_<tb_top>.do) when present, runs the test to
rem     completion (run -all), zooms the waveform to the active region, and
rem     KEEPS THE GUI OPEN so you can inspect. No "quit -f" in GUI mode.
rem ============================================================================

set QUESTA_ROOT=H:\questasim64_10.7c
set "VLOG=%QUESTA_ROOT%\win64\vlog.exe"
set "VSIM=%QUESTA_ROOT%\win64\vsim.exe"
set "VLIB=%QUESTA_ROOT%\win64\vlib.exe"
set REPO=H:\IC Design\Code\ECG\ecg-thinh-uvm
set SIMLIB=%REPO%\simlib

set "TB_TOP=%~1"
if "%TB_TOP%"=="" goto usage

set "TB_SRC=%REPO%\tb\%TB_TOP%.sv"
set "WAVE_DO=%REPO%\scripts\gui\wave_%TB_TOP%.do"

if not exist "%SIMLIB%\work_reg\_lib.qdb" goto build
goto open

:build
echo [gui] work_reg library missing - building (RTL + %TB_TOP%) ...
pushd "%SIMLIB%"
"%VLIB%" work_reg
"%VLOG%" -sv -work work_reg ^
    "%REPO%\apb\apb_slave_if.v" ^
    "%REPO%\adc\adc_interface.v" ^
    "%REPO%\window\window_buffer.v" ^
    "%REPO%\feature\feature_extraction.v" ^
    "%REPO%\ai\ai_classifier.v" ^
    "%REPO%\ai\mlp_weights_rom.v" ^
    "%REPO%\control\control_fsm.v" ^
    "%REPO%\uart\uart_tx.v" ^
    "%REPO%\top\top_ecg_classifier.v" ^
    "%TB_SRC%"
if errorlevel 1 goto buildfail
popd
goto open

:buildfail
popd
echo [gui] build failed - see messages above.
exit /b 1

:open
echo [gui] reusing work_reg library, opening GUI for %TB_TOP% ...
pushd "%SIMLIB%"
if exist "%WAVE_DO%" (
    echo [gui] waveform config: %WAVE_DO%
    call :zoomfor %TB_TOP%
    start "" "%VSIM%" -work work_reg %TB_TOP% -do "do \"%WAVE_DO%\"; run -all; wave zoom %ZOOM%"
) else (
    echo [gui] no wave_%TB_TOP%.do found - opening plain GUI.
    start "" "%VSIM%" -work work_reg %TB_TOP% -do "run -all"
)
exit /b 0

rem ------------------------------------------------------------------------------
rem Per-test calibrated zoom (applied AFTER run -all; pre-run zoom is overridden).
rem Values come from real pipeline event times (div=20 top TB override), measured
rem in-tb with a temporary $time probe on 2026-10-30. Default is a broad window.
:zoomfor
rem NB: Questa 10.7c requires the "range" subcommand: "wave zoom range <a> <b>".
rem (The plain "wave zoom <a> <b>" is an error: "unknown or ambiguous
rem  subcommand".) ZOOM holds the subcommand + two times.
set "ZOOM=range 0ns 500000ns"
if /I "%~1"=="tb_top_ecg_classifier" set "ZOOM=range 195000ns 310000ns"
rem control_fsm TB runs ~367 ns total: a 0..500 ns window covers it.
if /I "%~1"=="tb_control_fsm" set "ZOOM=range 0ns 500ns"
goto :eof

:usage
echo Usage: run_gui.bat ^<tb_top_module^>   e.g. run_gui.bat tb_control_fsm
exit /b 1
