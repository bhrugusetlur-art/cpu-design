// =============================================================
//  control_tb.v  —  Testbench for control
//  Run with:
//    iverilog -g2012 -o ctrl_sim control_tb.v control.v && vvp ctrl_sim
// =============================================================
`timescale 1ns/1ps

module control_tb;

    reg  [15:0] instr;
    wire [1:0]  rd_addr, rs1_addr;
    wire [7:0]  imm;
    wire [2:0]  alu_op;
    wire [1:0]  wb_sel;
    wire        reg_wr_en, mem_req, mem_we, jump, branch, halt;

    control dut (
        .instr(instr),
        .rd_addr(rd_addr), .rs1_addr(rs1_addr), .imm(imm),
        .alu_op(alu_op), .wb_sel(wb_sel), .reg_wr_en(reg_wr_en),
        .mem_req(mem_req), .mem_we(mem_we),
        .jump(jump), .branch(branch), .halt(halt)
    );

    integer pass_cnt, fail_cnt;

    // Check decoded control signals (not rd_addr/rs1_addr/imm — those are
    // direct slices of instr so they can't be wrong if instr is correct)
    task check;
        input [127:0] label;
        input [2:0]   exp_alu_op;
        input [1:0]   exp_wb_sel;
        input         exp_reg_wr_en;
        input         exp_mem_req, exp_mem_we;
        input         exp_jump, exp_branch, exp_halt;
        reg ok;
        begin
            #1; ok = 1;
            if (alu_op    !== exp_alu_op)    begin $display("    alu_op:    %b got, %b want", alu_op,    exp_alu_op);    ok=0; end
            if (wb_sel    !== exp_wb_sel)    begin $display("    wb_sel:    %b got, %b want", wb_sel,    exp_wb_sel);    ok=0; end
            if (reg_wr_en !== exp_reg_wr_en) begin $display("    reg_wr_en: %b got, %b want", reg_wr_en, exp_reg_wr_en); ok=0; end
            if (mem_req   !== exp_mem_req)   begin $display("    mem_req:   %b got, %b want", mem_req,   exp_mem_req);   ok=0; end
            if (mem_we    !== exp_mem_we)    begin $display("    mem_we:    %b got, %b want", mem_we,    exp_mem_we);    ok=0; end
            if (jump      !== exp_jump)      begin $display("    jump:      %b got, %b want", jump,      exp_jump);      ok=0; end
            if (branch    !== exp_branch)    begin $display("    branch:    %b got, %b want", branch,    exp_branch);    ok=0; end
            if (halt      !== exp_halt)      begin $display("    halt:      %b got, %b want", halt,      exp_halt);      ok=0; end
            if (ok) begin $display("  PASS  %0s", label); pass_cnt=pass_cnt+1; end
            else    begin $display("  FAIL  %0s", label); fail_cnt=fail_cnt+1; end
        end
    endtask

    initial begin
        $dumpfile("control.vcd");
        $dumpvars(0, control_tb);
        pass_cnt = 0; fail_cnt = 0;

        //                         alu_op wb_sel wr mr mw  j  br  h
        // MOV Rd, Rs  — opcode 0000, Rd=01 Rs=00
        instr = 16'h0400; check("MOV Rd Rs",  3'b000, 2'b11, 1, 0,0, 0,0,0);

        // MOV Rd, #imm — opcode 0001, Rd=10, imm=0x42
        instr = 16'h1842; check("MOV Rd imm", 3'b000, 2'b10, 1, 0,0, 0,0,0);

        // ADD Rd, Rs  — opcode 0010, Rd=01 Rs=00
        instr = 16'h2400; check("ADD",        3'b010, 2'b00, 1, 0,0, 0,0,0);

        // SUB Rd, Rs  — opcode 0011, Rd=00 Rs=01
        instr = 16'h3100; check("SUB",        3'b011, 2'b00, 1, 0,0, 0,0,0);

        // AND Rd, Rs  — opcode 0100, Rd=00 Rs=00
        instr = 16'h4000; check("AND",        3'b100, 2'b00, 1, 0,0, 0,0,0);

        // OR  Rd, Rs  — opcode 0101, Rd=01 Rs=00
        instr = 16'h5400; check("OR",         3'b101, 2'b00, 1, 0,0, 0,0,0);

        // NOT Rd      — opcode 0110, Rd=10
        instr = 16'h6800; check("NOT",        3'b110, 2'b00, 1, 0,0, 0,0,0);

        // LOAD Rd,[Rs] — opcode 0111, Rd=01 Rs=00
        instr = 16'h7400; check("LOAD",       3'b000, 2'b01, 1, 1,0, 0,0,0);

        // STORE Rs,[Rd] — opcode 1000, Rd=00(addr) Rs=01(data)
        instr = 16'h8100; check("STORE",      3'b000, 2'b00, 0, 1,1, 0,0,0);

        // JMP addr    — opcode 1001, addr=0x20
        instr = 16'h9020; check("JMP",        3'b000, 2'b00, 0, 0,0, 1,0,0);

        // JZ  addr    — opcode 1010, addr=0x10
        instr = 16'hA010; check("JZ",         3'b000, 2'b00, 0, 0,0, 0,1,0);

        // HALT        — opcode 1111
        instr = 16'hF000; check("HALT",       3'b000, 2'b00, 0, 0,0, 0,0,1);

        // Verify rd_addr / rs1_addr / imm are correct direct slices
        $display("Address/imm slice checks:");
        instr = 16'h2400; #1;  // ADD R1, R0
        if (rd_addr===2'd1 && rs1_addr===2'd0)
            $display("  PASS  rd_addr=R1 rs1_addr=R0");
        else
            $display("  FAIL  rd=%0d rs1=%0d", rd_addr, rs1_addr);

        instr = 16'h9037; #1;  // JMP 0x37
        if (imm===8'h37)
            $display("  PASS  imm=0x%02h from JMP instr", imm);
        else
            $display("  FAIL  imm=0x%02h want 0x37", imm);

        $display("\n%0d passed, %0d failed.", pass_cnt, fail_cnt);
        $finish;
    end

endmodule
