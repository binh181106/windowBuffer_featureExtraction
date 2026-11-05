`timescale 1ns/1ps
// Isolated repro of f_crest numerator width behavior.
// Reproduces feature_extraction.v:289  f_crest <= (peak_reg <<< 12) / rms_calc[15:0];
module tb_crest_probe;
    reg signed [7:0]  peak_reg;   // 8-bit, as in RTL
    reg signed [31:0] rms_calc;   // 32-bit, as in RTL
    reg signed [15:0] f_crest;
    reg signed [31:0] wide;
    reg signed [31:0] crest_full;
    reg signed [15:0] f_crest_fixed;

    initial begin
        peak_reg = 8'sd10;
        rms_calc = (32'd800) >> 9;   // = 1
        $display("peak_reg=%0d  rms_calc=%0d  (800>>9=1)", peak_reg, rms_calc);

        // Current RTL expression (self-determined width):
        f_crest = (peak_reg <<< 12) / rms_calc[15:0];
        $display("RTL   f_crest = %0d  (0x%0h)", f_crest, f_crest);

        // What the formula SHOULD give (full-precision numerator, peak*4096/rms):
        $display("SPEC  (peak*4096/rms) = %0d  (10*4096/1)", 10*4096/1);

        // Fixed variant: sign-extend numerator before shift (32-bit temp).
        wide = $signed(peak_reg) <<< 12;
        crest_full = wide / rms_calc;
        f_crest_fixed = crest_full[15:0];
        $display("FIXED f_crest (sign-extend) = %0d", f_crest_fixed);
        $finish;
    end
endmodule
