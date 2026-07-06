// =============================================================
//  datapath.v - CPU datapath
// =============================================================

module datapath #(
    parameter MEM_FILE = "program.mem"
) (
    input  wire        clk,
    input  wire        rst,

    // Data memory interface
    output wire [7:0]  cpu_addr,
    output wire [7:0]  cpu_wdata,
    output wire        cpu_we,
    output wire        cpu_req,
    input  wire [7:0]  cpu_rdata,
    input  wire        stall,

    output wire        halt,
    output wire [7:0]  pc_out,

    output wire [7:0]  debug_r0,
    output wire [7:0]  debug_r1,
    output wire [7:0]  debug_r2,
    output wire [7:0]  debug_r3,
    output wire        debug_zero_flag,
    output wire [15:0] debug_instr
);

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
    wire        alu_zero_flag, carry_flag;

    reg         saved_zero_flag;

    wire is_alu_instr = ctrl_reg_wr_en && (ctrl_wb_sel == 2'b00);

    always @(posedge clk or posedge rst) begin
        if (rst)
            saved_zero_flag <= 1'b0;
        else if (!stall && is_alu_instr)
            saved_zero_flag <= alu_zero_flag;
    end

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

    assign cpu_addr  = ctrl_mem_we ? rs2_data : rs1_data;
    assign cpu_wdata = rs1_data;
    assign cpu_we    = ctrl_mem_we;
    assign cpu_req   = ctrl_mem_req;

    assign halt   = ctrl_halt;
    assign pc_out = pc_val;
    assign debug_zero_flag = saved_zero_flag;
    assign debug_instr = instr;

    pc pc_inst (
        .clk(clk), .rst(rst),
        .jump(ctrl_jump), .branch(ctrl_branch),
        .zero_flag(saved_zero_flag), .stall(stall), .halt(ctrl_halt),
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
        .rs1_addr(ctrl_rs1),  .rs1_data(rs1_data),
        .rs2_addr(ctrl_rd),   .rs2_data(rs2_data),
        .rd_addr(ctrl_rd),    .rd_data(wb_data),
        .wr_en(ctrl_reg_wr_en && !stall),
        .debug_r0(debug_r0),
        .debug_r1(debug_r1),
        .debug_r2(debug_r2),
        .debug_r3(debug_r3)
    );

    alu alu_inst (
        .a(rs2_data),
        .b(rs1_data),
        .op(ctrl_alu_op),
        .result(alu_result), .zero(alu_zero_flag), .carry(carry_flag)
    );

endmodule
