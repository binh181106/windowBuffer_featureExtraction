`timescale 1ns / 1ps

// =============================================================================
// APB Slave Interface for ECG Classifier
// =============================================================================
module apb_slave_if #(
    parameter ADDR_WIDTH = 8,
    parameter DATA_WIDTH = 32
) (
    input  wire              pclk,
    input  wire              presetn,
    input  wire [ADDR_WIDTH-1:0] paddr,
    input  wire              psel,
    input  wire              penable,
    input  wire              pwrite,
    input  wire [DATA_WIDTH-1:0] pwdata,
    output reg  [DATA_WIDTH-1:0] prdata,
    output reg               pready,
    output reg               pslverr,
    output reg               sys_enable,
    output reg               sys_start,
    output reg  [15:0]      ecg_threshold,
    output reg  [15:0]      baud_div,
    output reg               ble_enable,
    output reg               uart_enable,
    output reg               soft_reset,
    input  wire              sys_busy,
    input  wire              sys_done,
    input  wire [1:0]       sys_class_code,
    input  wire              sys_overflow
);

    localparam ADDR_CTRL   = 8'h00;
    localparam ADDR_STATUS  = 8'h04;
    localparam ADDR_THRESH  = 8'h08;
    localparam ADDR_BAUD    = 8'h0C;
    localparam ADDR_RESULT  = 8'h10;
    localparam ADDR_VERSION = 8'h14;
    localparam ADDR_CONFIG  = 8'h18;
    localparam VERSION = 16'h0200;

    reg [DATA_WIDTH-1:0] ctrl_reg;
    reg [DATA_WIDTH-1:0] thresh_reg;
    reg [DATA_WIDTH-1:0] baud_reg;
    reg [DATA_WIDTH-1:0] config_reg;
    reg p_irq;

    always @(posedge pclk or negedge presetn) begin
        if (!presetn) begin
            ctrl_reg   <= 32'h0;
            thresh_reg <= 32'h00000050;
            baud_reg   <= 32'h000001B5;
            config_reg <= 32'h0;
            sys_enable    <= 1'b0;
            sys_start     <= 1'b0;
            ecg_threshold <= 16'd80;
            baud_div      <= 16'd437;
            ble_enable    <= 1'b0;
            uart_enable   <= 1'b1;
            soft_reset    <= 1'b0;
        end else begin
            soft_reset <= 1'b0;

            if (psel && pwrite && !penable) begin
                case (paddr[7:0])
                    ADDR_CTRL: begin
                        ctrl_reg <= pwdata;
                        sys_enable <= pwdata[0];
                        if (pwdata[1]) sys_start <= 1'b1;
                        if (pwdata[4]) soft_reset <= 1'b1;
                    end
                    ADDR_THRESH: begin
                        thresh_reg <= pwdata;
                        ecg_threshold <= pwdata[15:0];
                    end
                    ADDR_BAUD: begin
                        baud_reg <= pwdata;
                        baud_div <= pwdata[15:0];
                    end
                    ADDR_CONFIG: begin
                        config_reg <= pwdata;
                        ble_enable  <= pwdata[0];
                        uart_enable <= pwdata[1];
                    end
                endcase
            end

            // Clear pulse after 2 cycles
            if (sys_start) sys_start <= 1'b0;
        end
    end

    always @(posedge pclk or negedge presetn) begin
        if (!presetn) begin
            prdata  <= 32'h0;
            pslverr <= 1'b0;
        end else begin
            prdata  <= 32'h0;
            pslverr <= 1'b0;
            if (psel && !pwrite) begin
                case (paddr[7:0])
                    ADDR_CTRL:   prdata <= ctrl_reg;
                    ADDR_STATUS: begin
                        prdata[0] <= sys_busy;
                        prdata[1] <= sys_done;
                        prdata[3] <= sys_overflow;
                    end
                    ADDR_THRESH: prdata <= thresh_reg;
                    ADDR_BAUD:   prdata <= baud_reg;
                    ADDR_RESULT: prdata[1:0] <= sys_class_code;
                    ADDR_VERSION: prdata[15:0] <= VERSION;
                    ADDR_CONFIG: prdata <= config_reg;
                endcase
            end
        end
    end

    always @(posedge pclk or negedge presetn) begin
        if (!presetn) pready <= 1'b0;
        else pready <= psel && penable;
    end

    always @(posedge pclk or negedge presetn) begin
        if (!presetn) p_irq <= 1'b0;
        else p_irq <= sys_done && ctrl_reg[2];
    end

endmodule
