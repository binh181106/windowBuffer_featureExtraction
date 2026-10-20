# Synthesis Scripts

## File: run_synth.tcl

## Chức năng
Vivado synthesis script cho FPGA implementation.

## Target
- FPGA: Gowin GW5A-LV25 (hoặc Xilinx tương đương)
- Clock: 100 MHz

## Resources (Estimated)
- LUT: ~2000
- DFF: ~1500
- BSRAM: 2 blocks (18K)
- DSP: 4 (for MAC operations)

## Xem thêm
- Top level: `top/top_ppg_classifier.v`
- Interface contract: `docs/interfaces.md`
