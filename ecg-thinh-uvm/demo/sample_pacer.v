`timescale 1ns / 1ps
// =============================================================================
// Sample pacer (demo) — clock-enable pacing with a 32-bit phase accumulator
// =============================================================================
// Emits `sample_data_valid`, a 1-clock pulse, on average TARGET_HZ times per
// second. Each posedge adds PHASE_INC to a 32-bit phase register; a pulse is
// issued on the cycle where the addition overflows bit 31. The emitted sample
// is latched from `rom_out` on that pulse, i.e. 1 cycle after the ROM address
// was set — matching ecg_rom's registered read exactly, so no sample is lost
// and the pulse width is one clock.
//
// Fractional divider: PHASE_INC = round(2^32 * TARGET_HZ / CLK_HZ)
// (64-bit math, taken low 32 bits — the exact value always fits).
//
//   Board config : CLK_HZ = 50_000_000, TARGET_HZ = 360
//                  -> PHASE_INC = round(4294967296*360/50e6) = 30924
//                  Pulse spacing alternates 138888/138889 cycles -> avg
//                  = 50e6 * 30924 / 2^32 = 360.002741 Hz (recorded, NOT
//                  "exactly 360"; +7.6 ppm over the target).
//   Fast sim     : CLK_HZ = 20_000_000, TARGET_HZ = 200_000 (TB override)
//                  -> PHASE_INC = 42949673 -> gap = CLK_HZ/TARGET_HZ = 100
//                  cycles. Chosen so 256-sample window time (25600 cycles) is
//                  > one 33-byte UART packet (14421 cycles) -> no drops.
//
// END OF SEGMENT: each ROM sample is emitted ONCE. No last->first loopback,
// so no fake 512-sample window forms across the boundary. After the final
// sample `end_of_data` latches and no further pulse is issued (windows already
// full have already fired).
//
// Interaction with adc_interface: the demo top sets SYS_SAMPLE_RATE_DIV = 1,
// so adc_interface's rate_tick asserts every cycle and every 1-cycle
// sample_valid pulse is forwarded exactly once with data pending -> no double
// division, no loss (verified: adc sample_count == ROM sample count).
// =============================================================================

module sample_pacer #(
    parameter integer CLK_HZ    = 50_000_000,
    parameter integer TARGET_HZ = 360,
    parameter ROM_WORDS = 2048,
    parameter ROM_DW    = 8
) (
    input  wire             clk,
    input  wire             rst_n,

    // ROM hookup (ecg_rom)
    input  wire [ROM_DW-1:0] rom_out,                 // ROM[rom_addr @ prev posedge]
    output wire [$clog2(ROM_WORDS)-1:0] rom_addr,     // stable between pulses

    // Paced sample (adc_interface input contract: data + 1-cycle valid)
    output reg  [ROM_DW-1:0] sample_data,
    output reg              sample_valid,
    output reg              end_of_data
);

    // PHASE_INC = round(2^32 * TARGET_HZ / CLK_HZ), kept in the low 32 bits
    // (the exact value always fits). Verified: round(2^32*360/50e6)=30924.
    localparam [63:0] PHASE_INC_64 =
        ( 64'd4294967296 * TARGET_HZ + CLK_HZ/2 ) / CLK_HZ;
    localparam [31:0] PHASE_INC = PHASE_INC_64[31:0];

    localparam AW = $clog2(ROM_WORDS);

    reg  [31:0] phase;
    reg  [AW-1:0] wr_ptr;        // index of the sample about to be emitted
    // 33-bit sum: the carry out of the 32-bit phase is bit 32.
    wire [32:0] phase_next = {1'b0, phase} + {1'b0, PHASE_INC};
    wire        phase_wrap = phase_next[32];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            phase        <= 32'd0;
            wr_ptr       <= {AW{1'b0}};
            sample_data  <= {ROM_DW{1'b0}};
            sample_valid <= 1'b0;
            end_of_data  <= 1'b0;
        end else begin
            sample_valid <= 1'b0;
            phase <= phase_next[31:0];

            // Pulse when the 32-bit phase wraps (carry out of bit 32), once
            // only (after the final sample the phase keeps counting but no
            // pulse).
            if (phase_wrap && !end_of_data) begin
                // rom_out carries ROM[wr_ptr]: the address has been held
                // stable for a full inter-sample interval and the ROM read is
                // registered -> exactly 1 cycle after rom_addr was set.
                sample_data  <= rom_out;
                sample_valid <= 1'b1;
                if (wr_ptr == ROM_WORDS - 1)
                    end_of_data <= 1'b1;     // last sample emitted, single pass
                else
                    wr_ptr <= wr_ptr + 1'b1; // next index; ROM address follows
            end
        end
    end

    // ROM address = the index we will emit on this pulse. It only changes on
    // the pulse cycle, so it is stable across the whole inter-sample gap and
    // the 1-cycle ROM read latency is fully absorbed.
    assign rom_addr = wr_ptr;

endmodule
