// =============================================================
//  pc.v  —  Program Counter
//
//  Priority (high → low):
//    1. rst   — reset to 0
//    2. halt  — freeze (HALT instruction executing)
//    3. stall — freeze (cache miss on LOAD/STORE)
//    4. jump  — load jump_target (JMP)
//       branch && zero_flag — load jump_target (JZ taken)
//    5. default — increment by 1
// =============================================================

module pc (
    input  wire        clk,
    input  wire        rst,
    input  wire        jump,
    input  wire        branch,
    input  wire        zero_flag,
    input  wire        stall,
    input  wire        halt,
    input  wire [7:0]  jump_target,
    output reg  [7:0]  pc
);
    always @(posedge clk or posedge rst) begin
        if (rst)
            pc <= 8'h00;
        else if (halt || stall)
            pc <= pc;
        else if (jump || (branch && zero_flag))
            pc <= jump_target;
        else
            pc <= pc + 8'd1;
    end

endmodule
