// =============================================================
//  cpu_top_tb.v  —  Full integration test for cpu_top
//  Uses the real cache hierarchy + dmem (not a stub).
//  STORE/LOAD stall the CPU on cold cache misses.
//
//  Test program (test_datapath.mem):
//    0: MOV R0, #0x0A    R0 = 10
//    1: MOV R1, #0x03    R1 =  3
//    2: ADD R0, R1       R0 = 13 (0x0D)
//    3: MOV R2, R0       R2 = 0x0D
//    4: STORE R0, [R2]   L1 dirty line at addr 0x0D  (cold miss — stalls)
//    5: LOAD  R3, [R2]   R3 = 0x0D  (L1 hit after STORE fill)
//    6: HALT
//
//  Run with:
//    iverilog -g2012 -o top_sim cpu_top_tb.v cpu_top.v datapath.v \
//             cache_hierarchy.v l1_cache.v l2_cache.v dmem.v \
//             pc.v imem.v control.v reg_file.v alu.v && vvp top_sim
// =============================================================
`timescale 1ns/1ps

module cpu_top_tb;

    reg  clk, rst;
    wire halt;
    wire [7:0] pc_out;
    wire [7:0] debug_r0, debug_r1, debug_r2, debug_r3;
    wire       debug_zero_flag;
    wire [15:0] debug_instr;
    wire [7:0] debug_cpu_addr;
    wire       debug_cpu_req, debug_cpu_we, debug_stall;

    cpu_top #(.MEM_FILE("test_datapath.mem")) dut (
        .clk(clk), .rst(rst), .halt(halt), .pc_out(pc_out),
        .debug_r0(debug_r0), .debug_r1(debug_r1),
        .debug_r2(debug_r2), .debug_r3(debug_r3),
        .debug_zero_flag(debug_zero_flag), .debug_instr(debug_instr),
        .debug_cpu_addr(debug_cpu_addr), .debug_cpu_req(debug_cpu_req),
        .debug_cpu_we(debug_cpu_we), .debug_stall(debug_stall)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    integer pass_cnt, fail_cnt, cycles;

    task check_reg;
        input [1:0]   rnum;
        input [7:0]   exp;
        input [127:0] label;
        reg [7:0] got;
        begin
            case (rnum)
                2'd0: got = dut.dp.rf_inst.regs[0];
                2'd1: got = dut.dp.rf_inst.regs[1];
                2'd2: got = dut.dp.rf_inst.regs[2];
                2'd3: got = dut.dp.rf_inst.regs[3];
            endcase
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
        $dumpfile("cpu_top.vcd");
        $dumpvars(0, cpu_top_tb);
        pass_cnt = 0; fail_cnt = 0;

        // Reset
        rst = 1;
        repeat(2) @(posedge clk);
        rst = 0;

        // Run until halt, with timeout guard
        cycles = 0;
        while (!halt && cycles < 500) begin
            @(posedge clk); #1;
            cycles = cycles + 1;
        end

        if (!halt) begin
            $display("FAIL: CPU did not halt within 500 cycles");
            $finish;
        end

        $display("CPU halted at PC=0x%02h after %0d cycles", pc_out, cycles);

        // --------------------------------------------------
        // Check registers
        // --------------------------------------------------
        $display("Registers:");
        check_reg(0, 8'h0D, "R0 (ADD result)");
        check_reg(1, 8'h03, "R1 (MOV #3)");
        check_reg(2, 8'h0D, "R2 (MOV R0)");
        check_reg(3, 8'h0D, "R3 (LOAD from cache)");

        // --------------------------------------------------
        // Check L1 cache — write-back keeps the dirty line in L1
        // (dmem is not updated until eviction, so check L1 directly)
        // addr 0x0D: index=3, offset=1
        // --------------------------------------------------
        $display("L1 cache (write-back dirty line):");
        if (dut.cache.l1.data[3][1] === 8'h0D) begin
            $display("  PASS  L1.data[3][1]=0x%02h (STORE in write-back line)",
                     dut.cache.l1.data[3][1]);
            pass_cnt = pass_cnt + 1;
        end else begin
            $display("  FAIL  L1.data[3][1]=0x%02h want 0x0D",
                     dut.cache.l1.data[3][1]);
            fail_cnt = fail_cnt + 1;
        end

        $display("\n%0d passed, %0d failed.", pass_cnt, fail_cnt);
        $finish;
    end

endmodule
