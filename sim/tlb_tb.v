// =============================================================
//  tlb_tb.v  —  Testbench for tlb
//  Run with:
//    iverilog -g2012 -o tlb_sim sim/tlb_tb.v design/tlb.v && vvp tlb_sim
// =============================================================
`timescale 1ns/1ps

module tlb_tb;

    reg        clk, rst;
    reg  [3:0] lookup_vpn;
    wire       hit;
    wire [3:0] hit_ppn;
    reg        fill;
    reg  [3:0] fill_vpn, fill_ppn;
    reg        flush;

    tlb dut (
        .clk(clk), .rst(rst),
        .lookup_vpn(lookup_vpn), .hit(hit), .hit_ppn(hit_ppn),
        .fill(fill), .fill_vpn(fill_vpn), .fill_ppn(fill_ppn),
        .flush(flush)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    integer pass_cnt, fail_cnt;

    // Drive one fill on a clock edge
    task fill_entry;
        input [3:0] v;
        input [3:0] p;
        begin
            @(negedge clk);
            fill = 1; fill_vpn = v; fill_ppn = p;
            @(posedge clk); #1;
            fill = 0;
        end
    endtask

    // Combinational lookup check
    task check_lookup;
        input [3:0] v;
        input       exp_hit;
        input [3:0] exp_ppn;
        input [127:0] name;
        begin
            lookup_vpn = v; #1;
            if (hit === exp_hit && (!exp_hit || hit_ppn === exp_ppn)) begin
                $display("  PASS: %0s (vpn=%0d hit=%b ppn=%0d)", name, v, hit, hit_ppn);
                pass_cnt = pass_cnt + 1;
            end else begin
                $display("  FAIL: %0s (vpn=%0d hit=%b ppn=%0d, want hit=%b ppn=%0d)",
                         name, v, hit, hit_ppn, exp_hit, exp_ppn);
                fail_cnt = fail_cnt + 1;
            end
        end
    endtask

    integer i;

    initial begin
        $dumpfile("tlb.vcd");
        $dumpvars(0, tlb_tb);
        pass_cnt = 0; fail_cnt = 0;
        rst = 1; fill = 0; flush = 0; lookup_vpn = 0; fill_vpn = 0; fill_ppn = 0;
        @(posedge clk); #1;
        rst = 0;

        // --------------------------------------------------
        // Test 1: every VPN misses after reset
        // --------------------------------------------------
        $display("TEST 1: reset state");
        for (i = 0; i < 16; i = i + 1)
            check_lookup(i[3:0], 1'b0, 4'h0, "miss after reset");

        // --------------------------------------------------
        // Test 2: fill VPN 0..3 with PPN 8..11, all hit
        // --------------------------------------------------
        $display("TEST 2: fill and hit");
        for (i = 0; i < 4; i = i + 1)
            fill_entry(i[3:0], i[3:0] + 4'd8);
        for (i = 0; i < 4; i = i + 1)
            check_lookup(i[3:0], 1'b1, i[3:0] + 4'd8, "hit after fill");

        // --------------------------------------------------
        // Test 3: fifth fill evicts the round-robin victim (way 0 / VPN 0)
        // --------------------------------------------------
        $display("TEST 3: round-robin replacement");
        fill_entry(4'd4, 4'd12);
        check_lookup(4'd0, 1'b0, 4'h0,  "VPN 0 evicted by fifth fill");
        check_lookup(4'd4, 1'b1, 4'd12, "VPN 4 hits PPN 12");
        check_lookup(4'd1, 1'b1, 4'd9,  "VPN 1 survives");
        check_lookup(4'd2, 1'b1, 4'd10, "VPN 2 survives");
        check_lookup(4'd3, 1'b1, 4'd11, "VPN 3 survives");

        // --------------------------------------------------
        // Test 4: one-clock flush invalidates everything
        // --------------------------------------------------
        $display("TEST 4: flush");
        @(negedge clk);
        flush = 1;
        @(posedge clk); #1;
        flush = 0;
        for (i = 0; i < 16; i = i + 1)
            check_lookup(i[3:0], 1'b0, 4'h0, "miss after flush");

        $display("\n%0d passed, %0d failed.", pass_cnt, fail_cnt);
        if (fail_cnt != 0) $fatal(1, "TLB regression failed");
        $finish;
    end

endmodule
