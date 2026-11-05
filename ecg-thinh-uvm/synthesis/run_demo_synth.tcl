# Gowin synthesis for top_ecg_rom_demo.
# The gw_sh Tcl command set in Gowin 1.9.9 here does NOT match the syntax
# documented in most references (verified: `set_top` is not a command,
# `create_project`/`add_file` work but the full synth flow is driven through
# the batch GUI exe). The authoritative invocation is synthesis/run_demo_synth.bat.

call synthesis\run_demo_synth.bat
