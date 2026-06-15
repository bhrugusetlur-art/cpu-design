// =============================================================
//  pc_tb.v  —  Testbench for pc
//  Run with:
//    iverilog -g2012 -o pc_sim pc_tb.v pc.v && vvp pc_sim
// =============================================================
`timescale 1ns/1ps

module pc_tb;

    reg        clk, rst;
    reg        jump, branch, zero_flag, stall, halt;
    reg  [7:0] jump_target;
    wire [7:0] pc;

    pc dut (
        .clk(clk), .rst(rst),
        .jump(jump), .branch(branch), .zero_flag(zero_flag),
        .stall(stall), .halt(halt),
        .jump_target(jump_target),
        .pc(pc)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    integer pass_cnt, fail_cnt;

    // Drive inputs at negedge, check result 1ns after the next posedge
    task step;
        input j, br, z, s, h;
        input [7:0] tgt;
        begin
            @(negedge clk);
            jump=j; branch=br; zero_flag=z; stall=s; halt=h; jump_target=tgt;
            @(posedge clk); #1;
        end
    endtask

    task check_pc;
        input [7:0]   exp;
        input [127:0] label;
        begin
            if (pc === exp) begin
                $display("  PASS  %0s: pc=0x%02h", label, pc);
                pass_cnt = pass_cnt + 1;
            end else begin
                $display("  FAIL  %0s: got 0x%02h want 0x%02h", label, pc, exp);
                fail_cnt = fail_cnt + 1;
            end
        end
    endtask

    initial begin
        $dumpfile("pc.vcd");
        $dumpvars(0, pc_tb);
        pass_cnt = 0; fail_cnt = 0;
        jump=0; branch=0; zero_flag=0; stall=0; halt=0; jump_target=0;

        // --------------------------------------------------
        // Test 1: reset drives pc to 0
        // --------------------------------------------------
        $display("TEST 1: reset");
        rst = 1;
        repeat(2) @(posedge clk); #1;
        check_pc(8'h00, "pc=0 after rst");
        rst = 0;

        // --------------------------------------------------
        // Test 2: normal increment
        // --------------------------------------------------
        $display("TEST 2: normal increment");
        step(0,0,0,0,0, 8'h00);
        step(0,0,0,0,0, 8'h00);
        step(0,0,0,0,0, 8'h00);
        check_pc(8'h03, "pc=3 after 3 steps");

        // --------------------------------------------------
        // Test 3: unconditional jump
        // --------------------------------------------------
        $display("TEST 3: JMP");
        step(1,0,0,0,0, 8'h20);       // jump to 0x20
        check_pc(8'h20, "pc=0x20 after JMP");
        step(0,0,0,0,0, 8'h00);        // continues from jump target
        check_pc(8'h21, "pc=0x21 after step past JMP");

        // --------------------------------------------------
        // Test 4: JZ not taken (zero_flag=0)
        // --------------------------------------------------
        $display("TEST 4: JZ not taken (zero=0)");
        step(0,1,0,0,0, 8'h30);       // branch=1 but zero=0
        check_pc(8'h22, "pc=0x22, JZ skipped");

        // --------------------------------------------------
        // Test 5: JZ taken (zero_flag=1)
        // --------------------------------------------------
        $display("TEST 5: JZ taken (zero=1)");
        step(0,1,1,0,0, 8'h40);       // branch=1 and zero=1
        check_pc(8'h40, "pc=0x40 after JZ taken");

        // --------------------------------------------------
        // Test 6: stall holds pc for 2 cycles then releases
        // --------------------------------------------------
        $display("TEST 6: stall");
        step(0,0,0,1,0, 8'h00);       // stall cycle 1
        check_pc(8'h40, "pc=0x40 held cycle 1");
        step(0,0,0,1,0, 8'h00);       // stall cycle 2
        check_pc(8'h40, "pc=0x40 held cycle 2");
        step(0,0,0,0,0, 8'h00);       // stall released
        check_pc(8'h41, "pc=0x41 resumes after stall");

        // --------------------------------------------------
        // Test 7: halt freezes pc permanently
        // --------------------------------------------------
        $display("TEST 7: halt");
        step(0,0,0,0,1, 8'h00);
        check_pc(8'h41, "pc=0x41 frozen (halt cycle 1)");
        step(0,0,0,0,1, 8'h00);
        check_pc(8'h41, "pc=0x41 frozen (halt cycle 2)");

        $display("\n%0d passed, %0d failed.", pass_cnt, fail_cnt);
        $finish;
    end

endmodule
