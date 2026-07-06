// =============================================================
//  cpu_programs_tb.v - Regression test for FPGA demo programs
//
//  Runs the same programs documented in programs/ and checks the
//  final register values for each CPU instance.
// =============================================================
`timescale 1ns/1ps

module cpu_programs_tb;

    reg clk, rst;

    wire cache_halt, alu_halt, branch_halt;
    wire [7:0] cache_pc, alu_pc, branch_pc;

    wire [7:0] cache_r0, cache_r1, cache_r2, cache_r3;
    wire [7:0] alu_r0, alu_r1, alu_r2, alu_r3;
    wire [7:0] branch_r0, branch_r1, branch_r2, branch_r3;

    wire cache_zero, alu_zero, branch_zero;
    wire [15:0] cache_instr, alu_instr, branch_instr;
    wire [7:0] cache_addr, alu_addr, branch_addr;
    wire cache_req, cache_we, cache_stall;
    wire alu_req, alu_we, alu_stall;
    wire branch_req, branch_we, branch_stall;

    cpu_top #(.MEM_FILE("programs/cache_store_load.mem")) cache_demo (
        .clk(clk), .rst(rst), .halt(cache_halt), .pc_out(cache_pc),
        .debug_r0(cache_r0), .debug_r1(cache_r1),
        .debug_r2(cache_r2), .debug_r3(cache_r3),
        .debug_zero_flag(cache_zero), .debug_instr(cache_instr),
        .debug_cpu_addr(cache_addr), .debug_cpu_req(cache_req),
        .debug_cpu_we(cache_we), .debug_stall(cache_stall)
    );

    cpu_top #(.MEM_FILE("programs/alu_ops.mem")) alu_demo (
        .clk(clk), .rst(rst), .halt(alu_halt), .pc_out(alu_pc),
        .debug_r0(alu_r0), .debug_r1(alu_r1),
        .debug_r2(alu_r2), .debug_r3(alu_r3),
        .debug_zero_flag(alu_zero), .debug_instr(alu_instr),
        .debug_cpu_addr(alu_addr), .debug_cpu_req(alu_req),
        .debug_cpu_we(alu_we), .debug_stall(alu_stall)
    );

    cpu_top #(.MEM_FILE("programs/branch_jz.mem")) branch_demo (
        .clk(clk), .rst(rst), .halt(branch_halt), .pc_out(branch_pc),
        .debug_r0(branch_r0), .debug_r1(branch_r1),
        .debug_r2(branch_r2), .debug_r3(branch_r3),
        .debug_zero_flag(branch_zero), .debug_instr(branch_instr),
        .debug_cpu_addr(branch_addr), .debug_cpu_req(branch_req),
        .debug_cpu_we(branch_we), .debug_stall(branch_stall)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    integer pass_cnt, fail_cnt, cycles;

    task check8;
        input [7:0] got;
        input [7:0] exp;
        input [255:0] label;
        begin
            if (got === exp) begin
                $display("  PASS  %0s: 0x%02h", label, got);
                pass_cnt = pass_cnt + 1;
            end else begin
                $display("  FAIL  %0s: got 0x%02h want 0x%02h", label, got, exp);
                fail_cnt = fail_cnt + 1;
            end
        end
    endtask

    initial begin
        $dumpfile("cpu_programs.vcd");
        $dumpvars(0, cpu_programs_tb);

        pass_cnt = 0;
        fail_cnt = 0;

        rst = 1;
        repeat (2) @(posedge clk);
        rst = 0;

        cycles = 0;
        while (!(cache_halt && alu_halt && branch_halt) && cycles < 500) begin
            @(posedge clk); #1;
            cycles = cycles + 1;
        end

        if (!(cache_halt && alu_halt && branch_halt)) begin
            $display("FAIL: not all programs halted within 500 cycles");
            $display("  cache_halt=%b pc=0x%02h", cache_halt, cache_pc);
            $display("  alu_halt=%b pc=0x%02h", alu_halt, alu_pc);
            $display("  branch_halt=%b pc=0x%02h", branch_halt, branch_pc);
            $fatal(1);
        end

        $display("All demo programs halted after %0d cycles", cycles);

        $display("\ncache_store_load.mem:");
        check8(cache_pc, 8'h06, "PC");
        check8(cache_r0, 8'h0D, "R0");
        check8(cache_r1, 8'h03, "R1");
        check8(cache_r2, 8'h0D, "R2");
        check8(cache_r3, 8'h0D, "R3");
        check8(cache_demo.cache.l1.data[3][1], 8'h0D, "L1 dirty line data");

        $display("\nalu_ops.mem:");
        check8(alu_pc, 8'h07, "PC");
        check8(alu_r0, 8'h0C, "R0");
        check8(alu_r1, 8'h03, "R1");
        check8(alu_r2, 8'h03, "R2");
        check8(alu_r3, 8'hFF, "R3");

        $display("\nbranch_jz.mem:");
        check8(branch_pc, 8'h0E, "PC");
        check8(branch_r0, 8'h02, "R0");
        check8(branch_r1, 8'h03, "R1");
        check8(branch_r2, 8'h02, "R2");
        check8(branch_r3, 8'h04, "R3");

        $display("\nRegression: %0d passed, %0d failed.", pass_cnt, fail_cnt);
        if (fail_cnt != 0)
            $fatal(1);

        $finish;
    end

endmodule
