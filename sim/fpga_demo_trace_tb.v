// Produces the CPU-state trace used by the README's Basys3 simulation visual.
// The program and final assertions match the full cpu_top integration test.
`timescale 1ns/1ps

module fpga_demo_trace_tb;

    reg clk = 1'b0;
    reg rst = 1'b1;

    wire halt;
    wire [7:0] pc_out;
    wire [7:0] debug_r0, debug_r1, debug_r2, debug_r3;
    wire debug_zero_flag;
    wire [15:0] debug_instr;
    wire [7:0] debug_cpu_addr;
    wire debug_cpu_req, debug_cpu_we, debug_stall;
    wire debug_page_fault;
    wire [7:0] debug_fault_va;

    cpu_top #(.MEM_FILE("sim/fpga_demo.mem")) dut (
        .clk(clk),
        .rst(rst),
        .halt(halt),
        .pc_out(pc_out),
        .debug_r0(debug_r0),
        .debug_r1(debug_r1),
        .debug_r2(debug_r2),
        .debug_r3(debug_r3),
        .debug_zero_flag(debug_zero_flag),
        .debug_instr(debug_instr),
        .debug_cpu_addr(debug_cpu_addr),
        .debug_cpu_req(debug_cpu_req),
        .debug_cpu_we(debug_cpu_we),
        .debug_stall(debug_stall),
        .debug_page_fault(debug_page_fault),
        .debug_fault_va(debug_fault_va)
    );

    always #5 clk = ~clk;

    integer trace_file;
    integer cycles;

    task write_trace_row;
        begin
            $fdisplay(
                trace_file,
                "%0d,%02h,%0d,%0d,%0d,%0d,%02h,%0d,%0d,%02h,%02h,%02h,%02h,%02h,%04h",
                cycles,
                pc_out,
                halt,
                debug_stall,
                debug_cpu_req,
                debug_cpu_we,
                debug_cpu_addr,
                debug_zero_flag,
                debug_page_fault,
                debug_fault_va,
                debug_r0,
                debug_r1,
                debug_r2,
                debug_r3,
                debug_instr
            );
        end
    endtask

    initial begin
        trace_file = $fopen("build/fpga-demo-trace.csv", "w");
        if (trace_file == 0)
            $fatal(1, "could not open build/fpga-demo-trace.csv");

        $fdisplay(
            trace_file,
            "cycle,pc,halt,stall,req,we,addr,zero,page_fault,fault_va,r0,r1,r2,r3,instr"
        );

        repeat (2) @(posedge clk);
        rst = 1'b0;

        cycles = 0;
        while (!halt && cycles < 500) begin
            @(negedge clk);
            #1;
            cycles = cycles + 1;
            write_trace_row();
        end

        $fclose(trace_file);

        if (!halt)
            $fatal(1, "CPU did not halt within 500 cycles");
        if (pc_out !== 8'h06)
            $fatal(1, "unexpected final PC: %02h", pc_out);
        if (debug_r0 !== 8'h0D || debug_r1 !== 8'h03 ||
            debug_r2 !== 8'h0D || debug_r3 !== 8'h0D)
            $fatal(
                1,
                "unexpected final registers: R0=%02h R1=%02h R2=%02h R3=%02h",
                debug_r0,
                debug_r1,
                debug_r2,
                debug_r3
            );

        $display("PASS: wrote build/fpga-demo-trace.csv after %0d cycles", cycles);
        $finish;
    end

endmodule
