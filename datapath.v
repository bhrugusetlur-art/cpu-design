// =============================================================
//  datapath.v  —  CPU datapath (wires all modules together)
//
//  Register file port assignment:
//    rs1 port reads instr[9:8]  (Rs) — ALU input B, LOAD addr, STORE data
//    rs2 port reads instr[11:10](Rd) — ALU input A, STORE addr
//
//  Write-back mux (wb_sel from control):
//    00 WB_ALU — ALU result      (ADD/SUB/AND/OR/NOT)
//    01 WB_MEM — cpu_rdata       (LOAD)
//    10 WB_IMM — imm             (MOV Rd,#imm)
//    11 WB_RS1 — rs1_data        (MOV Rd,Rs)
//
//  Cache address mux:
//    LOAD  (mem_we=0): cpu_addr = rs1_data  (Rs holds the address)
//    STORE (mem_we=1): cpu_addr = rs2_data  (Rd holds the address)
// =============================================================

module datapath #(
    parameter MEM_FILE = "program.mem"
) (
    input  wire        clk,
    input  wire        rst,

    // Data memory interface — wired to cache_hierarchy in cpu_top
    output wire [7:0]  cpu_addr,
    output wire [7:0]  cpu_wdata,
    output wire        cpu_we,
    output wire        cpu_req,
    input  wire [7:0]  cpu_rdata,
    input  wire        stall,

    output wire        halt,
    output wire [7:0]  pc_out
);

    // ---------- internal wires ----------
    wire [7:0]  pc_val;
    wire [15:0] instr;

    wire [1:0]  ctrl_rd, ctrl_rs1;
    wire [7:0]  ctrl_imm;
    wire [2:0]  ctrl_alu_op;
    wire [1:0]  ctrl_wb_sel;
    wire        ctrl_reg_wr_en, ctrl_mem_req, ctrl_mem_we;
    wire        ctrl_jump, ctrl_branch, ctrl_halt;

    wire [7:0]  rs1_data, rs2_data;
    wire [7:0]  alu_result;
    wire        zero_flag, carry_flag;

    // ---------- write-back mux ----------
    reg [7:0] wb_data;
    always @(*) begin
        case (ctrl_wb_sel)
            2'b00:   wb_data = alu_result;
            2'b01:   wb_data = cpu_rdata;
            2'b10:   wb_data = ctrl_imm;
            2'b11:   wb_data = rs1_data;
            default: wb_data = 8'h00;
        endcase
    end

    // ---------- cache interface ----------
    assign cpu_addr  = ctrl_mem_we ? rs2_data : rs1_data;
    assign cpu_wdata = rs1_data;
    assign cpu_we    = ctrl_mem_we;
    assign cpu_req   = ctrl_mem_req;

    assign halt   = ctrl_halt;
    assign pc_out = pc_val;

    // ---------- module instances ----------
    pc pc_inst (
        .clk(clk), .rst(rst),
        .jump(ctrl_jump), .branch(ctrl_branch),
        .zero_flag(zero_flag), .stall(stall), .halt(ctrl_halt),
        .jump_target(ctrl_imm),
        .pc(pc_val)
    );

    imem #(.MEM_FILE(MEM_FILE)) imem_inst (
        .addr(pc_val), .instr(instr)
    );

    control ctrl_inst (
        .instr(instr),
        .rd_addr(ctrl_rd), .rs1_addr(ctrl_rs1), .imm(ctrl_imm),
        .alu_op(ctrl_alu_op), .wb_sel(ctrl_wb_sel),
        .reg_wr_en(ctrl_reg_wr_en), .mem_req(ctrl_mem_req), .mem_we(ctrl_mem_we),
        .jump(ctrl_jump), .branch(ctrl_branch), .halt(ctrl_halt)
    );

    reg_file rf_inst (
        .clk(clk), .rst(rst),
        .rs1_addr(ctrl_rs1),  .rs1_data(rs1_data),   // reads Rs
        .rs2_addr(ctrl_rd),   .rs2_data(rs2_data),    // reads Rd
        .rd_addr(ctrl_rd),    .rd_data(wb_data),
        .wr_en(ctrl_reg_wr_en && !stall)
    );

    alu alu_inst (
        .a(rs2_data),     // current Rd value
        .b(rs1_data),     // Rs value
        .op(ctrl_alu_op),
        .result(alu_result), .zero(zero_flag), .carry(carry_flag)
    );

endmodule
