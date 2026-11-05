`timescale 1ns / 1ps
// =============================================================================
// Demo UART packetizer — one binary result packet per classification window
// =============================================================================
// SOLE driver of uart_tx in the demo top (single TX controller; the product
// control_fsm's uart_send is not routed to uart_tx in the demo).
//
// Frame — 33 bytes, 16-bit fields little-endian, features two's complement:
//   [0]  0xE7  sync1
//   [1]  0xA5  sync2
//   [2]  0x01  type = window result
//   [3]  0x1C  len = 28 (bytes 4..31)
//   [4..5]   win_index[15:0]
//   [6..29]  features f0..f11, each 16-bit, LSB first (order matches top:
//             f_rms f_var f_peak f_zc f_ptp f_crest f_half_ratio f_max
//             f_rr f_rr_prev f_rr_ratio f_rr_diff)
//   [30]  class_code [1:0] (byte value = class_code, 0..3)
//   [31]  flags: bit0=adc_overflow bit1=feature_overflow bit2=mlp_overflow
//   [32]  checksum = sum(bytes[2..31]) mod 256
//
// Latching: on the 1-cycle `pkt_req` (issued right after the APB RESULT read,
// see demo_apb_seq) ALL fields are latched before serialization -> window i
// data can never mix into window i+1. A new packet starts only after the
// current one fully finishes (uart_tx tx_done_tick); a `pkt_req` arriving
// while busy latches `pkt_drop` (never silent — the demo TB asserts it is 0).
// =============================================================================

module demo_uart_packetizer (
    input  wire             clk,
    input  wire             rst_n,

    // Request + latched data (stable during the 1-cycle pkt_req)
    input  wire             pkt_req,
    input  wire [15:0]      win_index,
    input  wire signed [15:0] f0,
    input  wire signed [15:0] f1,
    input  wire signed [15:0] f2,
    input  wire signed [15:0] f3,
    input  wire signed [15:0] f4,
    input  wire signed [15:0] f5,
    input  wire signed [15:0] f6,
    input  wire signed [15:0] f7,
    input  wire signed [15:0] f8,
    input  wire signed [15:0] f9,
    input  wire signed [15:0] f10,
    input  wire signed [15:0] f11,
    input  wire [1:0]       class_code,
    input  wire             err_adc,
    input  wire             err_feat,
    input  wire             err_mlp,

    // Byte interface to uart_tx
    output reg              tx_start,
    output reg       [7:0]  tx_data,

    // uart_tx done tick (one cycle after the byte finished serializing)
    input  wire             tx_done_tick,

    // Status
    output reg              pkt_busy,
    output reg              pkt_done,      // 1 cycle, last byte of a packet done
    output reg              pkt_drop      // latched: pkt_req arrived while busy
);

    localparam [7:0] SYNC1 = 8'hE7;
    localparam [7:0] SYNC2 = 8'hA5;
    localparam [7:0] TYPE  = 8'h01;
    localparam [7:0] LEN   = 8'd28;
    localparam [5:0] LAST  = 6'd32;

    // ---- latched packet data -------------------------------------------------
    reg [15:0]      w_idx;
    reg  [7:0]      lf8 [0:23];   // features as 24 raw bytes, index b: feature b/2, byte b%2
    reg [1:0]       l_class;
    reg [2:0]       l_flags;

    // ---- byte pump state -----------------------------------------------------
    reg [5:0]       pump_idx;
    reg             pumping;

    // byte value at index n from the latched data (LSB byte first).
    function [7:0] byte_at;
        input [5:0] n;
        begin
            case (n)
                6'd0:  byte_at = SYNC1;
                6'd1:  byte_at = SYNC2;
                6'd2:  byte_at = TYPE;
                6'd3:  byte_at = LEN;
                6'd4:  byte_at = w_idx[7:0];
                6'd5:  byte_at = w_idx[15:8];
                6'd30: byte_at = {6'd0, l_class};
                6'd31: byte_at = {5'd0, l_flags};
                6'd32: byte_at = 8'd0;              // replaced by checksum
                default: byte_at = lf8[(n - 6'd6)]; // feature byte, index 6..29
            endcase
        end
    endfunction

    // checksum = sum of bytes[2..31] mod 256 (raw byte values as transmitted)
    wire [31:0] chk_sum =
        {24'd0, TYPE}
      + {24'd0, LEN}
      + {24'd0, w_idx[7:0]}  + {24'd0, w_idx[15:8]}
      + {24'd0, lf8[0]} + {24'd0, lf8[1]}
      + {24'd0, lf8[2]} + {24'd0, lf8[3]}
      + {24'd0, lf8[4]} + {24'd0, lf8[5]}
      + {24'd0, lf8[6]} + {24'd0, lf8[7]}
      + {24'd0, lf8[8]} + {24'd0, lf8[9]}
      + {24'd0, lf8[10]}+ {24'd0, lf8[11]}
      + {24'd0, lf8[12]}+ {24'd0, lf8[13]}
      + {24'd0, lf8[14]}+ {24'd0, lf8[15]}
      + {24'd0, lf8[16]}+ {24'd0, lf8[17]}
      + {24'd0, lf8[18]}+ {24'd0, lf8[19]}
      + {24'd0, lf8[20]}+ {24'd0, lf8[21]}
      + {24'd0, lf8[22]}+ {24'd0, lf8[23]}
      + {28'd0, 4'd0} + 32'd0
      + {30'd0, l_class}
      + {29'd0, l_flags};
    wire [7:0] chk_byte = chk_sum[7:0];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pkt_busy   <= 1'b0;
            pkt_done   <= 1'b0;
            pkt_drop   <= 1'b0;
            tx_start   <= 1'b0;
            tx_data    <= 8'd0;
            pumping    <= 1'b0;
            pump_idx   <= 6'd0;
            w_idx      <= 16'd0;
            l_class    <= 2'd0;
            l_flags    <= 3'd0;
            for (int i = 0; i < 24; i = i + 1) lf8[i] <= 8'd0;
        end else begin
            tx_start <= 1'b0;
            pkt_done <= 1'b0;

            // Drop detection (latched; the TB must keep this at 0).
            if (pkt_req && pkt_busy)
                pkt_drop <= 1'b1;

            if (pkt_req && !pkt_busy) begin
                // Latch all fields BEFORE serializing (no window mixing).
                w_idx   <= win_index;
                l_class <= class_code;
                l_flags <= {err_mlp, err_feat, err_adc};
                lf8[0]  <= f0[7:0];   lf8[1]  <= f0[15:8];
                lf8[2]  <= f1[7:0];   lf8[3]  <= f1[15:8];
                lf8[4]  <= f2[7:0];   lf8[5]  <= f2[15:8];
                lf8[6]  <= f3[7:0];   lf8[7]  <= f3[15:8];
                lf8[8]  <= f4[7:0];   lf8[9]  <= f4[15:8];
                lf8[10] <= f5[7:0];   lf8[11] <= f5[15:8];
                lf8[12] <= f6[7:0];   lf8[13] <= f6[15:8];
                lf8[14] <= f7[7:0];   lf8[15] <= f7[15:8];
                lf8[16] <= f8[7:0];   lf8[17] <= f8[15:8];
                lf8[18] <= f9[7:0];   lf8[19] <= f9[15:8];
                lf8[20] <= f10[7:0];  lf8[21] <= f10[15:8];
                lf8[22] <= f11[7:0];  lf8[23] <= f11[15:8];
                pump_idx <= 6'd0;
                pumping  <= 1'b1;
                tx_start <= 1'b1;
                tx_data  <= byte_at(6'd0);   // SYNC1
                pkt_busy <= 1'b1;
            end else if (pumping) begin
                if (tx_done_tick) begin
                    // Byte pump_idx finished serializing; send the next one.
                    if (pump_idx == LAST) begin
                        pumping  <= 1'b0;
                        pkt_busy <= 1'b0;
                        pkt_done <= 1'b1;
                    end else begin
                        pump_idx <= pump_idx + 6'd1;
                        tx_start <= 1'b1;
                        // Next byte value (byte_at(32) = 0; use checksum there).
                        tx_data  <= (pump_idx + 6'd1) == LAST ? chk_byte
                                                               : byte_at(pump_idx + 6'd1);
                    end
                end
            end
        end
    end

endmodule
