// =============================================================
//  cpu_vm_tb.v  —  Full-CPU virtual memory regression
//  Runs sim/vm_program.mem on the real cpu_top (datapath + MMU +
//  TLB + L1/L2 + dmem):
//    1. writes valid PTE 0x83 to VA/PA 0xF2 (VPN 2 → PPN 3)
//    2. stores 0x5A at remapped VA 0x21 → PA 0x31, loads it back
//    3. invalidates PTE 0xF4, then faults on LOAD VA 0x40
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

    integer pass_cnt, fail_cnt;

    task check8;
        input [7:0]   got, want;
        input [199:0] name;
        begin
            if (got === want) begin
                $display("  PASS: %0s = 0x%02h", name, got);
                pass_cnt = pass_cnt + 1;
            end else begin
                $display("  FAIL: %0s got 0x%02h want 0x%02h", name, got, want);
                fail_cnt = fail_cnt + 1;
            end
        end
    endtask

    integer cycles, i;
    reg [7:0] fault_pc, fault_r3;

    initial begin
        $dumpfile("cpu_vm.vcd");
        $dumpvars(0, cpu_vm_tb);
        pass_cnt = 0; fail_cnt = 0;

        repeat (2) @(posedge clk);
        rst = 0;

        cycles = 0;
        while (!debug_page_fault && cycles < 1200) begin
            @(posedge clk);
            cycles = cycles + 1;
        end
        $display("Page fault after %0d cycles (PC=0x%02h)", cycles, pc_out);

        check8({7'b0, debug_page_fault}, 8'h01, "page fault asserted");
        check8(debug_fault_va, 8'h40, "faulting virtual address");
        check8(dut.dp.rf_inst.regs[0], 8'h00, "PTE invalidation value");
        check8(dut.dp.rf_inst.regs[3], 8'h5A, "faulting LOAD did not write R3");
        check8(dut.cache.l1.data[4][1], 8'h5A, "remapped PA 0x31 cached data");

        // Fault state must be frozen: same PC, fault VA, and R3 later
        fault_pc = pc_out;
        fault_r3 = dut.dp.rf_inst.regs[3];
        for (i = 0; i < 5; i = i + 1) @(posedge clk);
        check8(pc_out, fault_pc, "PC frozen after fault");
        check8(debug_fault_va, 8'h40, "fault VA stable");
        check8(dut.dp.rf_inst.regs[3], fault_r3, "R3 stable after fault");

        $display("\n%0d passed, %0d failed.", pass_cnt, fail_cnt);
        if (fail_cnt != 0) $fatal(1, "VM regression failed");
        $finish;
    end

endmodule
