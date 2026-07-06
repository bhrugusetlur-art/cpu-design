// =============================================================
//  datapath_tb.v  —  Testbench for datapath
//  Uses a 0-latency memory stub (stall=0 always) so each
//  instruction completes in exactly one clock cycle.
//
//  Test program (test_datapath.mem):
//    addr 0: 100A  MOV R0, #0x0A   → R0 = 10
//    addr 1: 1403  MOV R1, #0x03   → R1 =  3
//    addr 2: 2100  ADD R0, R1      → R0 = 13 (0x0D)
//    addr 3: 0800  MOV R2, R0      → R2 = 0x0D
//    addr 4: 8800  STORE R0, [R2]  → mem[0x0D] = 0x0D
//    addr 5: 7E00  LOAD  R3, [R2]  → R3 = mem[0x0D] = 0x0D
//    addr 6: F000  HALT
//
//  Run with:
//    iverilog -g2012 -o dp_sim datapath_tb.v datapath.v \
//             pc.v imem.v control.v reg_file.v alu.v && vvp dp_sim
// =============================================================
`timescale 1ns/1ps

module datapath_tb;

    reg        clk, rst;
    wire [7:0] cpu_addr, cpu_wdata;
    wire       cpu_we, cpu_req;
    reg  [7:0] cpu_rdata;
    wire       halt;
    wire [7:0] pc_out;
    wire [7:0] debug_r0, debug_r1, debug_r2, debug_r3;
    wire       debug_zero_flag;
    wire [15:0] debug_instr;

    datapath #(.MEM_FILE("test_datapath.mem")) dut (
        .clk(clk), .rst(rst),
        .cpu_addr(cpu_addr), .cpu_wdata(cpu_wdata),
        .cpu_we(cpu_we), .cpu_req(cpu_req),
        .cpu_rdata(cpu_rdata), .stall(1'b0),
        .halt(halt), .pc_out(pc_out),
        .debug_r0(debug_r0), .debug_r1(debug_r1),
        .debug_r2(debug_r2), .debug_r3(debug_r3),
        .debug_zero_flag(debug_zero_flag), .debug_instr(debug_instr)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    integer pass_cnt, fail_cnt;

    // 0-latency memory stub: combinational read, synchronous write
    reg [7:0] stub_mem [0:255];
    always @(*) cpu_rdata = stub_mem[cpu_addr];
    always @(posedge clk)
        if (cpu_req && cpu_we)
            stub_mem[cpu_addr] <= cpu_wdata;

    task check_reg;
        input [1:0]   rnum;
        input [7:0]   exp;
        input [127:0] label;
        reg [7:0] got;
        begin
            case (rnum)
                2'd0: got = dut.rf_inst.regs[0];
                2'd1: got = dut.rf_inst.regs[1];
                2'd2: got = dut.rf_inst.regs[2];
                2'd3: got = dut.rf_inst.regs[3];
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
        $dumpfile("datapath.vcd");
        $dumpvars(0, datapath_tb);
        pass_cnt = 0; fail_cnt = 0;

        // Reset
        rst = 1;
        repeat(2) @(posedge clk);
        rst = 0;

        // Run enough cycles for all 7 instructions to complete
        repeat(15) @(posedge clk); #1;

        if (!halt) begin
            $display("FAIL: CPU did not halt — check program or wiring");
            $finish;
        end
        $display("CPU halted at PC=0x%02h", pc_out);

        // --------------------------------------------------
        // Check register file (via hierarchical reference)
        // --------------------------------------------------
        $display("Registers:");
        check_reg(0, 8'h0D, "R0 (0x0A + 0x03)");
        check_reg(1, 8'h03, "R1 (MOV #3)");
        check_reg(2, 8'h0D, "R2 (MOV R0)");
        check_reg(3, 8'h0D, "R3 (LOAD)");

        // --------------------------------------------------
        // Check memory (STORE wrote 0x0D to addr 0x0D)
        // --------------------------------------------------
        $display("Memory:");
        if (stub_mem[8'h0D] === 8'h0D) begin
            $display("  PASS  mem[0x0D]=0x%02h (STORE verified)", stub_mem[8'h0D]);
            pass_cnt = pass_cnt + 1;
        end else begin
            $display("  FAIL  mem[0x0D]=0x%02h want 0x0D", stub_mem[8'h0D]);
            fail_cnt = fail_cnt + 1;
        end

        $display("\n%0d passed, %0d failed.", pass_cnt, fail_cnt);
        $finish;
    end

endmodule
