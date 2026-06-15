// =============================================================
//  reg_file.v  —  4×8-bit register file
//  R0–R3, 2 asynchronous read ports, 1 synchronous write port
//
//  Reads are combinational (same-cycle visibility of current value).
//  Write takes effect on the next rising edge, so a read and write
//  to the same address in the same cycle returns the OLD value.
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
    input  wire        wr_en
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

endmodule
