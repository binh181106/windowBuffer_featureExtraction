`timescale 1ns / 1ps

// =============================================================================
// MODULE 1: 32-bit / 16-bit Restoring Divider 
// =============================================================================
module restoring_divider (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,      // Pulse to start calculation
    input  wire [31:0] dividend,   // Số bị chia
    input  wire [31:0] divisor,    // Số chia (widened to 32-bit)
    
    output reg  [31:0] quotient,   // Thương số
    output reg  [31:0] remainder,  // Số dư (widened to 32-bit)
    output reg         done        // High when calculation is complete
);

    localparam IDLE = 2'b00, CALC = 2'b01, DONE = 2'b10;
    reg [1:0]  state;
    reg [5:0]  count;
    
    reg [31:0] Q;
    reg [32:0] A;
    reg [31:0] M;

    wire [32:0] A_shifted = {A[31:0], Q[31]};
    wire [32:0] A_sub     = A_shifted - {1'b0, M}; 

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE; quotient <= 32'd0; remainder <= 32'd0;
            done <= 1'b0; count <= 6'd0; A <= 33'd0; Q <= 32'd0; M <= 32'd0;
        end else begin
            case (state)
                IDLE: begin
                    done <= 1'b0;
                    if (start) begin
                            A <= 33'd0; Q <= dividend; M <= divisor;
                            count <= 6'd32; state <= CALC;
                    end
                end
                CALC: begin
                    if (count > 0) begin
                        count <= count - 1'b1;
                        if (A_sub[32]) begin 
                            A <= A_shifted; Q <= {Q[30:0], 1'b0};
                        end else begin
                            A <= A_sub;     Q <= {Q[30:0], 1'b1};
                        end
                    end else state <= DONE;
                end
                DONE: begin
                    quotient <= Q; remainder <= A[31:0];
                    done <= 1'b1;  state <= IDLE;
                end
                default: state <= IDLE;
            endcase
        end
    end
endmodule

// =============================================================================
// MODULE 2: 32-bit Iterative Square Root 
// =============================================================================
module iterative_sqrt (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,      
    input  wire [63:0] radicand,   // Số dưới dấu căn (widened to 64-bit)
    
    output reg  [31:0] root,       // Căn bậc hai (widened to 32-bit)
    output reg         done
);

    localparam IDLE = 2'b00, CALC = 2'b01, DONE = 2'b10;
    reg [1:0]  state;
    reg [5:0]  count;
    reg [63:0] D;
    reg [31:0] Q;
    reg [33:0] R;

    wire [33:0] R_shifted = {R[31:0], D[63:62]};
    wire [33:0] sub_val   = {Q, 2'b01}; 
    wire [33:0] R_sub     = R_shifted - sub_val;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE; root <= 32'd0; done <= 1'b0;
            count <= 6'd0; D <= 64'd0; Q <= 32'd0; R <= 34'd0;
        end else begin
            case (state)
                IDLE: begin
                    done <= 1'b0;
                    if (start) begin
                        D <= radicand; Q <= 32'd0; R <= 34'd0;
                        count <= 6'd32; state <= CALC;
                    end
                end
                CALC: begin
                    if (count > 0) begin
                        count <= count - 1'b1;
                        D <= {D[61:0], 2'b00}; 
                        if (R_sub[33]) begin
                            R <= R_shifted; Q <= {Q[30:0], 1'b0};
                        end else begin
                            R <= R_sub;     Q <= {Q[30:0], 1'b1};
                        end
                    end else state <= DONE;
                end
                DONE: begin
                    root <= Q; done <= 1'b1; state <= IDLE;
                end
                default: state <= IDLE;
            endcase
        end
    end
endmodule