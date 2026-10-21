`timescale 1ns / 1ps

// =============================================================================
// UART TX Engine Module
// =============================================================================
// Function: Serialize and transmit classification results via UART
// Protocol: 8N1 (8 data bits, No parity, 1 stop bit)
// Baud rates: Programmable via APB
// =============================================================================

module uart_tx #(
    parameter CLKS_PER_BIT = 437  // 115200 @ 50.4MHz: 50400000/115200 = 437.5
) (
    // Clock and Reset
    input  wire              clk,
    input  wire              rst_n,

    // Configuration
    input  wire [15:0]     baud_div,          // Baud divisor from APB

    // Data Input
    input  wire [7:0]       tx_data,           // 8-bit data to transmit
    input  wire              tx_start,          // Start transmission pulse
    input  wire              tx_enable,          // UART enable

    // Status
    output reg               tx_busy,           // Transmitter busy
    output reg               tx_done_tick,      // Transmission complete pulse

    // UART Output
    output reg               uart_txd            // UART TX pin
);

    // =============================================================================
    // State Machine States
    // =============================================================================
    localparam IDLE  = 3'd0;
    localparam START = 3'd1;  // Start bit (0)
    localparam DATA  = 3'd2;  // Data bits (8)
    localparam STOP  = 3'd3;  // Stop bit (1)
    localparam CLEAN = 3'd4;  // Clean up

    // =============================================================================
    // Internal Registers
    // =============================================================================
    reg [2:0]       state;
    reg [2:0]       state_next;
    reg [15:0]      clk_count;      // Clock cycles per bit
    reg [2:0]       bit_index;      // Which bit to transmit
    reg [7:0]       tx_data_reg;    // Latched TX data
    reg [15:0]      baud_div_reg;   // Latched baud divisor

    // =============================================================================
    // Latch Configuration and Data
    // =============================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_data_reg  <= 8'h0;
            baud_div_reg <= CLKS_PER_BIT;
        end else begin
            if (tx_start && !tx_busy) begin
                tx_data_reg  <= tx_data;
                baud_div_reg <= baud_div;
            end
        end
    end

    // =============================================================================
    // Main UART TX State Machine
    // =============================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state       <= IDLE;
            uart_txd    <= 1'b1;     // UART idle high
            tx_busy     <= 1'b0;
            tx_done_tick <= 1'b0;
            clk_count   <= 16'd0;
            bit_index   <= 3'd0;
        end else begin
            // Default
            tx_done_tick <= 1'b0;

            case (state)
                // =============================================================
                // IDLE: Wait for start signal
                // =============================================================
                IDLE: begin
                    uart_txd  <= 1'b1;     // Idle high
                    clk_count <= 16'd0;
                    bit_index <= 3'd0;

                    if (tx_start && tx_enable && !tx_busy) begin
                        state   <= START;
                        tx_busy <= 1'b1;
                    end else begin
                        state   <= IDLE;
                        tx_busy <= 1'b0;
                    end
                end

                // =============================================================
                // START: Transmit start bit (0)
                // =============================================================
                START: begin
                    uart_txd <= 1'b0;      // Start bit

                    if (clk_count < baud_div_reg - 1) begin
                        clk_count <= clk_count + 16'd1;
                        state     <= START;
                    end else begin
                        clk_count <= 16'd0;
                        state     <= DATA;
                    end
                end

                // =============================================================
                // DATA: Transmit 8 data bits (LSB first)
                // =============================================================
                DATA: begin
                    uart_txd <= tx_data_reg[bit_index];  // Send current bit

                    if (clk_count < baud_div_reg - 1) begin
                        clk_count <= clk_count + 16'd1;
                        state     <= DATA;
                    end else begin
                        clk_count <= 16'd0;

                        if (bit_index == 3'd7) begin
                            // All bits sent
                            bit_index <= 3'd0;
                            state     <= STOP;
                        end else begin
                            bit_index <= bit_index + 3'd1;
                            state     <= DATA;
                        end
                    end
                end

                // =============================================================
                // STOP: Transmit stop bit (1)
                // =============================================================
                STOP: begin
                    uart_txd <= 1'b1;      // Stop bit

                    if (clk_count < baud_div_reg - 1) begin
                        clk_count <= clk_count + 16'd1;
                        state     <= STOP;
                    end else begin
                        clk_count <= 16'd0;
                        state     <= CLEAN;
                    end
                end

                // =============================================================
                // CLEANUP: Generate done tick and return to IDLE
                // =============================================================
                CLEAN: begin
                    tx_busy      <= 1'b0;
                    tx_done_tick <= 1'b1;     // Done pulse
                    state        <= IDLE;
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule
