`timescale 1ns / 1ps
// =============================================================================
// Demo APB sequencer — deterministic bring-up + per-result APB access
// =============================================================================
// Drives a minimal APB AMBA3 master. No external CPU.
//
//   BRING-UP (once):  W: CTRL = 0x0000_0003  (bit0=sys_enable, bit1=sys_start
//                             -> sys_start pulses -> control FSM starts)
//                     W: BAUD = 0x0000_01B5  (437 = 115200 @ 50.4 MHz)
//   PER-RESULT LOOP:  `done_seen` latches every 1-cycle sys_done (so a done
//                     pulse is never missed while the sequencer is busy).
//                     On done_seen:
//                       APB READ ADDR_RESULT (SETUP then ACCESS; prdata valid
//                       the cycle after the ACCESS posedge)
//                       fire `pkt_req` on that cycle (the packetizer latches
//                       class_code from prdata there)
//                       RE-START: APB write CTRL = 0x0000_0003 again.
//
// The FSM restart matters: control_fsm returns to IDLE after DONE (start was
// a 2-cycle pulse) and from IDLE re-enters LOAD only on a NEW start while
// apb_enable. One restart per result -> every window gets classified.
//
// APB AMBA3 timing: SETUP (psel=1, penable=0) -> ACCESS (psel=1, penable=1,
// wait pready). This slave asserts pready in the ACCESS cycle; a write is
// committed there and prdata is registered at the same posedge (read data
// valid one cycle after ACCESS).
//
// Demo-only: lives inside top_ecg_rom_demo; the demo top exposes NO APB pins
// on the FPGA.
// =============================================================================

module demo_apb_seq (
    input  wire             pclk,
    input  wire             presetn,

    // APB master out
    output reg  [7:0]       paddr,
    output reg              psel,
    output reg              penable,
    output reg              pwrite,
    output reg  [31:0]      pwdata,
    input  wire             pready,
    input  wire [31:0]      prdata,

    // Demo-internal trigger
    input  wire             sys_done,      // 1-cycle pulse per window result

    // Packetizer request (1 cycle; prdata valid on this cycle)
    output reg              pkt_req
);

    localparam [7:0] A_CTRL  = 8'h00;
    localparam [7:0] A_BAUD  = 8'h0C;
    localparam [7:0] A_RES   = 8'h10;
    localparam [31:0] D_ENS  = 32'h0000_0003;  // enable + start
    localparam [31:0] D_BAUD = 32'h0000_01B5;  // 437

    localparam [2:0] S_IDLE    = 3'd0;
    localparam [2:0] S_WRACC   = 3'd1;   // ACCESS of the write(s)
    localparam [2:0] S_RDSETUP = 3'd2;
    localparam [2:0] S_RDACC   = 3'd3;
    localparam [2:0] S_FIR     = 3'd4;   // fire pkt_req + start restart SETUP
    localparam [2:0] S_RSACC   = 3'd5;   // ACCESS of the restart write

    reg [2:0]  state;
    reg [3:0]  widx;        // 0: write CTRL, 1: write BAUD, 2: loop
    reg        done_seen;

    always @(posedge pclk or negedge presetn) begin
        if (!presetn) begin
            state     <= S_IDLE;
            widx      <= 4'd0;
            done_seen <= 1'b0;
            paddr     <= 8'h00;
            psel      <= 1'b0;
            penable   <= 1'b0;
            pwrite    <= 1'b0;
            pwdata    <= 32'h0;
            pkt_req   <= 1'b0;
        end else begin
            // Latch every done pulse (even while mid-transaction).
            if (sys_done)
                done_seen <= 1'b1;

            pkt_req <= 1'b0;
            case (state)
                S_IDLE: begin
                    if (widx < 4'd2) begin
                        // SETUP of write widx
                        paddr   <= (widx == 4'd0) ? A_CTRL : A_BAUD;
                        pwdata  <= (widx == 4'd0) ? D_ENS  : D_BAUD;
                        pwrite  <= 1'b1;
                        psel    <= 1'b1;
                        penable <= 1'b0;
                        state   <= S_WRACC;
                    end else if (done_seen) begin
                        // SETUP of the RESULT read
                        paddr   <= A_RES;
                        pwrite  <= 1'b0;
                        psel    <= 1'b1;
                        penable <= 1'b0;
                        state   <= S_RDSETUP;
                    end else begin
                        pwrite  <= 1'b0;
                        psel    <= 1'b0;
                        penable <= 1'b0;
                    end
                end

                S_WRACC: begin
                    penable <= 1'b1;                     // ACCESS
                    if (pready) begin
                        penable <= 1'b0;
                        pwrite  <= 1'b0;
                        psel    <= 1'b0;
                        widx    <= widx + 4'd1;
                        state   <= S_IDLE;
                    end
                end

                S_RDSETUP: begin
                    penable <= 1'b1;                     // ACCESS
                    state   <= S_RDACC;
                end

                S_RDACC: begin
                    if (pready) begin
                        penable <= 1'b0;
                        psel    <= 1'b0;
                        state   <= S_FIR;                // prdata valid next c
                    end
                end

                // prdata is valid this cycle -> fire the packet request and,
                // in the same cycle, issue the SETUP of the restart write.
                S_FIR: begin
                    pkt_req   <= 1'b1;
                    done_seen <= 1'b0;                   // consume the done
                    paddr    <= A_CTRL;
                    pwdata   <= D_ENS;
                    pwrite   <= 1'b1;
                    psel     <= 1'b1;
                    penable  <= 1'b0;
                    state    <= S_RSACC;
                end

                S_RSACC: begin
                    penable <= 1'b1;                     // ACCESS of restart
                    if (pready) begin
                        penable <= 1'b0;
                        pwrite  <= 1'b0;
                        psel    <= 1'b0;
                        state   <= S_IDLE;               // wait next done_seen
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
