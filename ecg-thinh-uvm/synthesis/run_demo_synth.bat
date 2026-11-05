@echo off
setlocal EnableExtensions
rem ============================================================================
rem Gowin batch synthesis for top_ecg_rom_demo.
rem Device: GW5A-LV25UG324C2/I1 (confirmed from Gowin device DB row gw5a25a-008,
rem         matches docs MODULE_REPORT target "Gowin GW5A-LV25").
rem Run from repo root. Synthesis only (no P&R) — P&R requires the ACG525 pin
rem         map / I-O voltage, which are not confirmed (see AUTOMATION_STATUS §5).
rem ============================================================================
set GOWIN=H:\Gowin\Gowin_V1.9.9_x64\IDE\bin
set REPO=%~dp0..
cd /d "%REPO%"

%GOWIN%\GowinSynthesis.exe ^
  -i demo/ecg_rom.v demo/sample_pacer.v demo/demo_apb_seq.v ^
      demo/demo_uart_packetizer.v demo/top_ecg_rom_demo.v ^
      adc/adc_interface.v window/window_buffer.v ^
      feature/feature_extraction.v ai/ai_classifier.v ^
      ai/mlp_weights_rom.v control/control_fsm.v ^
      apb/apb_slave_if.v uart/uart_tx.v ^
  -top top_ecg_rom_demo ^
  -sdc synthesis/demo_ecg_rom_demo.sdc ^
  -pn "GW5A-LV25UG324C2/I1" ^
  -o synthesis/demo_out/top_ecg_rom_demo
