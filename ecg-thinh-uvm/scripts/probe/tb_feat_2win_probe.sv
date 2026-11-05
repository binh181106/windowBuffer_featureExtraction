`timescale 1ns/1ps
// Probe: expected per-window feature values under the RTL's width contexts.
// Mirrors feature_extraction.v expressions exactly so the numbers reflect
// what Questa 10.7c computes (shift/div width semantics), not a hand-guess.
module tb_feat_2win_probe;
    // Window A: 8 x 10
    reg signed [7:0]  peakA;      // 10
    reg signed [63:0] sum_sqA;    // 800
    reg signed [31:0] sumA;       // 80
    reg signed [63:0] meanA;      // sum<<<3
    // Window B: 8 x 20
    reg signed [7:0]  peakB;      // 20
    reg signed [63:0] sum_sqB;    // 3200
    reg signed [31:0] sumB;       // 160
    reg signed [63:0] meanB;      // sum<<<3

    reg signed [31:0] rmsA, rmsB;   // $signed(sum_sq[31:0] >> 9)
    reg signed [63:0] varA, varB;    // (sum_sq<<<3) - (mean^2 >>> 12)
    reg signed [15:0] crestA, crestB;

    initial begin
        // Window A
        peakA = 8'sd10;  sumA = 32'sd80;   sum_sqA = 64'sd800;
        meanA = $signed(sumA) <<< 3;
        rmsA  = $signed(sum_sqA[31:0] >> 9);
        varA  = (sum_sqA <<< 3) - ((meanA * meanA) >>> 12);
        crestA = (peakA <<< 12) / rmsA[15:0];

        // Window B
        peakB = 8'sd20;  sumB = 32'sd160;  sum_sqB = 64'sd3200;
        meanB = $signed(sumB) <<< 3;
        rmsB  = $signed(sum_sqB[31:0] >> 9);
        varB  = (sum_sqB <<< 3) - ((meanB * meanB) >>> 12);
        crestB = (peakB <<< 12) / rmsB[15:0];

        $display("== Window A (8x10) ==");
        $display("  rms_calc=%0d  f_rms(low16)=%0d", rmsA, rmsA[15:0]);
        $display("  mean=%0d  var(full64)=%0d  f_var(low16)=%0d", meanA, varA, varA[15:0]);
        $display("  peak*4096=%0d  denom=%0d  crest(full)=%0d 0x%0h  crest(s16)=%0d",
                 peakA*4096, rmsA[15:0], crestA, crestA, $signed(crestA));

        $display("== Window B (8x20) ==");
        $display("  rms_calc=%0d  f_rms(low16)=%0d", rmsB, rmsB[15:0]);
        $display("  mean=%0d  var(full64)=%0d  f_var(low16)=%0d", meanB, varB, varB[15:0]);
        $display("  peak*4096=%0d  denom=%0d  crest(full)=%0d 0x%0h  crest(s16)=%0d",
                 peakB*4096, rmsB[15:0], crestB, crestB, $signed(crestB));

        $finish;
    end
endmodule
