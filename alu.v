// =============================================================
//  alu.v  —  8-bit combinational ALU
//
//  op encoding matches ISA opcode[2:0]:
//    3'b010  ADD    {carry, result} = a + b
//    3'b011  SUB    {carry, result} = a - b  (carry=1 → no borrow, a≥b)
//    3'b100  AND    result = a & b
//    3'b101  OR     result = a | b
//    3'b110  NOT    result = ~a          (b unused)
//
//  Flags:
//    zero  — result == 0 (combinational)
//    carry — unsigned carry/borrow as above; 0 for AND/OR/NOT
// =============================================================

module alu (
    input  wire [7:0]  a,
    input  wire [7:0]  b,
    input  wire [2:0]  op,
    output reg  [7:0]  result,
    output wire        zero,
    output reg         carry
);

    localparam ADD = 3'b010;
    localparam SUB = 3'b011;
    localparam AND = 3'b100;
    localparam OR  = 3'b101;
    localparam NOT = 3'b110;

    wire [8:0] sum  = {1'b0, a} + {1'b0, b};
    wire [8:0] diff = {1'b0, a} + {1'b0, ~b} + 9'd1;

    always @(*) begin
        carry  = 1'b0;
        result = 8'h00;
        case (op)
            ADD: begin result = sum[7:0];  carry = sum[8];  end
            SUB: begin result = diff[7:0]; carry = diff[8]; end
            AND: result = a & b;
            OR:  result = a | b;
            NOT: result = ~a;
            default: result = 8'h00;
        endcase
    end

    assign zero = (result == 8'h00);

endmodule
