`timescale 1ns / 1ps

// =============================================================================
// Window Buffer Module (512 samples with 50% overlap)
// =============================================================================
// Function: Collect 512 PPG samples for feature extraction
// Features: Ping-pong buffering, automatic 50% overlap sliding window
// Memory: 1024 x 8-bit RAM
// =============================================================================

module window_buffer #(
    parameter DATA_WIDTH = 8,      // 8-bit ADC data
    parameter WINDOW_SIZE = 512,   // Samples per window
    parameter OVERLAP = 256        // 50% overlap (256 samples)
) (
    // Clock and Reset
    input  wire              clk,
    input  wire              rst_n,

    // Control
    input  wire              enable,          // Enable buffering
    input  wire              soft_reset,      // Soft reset

    // Data Input (from ADC Interface)
    input  wire [DATA_WIDTH-1:0] sample_in,
    input  wire              sample_valid,

    // Read Interface (to Feature Extraction)
    input  wire              read_en,
    input  wire [8:0]       read_addr,       // 0 to 511
    output wire [DATA_WIDTH-1:0] frame_out,

    // Status
    output reg               window_ready,     // Window full, ready to process
    output reg  [31:0]      samples_collected,
    output wire              ready_bank       // Which bank is ready for reading
);

    // =============================================================================
    // Constants
    // =============================================================================
    localparam RAM_DEPTH = WINDOW_SIZE * 2;  // 1024 for ping-pong
    localparam BANK_SIZE = WINDOW_SIZE;       // 512 per bank
    localparam HALF_WINDOW = WINDOW_SIZE / 2; // 256 for overlap

    // =============================================================================
    // Internal Signals
    // =============================================================================
    reg [9:0]       write_counter;    // 0 to 511
    reg             write_bank;       // Current write bank (0=Ping, 1=Pong)
    reg             read_bank;        // Current read bank
    reg [8:0]       read_addr_reg;   // Latched read address

    // RAM inference
    reg [DATA_WIDTH-1:0] ram [0:RAM_DEPTH-1];

    // =============================================================================
    // Write Logic
    // =============================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n || soft_reset) begin
            write_counter     <= 10'd0;
            write_bank        <= 1'b0;
            read_bank         <= 1'b1;  // Start with opposite bank
            window_ready      <= 1'b0;
            samples_collected <= 32'd0;
        end else begin
            window_ready <= 1'b0;  // Default pulse

            if (enable && sample_valid) begin
                // Check for full window BEFORE increment
                if (write_counter == WINDOW_SIZE - 1) begin
                    // Window full! Signal ready and switch banks
                    window_ready <= 1'b1;
                    read_bank <= write_bank;  // Read bank becomes ready
                    write_bank <= ~write_bank; // Switch to other bank
                    write_counter <= 10'd0;    // Reset for new window
                end else begin
                    // Write to RAM at current address
                    ram[{write_bank, write_counter[8:0]}] <= sample_in;

                    // Increment counter
                    write_counter <= write_counter + 10'd1;
                    samples_collected <= samples_collected + 32'd1;
                end
            end
        end
    end

    // =============================================================================
    // Read Logic
    // =============================================================================
    assign ready_bank = read_bank;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            read_addr_reg <= 9'd0;
        end else begin
            if (read_en) begin
                read_addr_reg <= read_addr;
            end
        end
    end

    // Frame output (from RAM)
    assign frame_out = ram[{read_bank, read_addr_reg}];

endmodule
