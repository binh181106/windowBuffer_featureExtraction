`timescale 1ns / 1ps

// =============================================================================
// Feature Extraction Module (8-bit input -> 12 features x 16-bit output)
// =============================================================================
// Function: Extract statistical features from 512 ECG samples
// Features: RMS, Variance, Peak, Zero-crossing, Peak-to-Peak, Crest Factor,
//           Half-ratio, Max, RR Interval, RR Ratio, RR Diff
// Output: 16-bit signed values, Q4.12 format for fractional features
// Sample Rate: 360 Hz
// =============================================================================

module feature_extraction #(
    parameter DATA_IN_WIDTH = 8,
    parameter DATA_OUT_WIDTH = 16,
    parameter NUM_SAMPLES = 512
) (
    // Clock and Reset
    input  wire              clk,
    input  wire              rst_n,

    // Control
    input  wire              start_compute,   // Start feature extraction
    input  wire [15:0]       ecg_threshold,   // R-peak threshold for RR detection

    // Data Input (from Window Buffer)
    input  wire              read_enable,     // Request sample from buffer
    output reg  [8:0]       sample_addr,     // Address to read from buffer
    input  wire [DATA_IN_WIDTH-1:0] sample_in, // 8-bit sample

    // Feature Output (12 features x 16-bit)
    output reg  signed [DATA_OUT_WIDTH-1:0] f_rms,
    output reg  signed [DATA_OUT_WIDTH-1:0] f_var,
    output reg  signed [DATA_OUT_WIDTH-1:0] f_peak,
    output reg  signed [DATA_OUT_WIDTH-1:0] f_zc,
    output reg  signed [DATA_OUT_WIDTH-1:0] f_ptp,
    output reg  signed [DATA_OUT_WIDTH-1:0] f_crest,     // Q4.12
    output reg  signed [DATA_OUT_WIDTH-1:0] f_half_ratio, // Q4.12
    output reg  signed [DATA_OUT_WIDTH-1:0] f_max,
    output reg  signed [DATA_OUT_WIDTH-1:0] f_rr,
    output reg  signed [DATA_OUT_WIDTH-1:0] f_rr_prev,
    output reg  signed [DATA_OUT_WIDTH-1:0] f_rr_ratio,   // Q4.12
    output reg  signed [DATA_OUT_WIDTH-1:0] f_rr_diff,
    output reg               feature_valid,    // Features ready

    // Status
    output reg               overflow          // Computation overflow
);

    // =============================================================================
    // FSM States
    // =============================================================================
    localparam S_IDLE        = 4'd0;
    localparam S_ACCUMULATE  = 4'd1;
    localparam S_CALC_BASE   = 4'd2;
    localparam S_CALC_VAR    = 4'd3;
    localparam S_CALC_RMS    = 4'd4;
    localparam S_CALC_CREST  = 4'd5;
    localparam S_DONE        = 4'd6;

    reg [3:0] state;

    // =============================================================================
    // Internal Counters
    // =============================================================================
    reg [9:0]  sample_cnt;        // 0-511
    reg [9:0]  next_sample_cnt;   // For next sample address

    // =============================================================================
    // Accumulation Registers
    // =============================================================================
    reg signed [31:0] sum;         // Sum of samples
    reg signed [63:0] sum_square;  // Sum of squares
    reg signed [7:0]  peak_reg;   // Peak value
    reg signed [7:0]  min_reg;    // Min value
    reg [15:0]        zc_cnt;     // Zero crossing count
    reg               prev_sign;
    reg [15:0]        pos_cnt;    // Positive sample count

    // RR Detection
    reg [15:0]        rr_timer;
    reg [15:0]        rr_current;
    reg [15:0]        rr_previous;
    reg               above_threshold;
    reg signed [7:0]  sample_delayed;

    // =============================================================================
    // Temporary Values
    // =============================================================================
    reg signed [63:0] mean_val;
    reg signed [63:0] var_calc;
    reg signed [31:0] rms_calc;
    reg signed [15:0] crest_calc;

    // =============================================================================
    // Main FSM
    // =============================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= S_IDLE;
            sample_addr   <= 9'd0;
            sample_cnt    <= 10'd0;
            feature_valid <= 1'b0;
            overflow      <= 1'b0;

            // Reset all accumulators
            sum           <= 32'd0;
            sum_square    <= 64'd0;
            peak_reg      <= -8'sd128;
            min_reg       <= 8'sd127;
            zc_cnt        <= 16'd0;
            pos_cnt       <= 16'd0;
            prev_sign     <= 1'b0;
            rr_timer      <= 16'd0;
            rr_current    <= 16'd0;
            rr_previous   <= 16'd0;
            above_threshold <= 1'b0;

            // Reset outputs
            f_rms    <= 16'd0;
            f_var    <= 16'd0;
            f_peak   <= 16'd0;
            f_zc     <= 16'd0;
            f_ptp    <= 16'd0;
            f_crest  <= 16'd0;
            f_half_ratio <= 16'd0;
            f_max    <= 16'd0;
            f_rr     <= 16'd0;
            f_rr_prev <= 16'd0;
            f_rr_ratio <= 16'd0;
            f_rr_diff  <= 16'd0;

        end else begin
            case (state)
                // =============================================================
                // IDLE: Wait for start signal
                // =============================================================
                S_IDLE: begin
                    feature_valid <= 1'b0;
                    sample_addr   <= 9'd0;
                    sample_cnt    <= 10'd0;

                    if (start_compute) begin
                        state <= S_ACCUMULATE;
                        // Reset accumulators
                        sum           <= 32'd0;
                        sum_square    <= 64'd0;
                        peak_reg      <= -8'sd128;
                        min_reg       <= 8'sd127;
                        zc_cnt        <= 16'd0;
                        pos_cnt       <= 16'd0;
                        rr_timer      <= 16'd0;
                        above_threshold <= 1'b0;
                    end
                end

                // =============================================================
                // ACCUMULATE: Collect 512 samples
                // =============================================================
                S_ACCUMULATE: begin
                    // Accumulate current sample
                    sum        <= sum + $signed({{24{sample_in[7]}}, sample_in});
                    sum_square <= sum_square +
                        ($signed({{56{sample_in[7]}}, sample_in}) *
                         $signed({{56{sample_in[7]}}, sample_in}));

                    // Peak/Min detection (cast to signed for comparison)
                    if ($signed(sample_in) > peak_reg) peak_reg <= $signed(sample_in);
                    if ($signed(sample_in) < min_reg)  min_reg  <= $signed(sample_in);

                    // Zero crossing count
                    if (sample_cnt > 9'd0) begin
                        if (prev_sign ^ sample_in[7]) begin
                            zc_cnt <= zc_cnt + 16'd1;
                        end
                    end
                    prev_sign <= sample_in[7];

                    // Positive sample count
                    if (sample_in >= 8'sd0) begin
                        pos_cnt <= pos_cnt + 16'd1;
                    end

                    // RR Detection (R-peak above threshold)
                    if (sample_delayed > ecg_threshold[7:0]) begin
                        if (sample_in < sample_delayed && rr_timer > 16'd50) begin
                            // Peak detected
                            rr_previous <= rr_current;
                            rr_current  <= rr_timer;
                            rr_timer    <= 16'd0;
                        end
                    end
                    sample_delayed <= sample_in;
                    rr_timer <= rr_timer + 16'd1;

                    // Next sample
                    sample_cnt <= sample_cnt + 10'd1;
                    sample_addr <= sample_cnt + 10'd1;

                    if (sample_cnt == NUM_SAMPLES - 1) begin
                        state <= S_CALC_BASE;
                    end
                end

                // =============================================================
                // CALC_BASE: Calculate basic features
                // =============================================================
                S_CALC_BASE: begin
                    // Mean value
                    mean_val <= $signed(sum) <<< 3;  // *8 for scaling

                    // Output basic features
                    f_peak      <= $signed({{8{peak_reg[7]}}, peak_reg});
                    f_max       <= $signed({{8{peak_reg[7]}}, peak_reg});
                    f_ptp       <= $signed({{8{peak_reg[7]}}, peak_reg}) -
                                   $signed({{8{min_reg[7]}}, min_reg});
                    f_zc        <= $signed(zc_cnt);
                    f_half_ratio <= $signed(pos_cnt <<< 3);  // Q4.12 format
                    f_rr        <= $signed(rr_current);
                    f_rr_prev   <= $signed(rr_previous);
                    f_rr_diff   <= $signed(rr_current - rr_previous);

                    state <= S_CALC_VAR;
                end

                // =============================================================
                // CALC_VAR: Calculate variance
                // =============================================================
                S_CALC_VAR: begin
                    // Variance = E[X²] - (E[X])²
                    var_calc <= (sum_square <<< 3) - ((mean_val * mean_val) >>> 12);
                    f_var <= $signed(var_calc[15:0]);
                    state <= S_CALC_RMS;
                end

                // =============================================================
                // CALC_RMS: Calculate RMS and Crest Factor
                // =============================================================
                S_CALC_RMS: begin
                    // RMS = sqrt(sum_square / N) = sqrt(sum_square >> 9)
                    rms_calc <= $signed(sum_square[31:0] >> 9);
                    f_rms <= $signed(rms_calc[15:0]);

                    // Crest Factor = Peak / RMS (Q4.12 format)
                    if (rms_calc[15:0] > 16'd0) begin
                        f_crest <= (peak_reg <<< 12) / rms_calc[15:0];
                    end else begin
                        f_crest <= 16'd0;
                    end

                    // RR Ratio (Q4.12 format)
                    if (rr_previous > 16'd0) begin
                        f_rr_ratio <= (rr_current <<< 12) / rr_previous;
                    end else begin
                        f_rr_ratio <= 16'd4096;  // 1.0 in Q4.12
                    end

                    state <= S_DONE;
                end

                // =============================================================
                // DONE: Features ready
                // =============================================================
                S_DONE: begin
                    feature_valid <= 1'b1;
                    state <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

    // =============================================================================
    // Overflow Detection
    // =============================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            overflow <= 1'b0;
        end else begin
            // Detect overflow in accumulation
            overflow <= (sum_square[63:62] != 2'b00) ? 1'b1 : 1'b0;
        end
    end

endmodule
