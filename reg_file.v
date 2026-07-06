// =============================================================
//  reg_file.v - 4x8-bit register file
//  R0-R3, 2 asynchronous read ports, 1 synchronous write port
// =============================================================

module reg_file (
    input  wire        clk,
    input  wire        rst,

    // Read port 1
    input  wire [1:0]  rs1_addr,
    output wire [7:0]  rs1_data,

    // Read port 2
    input  wire [1:0]  rs2_addr,
    output wire [7:0]  rs2_data,

    // Write port
    input  wire [1:0]  rd_addr,
    input  wire [7:0]  rd_data,
    input  wire        wr_en,

    // Debug outputs
    output wire [7:0]  debug_r0,
    output wire [7:0]  debug_r1,
    output wire [7:0]  debug_r2,
    output wire [7:0]  debug_r3
);

    reg [7:0] regs [0:3];

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            regs[0] <= 8'h00;
            regs[1] <= 8'h00;
            regs[2] <= 8'h00;
            regs[3] <= 8'h00;
        end else if (wr_en) begin
            regs[rd_addr] <= rd_data;
        end
    end

    assign rs1_data = regs[rs1_addr];
    assign rs2_data = regs[rs2_addr];

    assign debug_r0 = regs[0];
    assign debug_r1 = regs[1];
    assign debug_r2 = regs[2];
    assign debug_r3 = regs[3];

endmodule