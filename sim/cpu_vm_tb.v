// =============================================================
//  cpu_vm_tb.v  —  Virtual memory integration harness
//  Run with:
//    iverilog -g2012 -o vm_sim sim/cpu_vm_tb.v design/cpu_top.v design/mmu.v \
//      design/tlb.v design/datapath.v design/cache_hierarchy.v design/l1_cache.v \
//      design/l2_cache.v design/dmem.v design/pc.v design/imem.v design/control.v \
//      design/reg_file.v design/alu.v && vvp vm_sim
// =============================================================
`timescale 1ns/1ps

module cpu_vm_tb;
    reg clk = 0, rst = 1;
    wire halt, debug_page_fault;
    wire [7:0] pc_out, debug_fault_va;
    wire [7:0] debug_r0, debug_r1, debug_r2, debug_r3;
    wire debug_zero_flag, debug_cpu_req, debug_cpu_we, debug_stall;
    wire [15:0] debug_instr;
    wire [7:0] debug_cpu_addr;

    cpu_top #(.MEM_FILE("sim/vm_program.mem")) dut (
        .clk(clk), .rst(rst), .halt(halt), .pc_out(pc_out),
        .debug_r0(debug_r0), .debug_r1(debug_r1), .debug_r2(debug_r2), .debug_r3(debug_r3),
        .debug_zero_flag(debug_zero_flag), .debug_instr(debug_instr),
        .debug_cpu_addr(debug_cpu_addr), .debug_cpu_req(debug_cpu_req),
        .debug_cpu_we(debug_cpu_we), .debug_stall(debug_stall),
        .debug_page_fault(debug_page_fault), .debug_fault_va(debug_fault_va)
    );
    always #5 clk = ~clk;
endmodule
