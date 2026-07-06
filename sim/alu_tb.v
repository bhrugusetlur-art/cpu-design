// =============================================================
//  alu_tb.v  —  Testbench for alu
//  Run with:
//    iverilog -g2012 -o alu_tb sim/alu_tb.v design/alu.v && vvp alu_tb
// =============================================================
`timescale 1ns/1ps

module alu_tb;

    reg  [7:0] a, b;
    reg  [2:0] op;
    wire [7:0] result;
    wire       zero, carry;

    alu dut (.a(a), .b(b), .op(op), .result(result), .zero(zero), .carry(carry));

    integer pass_cnt, fail_cnt;

    task check;
        input [7:0]  exp_result;
        input        exp_zero;
        input        exp_carry;
        input [127:0] label;
        begin
            #1;
            if (result === exp_result && zero === exp_zero && carry === exp_carry) begin
                $display("  PASS  %0s", label);
                pass_cnt = pass_cnt + 1;
            end else begin
                $display("  FAIL  %0s", label);
                $display("        got  result=0x%02h z=%b c=%b", result, zero, carry);
                $display("        want result=0x%02h z=%b c=%b", exp_result, exp_zero, exp_carry);
                fail_cnt = fail_cnt + 1;
            end
        end
    endtask

    initial begin
        pass_cnt = 0; fail_cnt = 0;

        // --- ADD ---
        $display("ADD:");
        a = 8'h0F; b = 8'h01; op = 3'b010;
        check(8'h10, 0, 0, "0x0F + 0x01 = 0x10");

        a = 8'hFF; b = 8'h01; op = 3'b010;
        check(8'h00, 1, 1, "0xFF + 0x01 = 0x00  carry=1  zero=1");

        a = 8'h80; b = 8'h80; op = 3'b010;
        check(8'h00, 1, 1, "0x80 + 0x80 = 0x00  carry=1  zero=1");

        a = 8'h00; b = 8'h00; op = 3'b010;
        check(8'h00, 1, 0, "0x00 + 0x00 = 0x00  carry=0  zero=1");

        // --- SUB ---
        $display("SUB:");
        a = 8'h05; b = 8'h03; op = 3'b011;
        check(8'h02, 0, 1, "0x05 - 0x03 = 0x02  carry=1 (no borrow)");

        a = 8'h03; b = 8'h05; op = 3'b011;
        check(8'hFE, 0, 0, "0x03 - 0x05 = 0xFE  carry=0 (borrow)");

        a = 8'h05; b = 8'h05; op = 3'b011;
        check(8'h00, 1, 1, "0x05 - 0x05 = 0x00  carry=1  zero=1");

        a = 8'h00; b = 8'h01; op = 3'b011;
        check(8'hFF, 0, 0, "0x00 - 0x01 = 0xFF  carry=0 (borrow)");

        // --- AND ---
        $display("AND:");
        a = 8'hFF; b = 8'hAA; op = 3'b100;
        check(8'hAA, 0, 0, "0xFF & 0xAA = 0xAA");

        a = 8'hF0; b = 8'h0F; op = 3'b100;
        check(8'h00, 1, 0, "0xF0 & 0x0F = 0x00  zero=1");

        // --- OR ---
        $display("OR:");
        a = 8'hF0; b = 8'h0F; op = 3'b101;
        check(8'hFF, 0, 0, "0xF0 | 0x0F = 0xFF");

        a = 8'h00; b = 8'h00; op = 3'b101;
        check(8'h00, 1, 0, "0x00 | 0x00 = 0x00  zero=1");

        // --- NOT ---
        $display("NOT:");
        a = 8'h00; b = 8'hXX; op = 3'b110;
        check(8'hFF, 0, 0, "~0x00 = 0xFF");

        a = 8'hFF; b = 8'hXX; op = 3'b110;
        check(8'h00, 1, 0, "~0xFF = 0x00  zero=1");

        a = 8'hAA; b = 8'hXX; op = 3'b110;
        check(8'h55, 0, 0, "~0xAA = 0x55");

        $display("\n%0d passed, %0d failed.", pass_cnt, fail_cnt);
        $finish;
    end

endmodule
