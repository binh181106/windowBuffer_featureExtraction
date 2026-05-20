`timescale 1ns / 1ps

// =============================================================================
// MODULE 1: 32-bit / 16-bit Restoring Divider 
// =============================================================================
module restoring_divider (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,      // Pulse to start calculation
    input  wire [31:0] dividend,   // Số bị chia
    input  wire [15:0] divisor,    // Số chia
    
    output reg  [31:0] quotient,   // Thương số
    output reg  [15:0] remainder,  // Số dư
    output reg         done        // High when calculation is complete
);

    localparam IDLE = 2'b00, CALC = 2'b01, DONE = 2'b10;
    reg [1:0]  state;
    reg [5:0]  count;
    
    reg [31:0] Q;
    reg [16:0] A;
    reg [15:0] M;

    wire [16:0] A_shifted = {A[15:0], Q[31]};
    wire [16:0] A_sub     = A_shifted - {1'b0, M}; 

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE; quotient <= 32'd0; remainder <= 16'd0;
            done <= 1'b0; count <= 6'd0; A <= 17'd0; Q <= 32'd0; M <= 16'd0;
        end else begin
            case (state)
                IDLE: begin
                    done <= 1'b0;
                    if (start) begin
                        A <= 17'd0; Q <= dividend; M <= divisor;
                        count <= 6'd32; state <= CALC;
                    end
                end
                CALC: begin
                    if (count > 0) begin
                        count <= count - 1'b1;
                        if (A_sub[16]) begin 
                            A <= A_shifted; Q <= {Q[30:0], 1'b0};
                        end else begin
                            A <= A_sub;     Q <= {Q[30:0], 1'b1};
                        end
                    end else state <= DONE;
                end
                DONE: begin
                    quotient <= Q; remainder <= A[15:0];
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
    input  wire [31:0] radicand,   // Số dưới dấu căn 
    
    output reg  [15:0] root,       // Căn bậc hai 
    output reg         done
);

    localparam IDLE = 2'b00, CALC = 2'b01, DONE = 2'b10;
    reg [1:0]  state;
    reg [4:0]  count;
    reg [31:0] D;
    reg [15:0] Q;
    reg [17:0] R;

    wire [17:0] R_shifted = {R[15:0], D[31:30]};
    wire [17:0] sub_val   = {Q, 2'b01}; 
    wire [17:0] R_sub     = R_shifted - sub_val;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE; root <= 16'd0; done <= 1'b0;
            count <= 5'd0; D <= 32'd0; Q <= 16'd0; R <= 18'd0;
        end else begin
            case (state)
                IDLE: begin
                    done <= 1'b0;
                    if (start) begin
                        D <= radicand; Q <= 16'd0; R <= 18'd0;
                        count <= 5'd16; state <= CALC;
                    end
                end
                CALC: begin
                    if (count > 0) begin
                        count <= count - 1'b1;
                        D <= {D[29:0], 2'b00}; 
                        if (R_sub[17]) begin
                            R <= R_shifted; Q <= {Q[14:0], 1'b0};
                        end else begin
                            R <= R_sub;     Q <= {Q[14:0], 1'b1};
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