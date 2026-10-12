`timescale 1ns / 1ps

// =============================================================================
// MLP Weights ROM - Initialized from weight.hex
// =============================================================================
// This module provides the weight and bias values for the MLP neural network
// Values are loaded from ../AI_FSM_ECG-main/AI_FSM_ECG-main/weight.hex
// Format: Q4.12 fixed-point
// =============================================================================

module mlp_weights_rom (
    input  wire              clk,
    input  wire              rst_n,

    // ROM read interface
    input  wire [7:0]       addr,
    output reg  [15:0]      data
);

    // =============================================================================
    // ROM Array (164 words)
    // Memory Map:
    // [0-11]    : Mean values (12)
    // [12-23]   : Inverse Scale (12)
    // [24-119]  : FC1 Weights (96)
    // [120-127] : FC1 Biases (8)
    // [128-159] : FC2 Weights (32)
    // [160-163] : FC2 Biases (4)
    // =============================================================================
    reg [15:0] rom [0:163];

    // =============================================================================
    // ROM Initialization from hex file
    // =============================================================================
    initial begin
        // Read weight.hex file
        $readmemh("../AI_FSM_ECG-main/AI_FSM_ECG-main/weight.hex", rom);
    end

    // =============================================================================
    // Read Operation
    // =============================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            data <= 16'h0000;
        end else begin
            data <= rom[addr];
        end
    end

    // =============================================================================
    // Debug: Display ROM contents (for simulation)
    // =============================================================================
    // synopsys translate_off
    integer i;
    initial begin
        #100;
        $display("=== MLP ROM Contents ===");
        $display("Mean Values [0-11]:");
        for (i = 0; i < 12; i = i + 1) begin
            $display("  [%02d] = %04x", i, rom[i]);
        end
        $display("Inverse Scale [12-23]:");
        for (i = 12; i < 24; i = i + 1) begin
            $display("  [%02d] = %04x", i, rom[i]);
        end
        $display("FC1 Weights [24-119] (first 10):");
        for (i = 24; i < 34; i = i + 1) begin
            $display("  [%02d] = %04x", i, rom[i]);
        end
        $display("FC1 Biases [120-127]:");
        for (i = 120; i < 128; i = i + 1) begin
            $display("  [%02d] = %04x", i, rom[i]);
        end
        $display("FC2 Weights [128-159] (first 10):");
        for (i = 128; i < 138; i = i + 1) begin
            $display("  [%02d] = %04x", i, rom[i]);
        end
        $display("FC2 Biases [160-163]:");
        for (i = 160; i < 164; i = i + 1) begin
            $display("  [%02d] = %04x", i, rom[i]);
        end
    end
    // synopsys translate_on

endmodule
