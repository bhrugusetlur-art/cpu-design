// =============================================================
//  imem_tb.v  —  Testbench for imem
//  Run with:
//    iverilog -g2012 -o imem_sim sim/imem_tb.v design/imem.v && vvp imem_sim
// =============================================================
`timescale 1ns/1ps

module imem_tb;

    reg  [7:0]  addr;
    wire [15:0] instr;

    imem #(.MEM_FILE("sim/test_imem.mem")) dut (.addr(addr), .instr(instr));

    integer pass_cnt, fail_cnt;

    task check_instr;
        input [7:0]   a;
        input [15:0]  exp;
        input [127:0] label;
        begin
            addr = a; #1;
            if (instr === exp) begin
                $display("  PASS  %0s", label);
                pass_cnt = pass_cnt + 1;
            end else begin
                $display("  FAIL  %0s: got 0x%04h want 0x%04h", label, instr, exp);
                fail_cnt = fail_cnt + 1;
            end
        end
    endtask

    initial begin
        $dumpfile("imem.vcd");
        $dumpvars(0, imem_tb);
        pass_cnt = 0; fail_cnt = 0;

        $display("IMEM: read test");
        check_instr(8'd0, 16'h1042, "addr 0");
        check_instr(8'd1, 16'h2400, "addr 1");
        check_instr(8'd2, 16'h3100, "addr 2");
        check_instr(8'd3, 16'h4000, "addr 3");
        check_instr(8'd4, 16'hF000, "addr 4");

        $display("\n%0d passed, %0d failed.", pass_cnt, fail_cnt);
        $finish;
    end

endmodule
