`timescale 1ns/1ps
module dbg_cputop;
    reg clk, rst;
    wire halt;
    wire [7:0] pc_out;
    wire [7:0] debug_r0, debug_r1, debug_r2, debug_r3;
    wire       debug_zero_flag;
    wire [15:0] debug_instr;
    wire [7:0] debug_cpu_addr;
    wire       debug_cpu_req, debug_cpu_we, debug_stall;

    cpu_top #(.MEM_FILE("sim/test_datapath.mem")) dut (
        .clk(clk), .rst(rst), .halt(halt), .pc_out(pc_out),
        .debug_r0(debug_r0), .debug_r1(debug_r1),
        .debug_r2(debug_r2), .debug_r3(debug_r3),
        .debug_zero_flag(debug_zero_flag), .debug_instr(debug_instr),
        .debug_cpu_addr(debug_cpu_addr), .debug_cpu_req(debug_cpu_req),
        .debug_cpu_we(debug_cpu_we), .debug_stall(debug_stall)
    );
    initial clk = 0;
    always #5 clk = ~clk;

    integer cycles;
    initial begin
        rst = 1; repeat(2) @(posedge clk); rst = 0;
        cycles = 0;
        while (!halt && cycles < 80) begin
            @(posedge clk); #1;
            cycles = cycles + 1;
            $display("cy=%0d pc=%0h stall=%b stall_d=%b cache_req=%b req=%b we=%b addr=%h wdata=%h rdata=%h R3=%h",
                cycles,
                dut.dp.pc_val,
                dut.dp.stall,
                dut.stall_d,
                dut.cache_req,
                dut.dp.cpu_req,
                dut.dp.cpu_we,
                dut.dp.cpu_addr,
                dut.dp.cpu_wdata,
                dut.dp.cpu_rdata,
                dut.dp.rf_inst.regs[3]
            );
        end
        $display("HALT: halt=%b pc=%h R3=%h", halt, pc_out, dut.dp.rf_inst.regs[3]);
        $finish;
    end
endmodule
