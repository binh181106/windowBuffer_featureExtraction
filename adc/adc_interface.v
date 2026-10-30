`timescale 1ns / 1ps

// =============================================================================
// ADC Interface Module (8-bit Parallel Input)
// =============================================================================
// Function: Latch and forward 8-bit parallel ADC data
// Application: ECG sensor (AD8232)
// Sample Rate: 360 Hz @ 50.4 MHz => sample_rate_div = 140000 (18-bit)
// =============================================================================

module adc_interface #(
    parameter DATA_WIDTH = 8,      // ADC resolution
    parameter DIV_WIDTH  = 18      // Sample rate divider width (140000 needs 18 bits)
) (
    // Clock and Reset
    input  wire              clk,
    input  wire              rst_n,

    // Configuration
    input  wire [DIV_WIDTH-1:0] sample_rate_div,  // Clock divider for sample rate

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
    reg [DIV_WIDTH-1:0]   rate_timer;
    reg                   rate_tick;

    // =============================================================================
    // Sample Rate Generator
    // =============================================================================
    // Chu kỳ tick = sample_rate_div clock (không phải div+1).
    //   sample_rate_div = 140000 @ 50.4 MHz  ->  50.4e6 / 140000 = 360 Hz
    //
    // Điều kiện cũ "rate_timer >= sample_rate_div" cho counter chạy 0..140000
    // (140001 giá trị) => chu kỳ 140001 clock => 359.997 Hz (lệch ~0.0007%).
    // Điều kiện mới ">= (div-1)" cho counter chạy 0..139999 => đúng 140000 clock.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rate_timer  <= {DIV_WIDTH{1'b0}};
            rate_tick   <= 1'b0;
        end else begin
            rate_tick <= 1'b0;

            if (rate_timer >= (sample_rate_div - 1'b1)) begin
                rate_timer <= {DIV_WIDTH{1'b0}};
                rate_tick  <= 1'b1;  // Generate tick at target rate
            end else begin
                rate_timer <= rate_timer + 1'b1;
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
