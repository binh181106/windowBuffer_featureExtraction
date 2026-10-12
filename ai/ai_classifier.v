`timescale 1ns / 1ps

// =============================================================================
// AI Classifier Module (MLP Neural Network 12->8->4)
// =============================================================================
// Function: Classify PPG features into 4 categories
// Architecture: 12 inputs -> 8 hidden (ReLU) -> 4 outputs -> Argmax
// Format: 16-bit Q4.12 fixed-point arithmetic
// Weights: Stored in internal ROM, initialized at startup
// =============================================================================

module ai_classifier #(
    parameter FEATURE_WIDTH = 16,
    parameter HIDDEN_NEURONS = 8,
    parameter OUTPUT_NEURONS = 4
) (
    // Clock and Reset
    input  wire              clk,
    input  wire              rst_n,

    // Control
    input  wire              start,            // Start inference
    input  wire              enable,           // Module enable

    // Feature Input (12 features x 16-bit)
    input  wire signed [FEATURE_WIDTH-1:0] features [0:11],

    // Output
    output reg  [1:0]        class_code,      // Classification result
    output reg               done,             // Inference complete
    output reg               overflow,          // Overflow detected

    // Debug
    output reg signed [31:0] fc1_out [0:HIDDEN_NEURONS-1],
    output reg signed [31:0] fc2_out [0:OUTPUT_NEURONS-1]
);

    // =============================================================================
    // FSM States
    // =============================================================================
    localparam S_IDLE     = 4'd0;
    localparam S_LOAD    = 4'd1;
    localparam S_NORM    = 4'd2;
    localparam S_FC1     = 4'd3;
    localparam S_FC1_B   = 4'd4;
    localparam S_RELU    = 4'd5;
    localparam S_FC2     = 4'd6;
    localparam S_FC2_B   = 4'd7;
    localparam S_ARGMAX  = 4'd8;
    localparam S_DONE    = 4'd9;

    reg [3:0] state;

    // =============================================================================
    // Internal Buffers
    // =============================================================================
    reg signed [31:0] features_norm [0:11];
    reg signed [31:0] hidden_out [0:HIDDEN_NEURONS-1];  // After ReLU
    reg signed [31:0] fc1_out_raw [0:HIDDEN_NEURONS-1];
    reg signed [31:0] fc2_out_raw [0:OUTPUT_NEURONS-1];

    // =============================================================================
    // Counters
    // =============================================================================
    reg [7:0] cnt;

    // =============================================================================
    // Weight and Bias ROM
    // These would typically be loaded from external hex file
    // For synthesis, we initialize with default values
    // =============================================================================

    // FC1 Weights (12 x 8 = 96 weights)
    reg signed [15:0] fc1_weights [0:95];

    // FC1 Biases (8 biases)
    reg signed [15:0] fc1_biases [0:7];

    // FC2 Weights (8 x 4 = 32 weights)
    reg signed [15:0] fc2_weights [0:31];

    // FC2 Biases (4 biases)
    reg signed [15:0] fc2_biases [0:3];

    // Scaler parameters (mean and inv_scale)
    reg signed [15:0] mean_vals [0:11];
    reg signed [15:0] inv_scale [0:11];

    // =============================================================================
    // ROM Initialization (Default values - should be loaded from file)
    // =============================================================================
    integer i;
    initial begin
        // Initialize with placeholder values
        for (i = 0; i < 12; i = i + 1) begin
            mean_vals[i] = 16'd0;
            inv_scale[i] = 16'd4096;  // 1.0 in Q4.12
        end
        for (i = 0; i < 96; i = i + 1) begin
            fc1_weights[i] = 16'd0;
        end
        for (i = 0; i < 8; i = i + 1) begin
            fc1_biases[i] = 16'd0;
        end
        for (i = 0; i < 32; i = i + 1) begin
            fc2_weights[i] = 16'd0;
        end
        for (i = 0; i < 4; i = i + 1) begin
            fc2_biases[i] = 16'd0;
        end
    end

    // =============================================================================
    // ROM Loading Interface
    // =============================================================================
    reg [7:0] rom_addr;
    reg [15:0] rom_wdata;
    reg rom_we;

    always @(posedge clk) begin
        if (rom_we) begin
            case (rom_addr)
                // Mean values (0-11)
                8'd0: mean_vals[0] <= rom_wdata;
                8'd1: mean_vals[1] <= rom_wdata;
                8'd2: mean_vals[2] <= rom_wdata;
                8'd3: mean_vals[3] <= rom_wdata;
                8'd4: mean_vals[4] <= rom_wdata;
                8'd5: mean_vals[5] <= rom_wdata;
                8'd6: mean_vals[6] <= rom_wdata;
                8'd7: mean_vals[7] <= rom_wdata;
                8'd8: mean_vals[8] <= rom_wdata;
                8'd9: mean_vals[9] <= rom_wdata;
                8'd10: mean_vals[10] <= rom_wdata;
                8'd11: mean_vals[11] <= rom_wdata;
                // Inv Scale (12-23)
                8'd12: inv_scale[0] <= rom_wdata;
                8'd13: inv_scale[1] <= rom_wdata;
                8'd14: inv_scale[2] <= rom_wdata;
                8'd15: inv_scale[3] <= rom_wdata;
                8'd16: inv_scale[4] <= rom_wdata;
                8'd17: inv_scale[5] <= rom_wdata;
                8'd18: inv_scale[6] <= rom_wdata;
                8'd19: inv_scale[7] <= rom_wdata;
                8'd20: inv_scale[8] <= rom_wdata;
                8'd21: inv_scale[9] <= rom_wdata;
                8'd22: inv_scale[10] <= rom_wdata;
                8'd23: inv_scale[11] <= rom_wdata;
                // FC1 Weights (24-119)
                8'd24: fc1_weights[0] <= rom_wdata;
                8'd25: fc1_weights[1] <= rom_wdata;
                // ... (should auto-generate for all 96 weights)
                // FC1 Biases (120-127)
                8'd120: fc1_biases[0] <= rom_wdata;
                8'd121: fc1_biases[1] <= rom_wdata;
                // ... (should auto-generate for all 8 biases)
                // FC2 Weights (128-159)
                8'd128: fc2_weights[0] <= rom_wdata;
                // ... (should auto-generate for all 32 weights)
                // FC2 Biases (160-163)
                8'd160: fc2_biases[0] <= rom_wdata;
                // ... (should auto-generate for all 4 biases)
            endcase
        end
    end

    // =============================================================================
    // Main FSM
    // =============================================================================
    reg signed [47:0] mac_temp;  // Temporary for MAC operations

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state    <= S_IDLE;
            done     <= 1'b0;
            overflow <= 1'b0;
            cnt      <= 8'd0;

            for (i = 0; i < 12; i = i + 1)
                features_norm[i] <= 32'd0;
            for (i = 0; i < 8; i = i + 1) begin
                hidden_out[i] <= 32'd0;
                fc1_out[i] <= 32'd0;
                fc1_out_raw[i] <= 32'd0;
            end
            for (i = 0; i < 4; i = i + 1) begin
                fc2_out[i] <= 32'd0;
                fc2_out_raw[i] <= 32'd0;
            end

        end else begin
            done <= 1'b0;

            case (state)
                // =============================================================
                // IDLE
                // =============================================================
                S_IDLE: begin
                    cnt <= 8'd0;
                    if (start && enable) begin
                        state <= S_LOAD;
                    end
                end

                // =============================================================
                // LOAD: Load features
                // =============================================================
                S_LOAD: begin
                    // Features loaded in next cycle
                    state <= S_NORM;
                end

                // =============================================================
                // NORMALIZE: (x - mean) * inv_scale
                // =============================================================
                S_NORM: begin
                    cnt <= cnt + 8'd1;
                    if (cnt < 8'd12) begin
                        // Normalization: (features[i] - mean[i]) * inv_scale[i]
                        features_norm[cnt] <=
                            ($signed(features[cnt]) - $signed(mean_vals[cnt])) *
                            $signed(inv_scale[cnt]);
                    end else begin
                        cnt <= 8'd0;
                        state <= S_FC1;
                    end
                end

                // =============================================================
                // FC1: Fully Connected Layer 1
                // MAC: sum(features_norm[j] * fc1_weights[i*12 + j])
                // =============================================================
                S_FC1: begin
                    cnt <= cnt + 8'd1;

                    if (cnt == 8'd0) begin
                        // Reset accumulators
                        for (i = 0; i < HIDDEN_NEURONS; i = i + 1)
                            fc1_out_raw[i] <= 32'd0;
                    end else if (cnt <= 8'd96) begin
                        // MAC operation
                        // cnt-1 = 0..95, corresponds to weight index
                        // neuron = (cnt-1) / 12
                        // feature = (cnt-1) % 12
                        mac_temp = $signed(features_norm[(cnt-1)%12]) *
                                   $signed(fc1_weights[cnt-1]);
                        fc1_out_raw[(cnt-1)/12] <= fc1_out_raw[(cnt-1)/12] +
                            (mac_temp >>> 12);
                    end else begin
                        cnt <= 8'd0;
                        state <= S_FC1_B;
                    end
                end

                // =============================================================
                // FC1_B: Add biases to FC1
                // =============================================================
                S_FC1_B: begin
                    cnt <= cnt + 8'd1;
                    if (cnt < 8'd8) begin
                        fc1_out_raw[cnt] <= fc1_out_raw[cnt] + $signed(fc1_biases[cnt]);
                    end else begin
                        cnt <= 8'd0;
                        state <= S_RELU;
                    end
                end

                // =============================================================
                // RELU: Apply activation
                // =============================================================
                S_RELU: begin
                    cnt <= cnt + 8'd1;
                    if (cnt < 8'd8) begin
                        if (fc1_out_raw[cnt] > 32'd0) begin
                            hidden_out[cnt] <= fc1_out_raw[cnt];
                            fc1_out[cnt] <= fc1_out_raw[cnt];
                        end else begin
                            hidden_out[cnt] <= 32'd0;
                            fc1_out[cnt] <= 32'd0;
                        end
                    end else begin
                        cnt <= 8'd0;
                        state <= S_FC2;
                    end
                end

                // =============================================================
                // FC2: Fully Connected Layer 2
                // MAC: sum(hidden_out[j] * fc2_weights[i*8 + j])
                // =============================================================
                S_FC2: begin
                    cnt <= cnt + 8'd1;

                    if (cnt == 8'd0) begin
                        for (i = 0; i < OUTPUT_NEURONS; i = i + 1)
                            fc2_out_raw[i] <= 32'd0;
                    end else if (cnt <= 8'd32) begin
                        mac_temp = $signed(hidden_out[(cnt-1)%8]) *
                                   $signed(fc2_weights[cnt-1]);
                        fc2_out_raw[(cnt-1)/8] <= fc2_out_raw[(cnt-1)/8] +
                            (mac_temp >>> 12);
                    end else begin
                        cnt <= 8'd0;
                        state <= S_FC2_B;
                    end
                end

                // =============================================================
                // FC2_B: Add biases to FC2
                // =============================================================
                S_FC2_B: begin
                    cnt <= cnt + 8'd1;
                    if (cnt < 8'd4) begin
                        fc2_out_raw[cnt] <= fc2_out_raw[cnt] + $signed(fc2_biases[cnt]);
                        fc2_out[cnt] <= fc2_out_raw[cnt] + $signed(fc2_biases[cnt]);
                    end else begin
                        cnt <= 8'd0;
                        state <= S_ARGMAX;
                    end
                end

                // =============================================================
                // ARGMAX: Find maximum output
                // =============================================================
                S_ARGMAX: begin
                    // Argmax logic
                    if (fc2_out_raw[0] >= fc2_out_raw[1] &&
                        fc2_out_raw[0] >= fc2_out_raw[2] &&
                        fc2_out_raw[0] >= fc2_out_raw[3]) begin
                        class_code <= 2'd0;  // Normal
                    end else if (fc2_out_raw[1] >= fc2_out_raw[2] &&
                               fc2_out_raw[1] >= fc2_out_raw[3]) begin
                        class_code <= 2'd1;  // Fast
                    end else if (fc2_out_raw[2] >= fc2_out_raw[3]) begin
                        class_code <= 2'd2;  // Slow
                    end else begin
                        class_code <= 2'd3;  // Abnormal
                    end
                    state <= S_DONE;
                end

                // =============================================================
                // DONE
                // =============================================================
                S_DONE: begin
                    done <= 1'b1;
                    state <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

    // =============================================================================
    // ROM Write Interface for external loading
    // =============================================================================
    wire [7:0] rom_addr_w = rom_addr;
    wire [15:0] rom_wdata_w = rom_wdata;
    wire rom_we_w = rom_we;

endmodule
