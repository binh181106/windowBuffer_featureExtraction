`timescale 1ns / 1ps

// =============================================================================
// Window Buffer Module - 50% Overlap Circular Buffer
// =============================================================================
// Application: ECG R-peak detection
// Sample Rate: 500 Hz
//
// Overlap Strategy:
// - Shift Register chứa 512 samples mới nhất
// - Mỗi 256 samples (512ms) → output window với 50% overlap
// - R-peaks không bị miss vì overlap đủ rộng (1/2 beat)
//
// Timing:
//   - ECG ~60-120 bpm = 1-2 beats/second
//   - R-peak width ~100ms = 50 samples @ 500Hz
//   - 256 samples overlap = 512ms = đủ để capture R-peak
// =============================================================================

module window_buffer #(
    parameter DATA_WIDTH = 8,
    parameter WINDOW_SIZE = 512,
    parameter OVERLAP = 256        // 50% overlap
) (
    input  wire              clk,
    input  wire              rst_n,
    input  wire              enable,
    input  wire              soft_reset,
    input  wire [DATA_WIDTH-1:0] sample_in,
    input  wire              sample_valid,
    input  wire              read_en,
    input  wire [8:0]       read_addr,
    output wire [DATA_WIDTH-1:0] frame_out,
    output reg               window_ready,
    output reg  [31:0]      samples_collected,
    output reg  [8:0]       sample_cnt      // Debug
);

    // =============================================================================
    // Constants
    // =============================================================================
    localparam ADDR_W = 9;  // 9 bits for 512 addresses
    localparam ADDR_MAX = WINDOW_SIZE - 1;  // 511

    // =============================================================================
    // RAM for circular buffer
    // =============================================================================
    reg [DATA_WIDTH-1:0] ram [0:ADDR_MAX];

    // =============================================================================
    // Write Pointer - circular, 0 to 511
    // =============================================================================
    reg [ADDR_W-1:0] write_ptr;

    // =============================================================================
    // Write Logic
    // =============================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n || soft_reset) begin
            write_ptr         <= 9'd0;
            sample_cnt        <= 9'd0;
            window_ready      <= 1'b0;
            samples_collected <= 32'd0;
        end else begin
            window_ready <= 1'b0;

            if (enable && sample_valid) begin
                // Write to circular buffer
                ram[write_ptr] <= sample_in;

                // Advance circular pointer
                if (write_ptr == ADDR_MAX)
                    write_ptr <= 9'd0;
                else
                    write_ptr <= write_ptr + 9'd1;

                // Count samples
                if (sample_cnt < ADDR_MAX)
                    sample_cnt <= sample_cnt + 9'd1;

                samples_collected <= samples_collected + 32'd1;

                // Overlap trigger: Output window every OVERLAP (256) samples
                // when we have at least WINDOW_SIZE samples
                if (sample_cnt >= OVERLAP &&
                    (sample_cnt - OVERLAP + 1) % OVERLAP == 0) begin
                    window_ready <= 1'b1;
                end
            end
        end
    end

    // =============================================================================
    // Read Logic
    // =============================================================================
    // Feature Extraction đọc từ buffer:
    // - window_ready = 1 → start reading 512 samples
    // - read_addr 0 = oldest sample in window
    // - read_addr 511 = newest sample

    // Calculate oldest sample address in current window
    wire [ADDR_W-1:0] oldest_addr;
    assign oldest_addr = (sample_cnt >= ADDR_MAX) ?
                         // Buffer full: oldest is at current write position
                         write_ptr :
                         // Buffer not full yet: oldest is at address 0
                         9'd0;

    // Actual read address with circular wrap
    wire [ADDR_W-1:0] actual_read_addr;
    assign actual_read_addr = (oldest_addr + read_addr) % WINDOW_SIZE;

    // Latched address for RAM read
    reg [ADDR_W-1:0] latched_addr;
    always @(posedge clk) begin
        if (read_en)
            latched_addr <= actual_read_addr;
    end

    assign frame_out = ram[latched_addr];

endmodule
