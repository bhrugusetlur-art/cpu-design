// =============================================================
//  dmem_tb.v  —  Testbench for dmem
//  Run with:
//    iverilog -g2012 -o dmem_sim sim/dmem_tb.v design/dmem.v && vvp dmem_sim
// =============================================================
`timescale 1ns/1ps

module dmem_tb;

    reg        clk;
    reg  [7:0] addr;
    reg  [7:0] wdata;
    reg        we, re;
    wire [7:0] rdata;
    wire       ready;

    dmem dut (.clk(clk), .addr(addr), .wdata(wdata), .we(we), .re(re),
              .rdata(rdata), .ready(ready));

    initial clk = 0;
    always #5 clk = ~clk;

    integer pass_cnt, fail_cnt;

    // Write wdata to addr; ready pulses high same posedge
    task mem_write;
        input [7:0] a;
        input [7:0] d;
        begin
            @(negedge clk);
            addr = a; wdata = d; we = 1; re = 0;
            @(posedge clk); #1;
            we = 0;
        end
    endtask

    // Read from addr; rdata valid 1 cycle after re asserted
    task mem_read;
        input  [7:0]  a;
        output [7:0]  d;
        begin
            @(negedge clk);
            addr = a; re = 1; we = 0;
            @(posedge clk); #1;
            d  = rdata;
            re = 0;
        end
    endtask

    initial begin
        $dumpfile("dmem.vcd");
        $dumpvars(0, dmem_tb);
        pass_cnt = 0; fail_cnt = 0;
        we = 0; re = 0; addr = 0; wdata = 0;
        @(posedge clk); #1;

        // --------------------------------------------------
        // Test 0: identity PTE boot image at 0xF0-0xFF
        // --------------------------------------------------
        $display("TEST 0: identity PTE boot image");
        if (dut.mem[8'hF0] !== 8'h80 ||
            dut.mem[8'hF5] !== 8'h85 ||
            dut.mem[8'hFF] !== 8'h8F) begin
            $display("  FAIL: identity PTE boot image missing");
            fail_cnt = fail_cnt + 1;
        end else begin
            $display("  PASS: identity PTE boot image");
            pass_cnt = pass_cnt + 1;
        end

        // --------------------------------------------------
        // Test 1: write then read back a single address
        // --------------------------------------------------
        $display("TEST 1: write and read back");
        begin : t1
            reg [7:0] rd;
            mem_write(8'hA0, 8'h55);
            mem_read(8'hA0, rd);
            if (rd === 8'h55) begin
                $display("  PASS: addr 0xA0 = 0x%02h", rd);
                pass_cnt = pass_cnt + 1;
            end else begin
                $display("  FAIL: addr 0xA0 got 0x%02h want 0x55", rd);
                fail_cnt = fail_cnt + 1;
            end
        end

        // --------------------------------------------------
        // Test 2: write multiple addresses and read them back
        // --------------------------------------------------
        $display("TEST 2: multiple addresses");
        begin : t2
            reg ok; reg [7:0] rd; ok = 1;
            mem_write(8'd0,   8'hAA);
            mem_write(8'd1,   8'hBB);
            mem_write(8'hFF,  8'hCC);
            mem_read(8'd0,  rd); if (rd !== 8'hAA) begin $display("  FAIL addr 0: 0x%02h",   rd); ok=0; end
            mem_read(8'd1,  rd); if (rd !== 8'hBB) begin $display("  FAIL addr 1: 0x%02h",   rd); ok=0; end
            mem_read(8'hFF, rd); if (rd !== 8'hCC) begin $display("  FAIL addr 255: 0x%02h", rd); ok=0; end
            if (ok) begin
                $display("  PASS: addr0=0xAA addr1=0xBB addr255=0xCC");
                pass_cnt = pass_cnt + 1;
            end else
                fail_cnt = fail_cnt + 1;
        end

        // --------------------------------------------------
        // Test 3: write to one address does not corrupt another
        // --------------------------------------------------
        $display("TEST 3: write isolation");
        begin : t3
            reg [7:0] rd;
            mem_write(8'd10, 8'h42);
            mem_read(8'd0, rd);
            if (rd === 8'hAA) begin
                $display("  PASS: addr 0 still 0x%02h after unrelated write", rd);
                pass_cnt = pass_cnt + 1;
            end else begin
                $display("  FAIL: addr 0 corrupted = 0x%02h", rd);
                fail_cnt = fail_cnt + 1;
            end
        end

        // --------------------------------------------------
        // Test 4: ready=0 when we=0, re=0
        // --------------------------------------------------
        $display("TEST 4: ready=0 when idle");
        @(negedge clk); we = 0; re = 0;
        @(posedge clk); #1;
        if (!ready) begin
            $display("  PASS: ready=0 when idle");
            pass_cnt = pass_cnt + 1;
        end else begin
            $display("  FAIL: ready should be 0 when idle");
            fail_cnt = fail_cnt + 1;
        end

        $display("\n%0d passed, %0d failed.", pass_cnt, fail_cnt);
        $finish;
    end

endmodule
