`timescale 1ns / 1ps

// =============================================================================
// ADC Interface Module (8-bit Parallel Input)
// =============================================================================
// Function: Latch and forward 8-bit parallel ADC data
// Supports: PPG sensor (MAX30102) or ECG sensor (AD8232)
// Data rate: 250Hz typical for PPG, 500Hz for ECG
// =============================================================================

module adc_interface #(
    parameter DATA_WIDTH = 8     // ADC resolution
) (
    // Clock and Reset
    input  wire              clk,
    input  wire              rst_n,

    // Configuration
    input  wire [15:0]      sample_rate_div,  // Clock divider for sample rate
    input  wire              mode_ppg_ecg,     // 0=PPG mode, 1=ECG mode

    // ADC Interface (8-bit parallel)
    input  wire [DATA_WIDTH-1:0] adc_data_in,   // 8-bit parallel ADC data
    input  wire              adc_data_valid,     // Data valid strobe from ADC
    input  wire              adc_clk,           // ADC conversion clock

    // Output to Window Buffer
    output reg  [DATA_WIDTH-1:0] sample_out,
    output reg                 sample_valid,
    output reg                 adc_overflow,     // Data lost indicator

    // Status
    output reg  [31:0]       sample_count
);

    // =============================================================================
    // Internal Signals
    // =============================================================================
    reg [DATA_WIDTH-1:0] adc_data_latch;
    reg                   adc_valid_prev;
    reg                   data_pending;
    reg                   overflow_flag;

    // Sample rate timer
    reg [15:0]            rate_timer;
    reg                   rate_tick;

    // =============================================================================
    // Sample Rate Generator
    // =============================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rate_timer  <= 16'd0;
            rate_tick   <= 1'b0;
        end else begin
            rate_tick <= 1'b0;

            if (rate_timer >= sample_rate_div) begin
                rate_timer <= 16'd0;
                rate_tick  <= 1'b1;  // Generate tick at target rate
            end else begin
                rate_timer <= rate_timer + 16'd1;
            end
        end
    end

    // =============================================================================
    // ADC Data Latching
    // =============================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            adc_data_latch   <= {DATA_WIDTH{1'b0}};
            adc_valid_prev   <= 1'b0;
            data_pending     <= 1'b0;
            overflow_flag    <= 1'b0;
        end else begin
            adc_valid_prev <= adc_data_valid;

            // Rising edge detection on data_valid
            if (adc_data_valid && !adc_valid_prev) begin
                // New data arrived
                if (!data_pending) begin
                    adc_data_latch <= adc_data_in;
                    data_pending    <= 1'b1;
                end else begin
                    // Previous data not consumed - overflow!
                    overflow_flag <= 1'b1;
                end
            end
        end
    end

    // =============================================================================
    // Output Data Forwarding
    // =============================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sample_out    <= {DATA_WIDTH{1'b0}};
            sample_valid  <= 1'b0;
            sample_count  <= 32'd0;
            adc_overflow  <= 1'b0;
        end else begin
            sample_valid <= 1'b0;
            adc_overflow  <= 1'b0;

            // Output data when rate tick occurs and data is pending
            if (rate_tick && data_pending) begin
                sample_out   <= adc_data_latch;
                sample_valid <= 1'b1;
                data_pending <= 1'b0;
                sample_count <= sample_count + 32'd1;

                // Clear overflow flag after reporting
                if (overflow_flag) begin
                    adc_overflow <= 1'b1;
                    overflow_flag <= 1'b0;
                end
            end
        end
    end

endmodule
