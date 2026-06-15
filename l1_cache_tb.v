// =============================================================
//  l1_cache_tb.v  —  Testbench for l1_cache
//  Run with:
//    iverilog -g2012 -o l1_tb l1_cache_tb.v l1_cache.v && vvp l1_tb
// =============================================================
`timescale 1ns/1ps

module l1_cache_tb;

    reg        clk, rst;
    reg  [7:0] cpu_addr, cpu_wdata;
    reg        cpu_we, cpu_req;
    wire [7:0] cpu_rdata;
    wire       stall;

    wire [7:0] l2_addr, l2_wdata;
    wire       l2_we, l2_re;
    reg  [7:0] l2_rdata;
    reg        l2_ready;

    l1_cache dut (
        .clk(clk), .rst(rst),
        .cpu_addr(cpu_addr), .cpu_wdata(cpu_wdata),
        .cpu_we(cpu_we), .cpu_req(cpu_req),
        .cpu_rdata(cpu_rdata), .stall(stall),
        .l2_addr(l2_addr), .l2_wdata(l2_wdata),
        .l2_we(l2_we), .l2_re(l2_re),
        .l2_rdata(l2_rdata), .l2_ready(l2_ready)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    // Stub L2: 256 bytes, responds 2 cycles after request
    reg [7:0] l2_mem [0:255];
    integer k;

    initial begin
        for (k = 0; k < 256; k = k + 1)
            l2_mem[k] = k[7:0];
        l2_rdata = 0;
        l2_ready = 0;
    end

    // L2 response handler
    always @(posedge clk) begin
        if (l2_re) begin
            @(posedge clk); @(posedge clk);
            l2_rdata <= l2_mem[l2_addr];
            l2_ready <= 1;
            @(posedge clk);
            l2_ready <= 0;
        end
    end

    always @(posedge clk) begin
        if (l2_we) begin
            @(posedge clk); @(posedge clk);
            l2_mem[l2_addr] <= l2_wdata;
            l2_ready <= 1;
            @(posedge clk);
            l2_ready <= 0;
        end
    end

    // Issue one request and wait for stall to clear
    task cpu_request;
        input [7:0] addr;
        input [7:0] wdata;
        input       we;
        begin
            @(negedge clk);
            cpu_addr  = addr;
            cpu_wdata = wdata;
            cpu_we    = we;
            cpu_req   = 1;
            @(posedge clk);
            #1 cpu_req = 0;
            @(posedge clk);
            while (stall) @(posedge clk);
            #1; // settle
        end
    endtask

    initial begin
        $dumpfile("l1_cache.vcd");
        $dumpvars(0, l1_cache_tb);

        rst = 1; cpu_req = 0; cpu_we = 0;
        cpu_addr = 0; cpu_wdata = 0;
        repeat(4) @(posedge clk);
        rst = 0;
        @(posedge clk);

        // Test 1: cold read — compulsory miss, fetches from L2
        $display("TEST 1: cold read addr=0x00");
        cpu_request(8'h00, 8'h00, 0);
        if (cpu_rdata === l2_mem[8'h00])
            $display("  PASS: rdata=0x%02h", cpu_rdata);
        else
            $display("  FAIL: expected 0x%02h got 0x%02h", l2_mem[8'h00], cpu_rdata);

        // Test 2: same address — should hit, no L2 traffic
        $display("TEST 2: repeat read (should hit)");
        cpu_request(8'h00, 8'h00, 0);
        if (cpu_rdata === 8'h00)
            $display("  PASS: rdata=0x%02h", cpu_rdata);
        else
            $display("  FAIL: expected 0x00 got 0x%02h", cpu_rdata);

        // Test 3: write hit then read back
        $display("TEST 3: write to cached line addr=0x00, data=0xAB");
        cpu_request(8'h00, 8'hAB, 1);
        cpu_request(8'h00, 8'h00, 0);
        if (cpu_rdata === 8'hAB)
            $display("  PASS: rdata=0x%02h", cpu_rdata);
        else
            $display("  FAIL: expected 0xAB got 0x%02h", cpu_rdata);

        // Test 4: conflict miss — addr 0x20 maps to same index 0, different tag
        // forces writeback of dirty 0x00 line before filling new line
        $display("TEST 4: eviction — addr=0x20 (same index, different tag)");
        cpu_request(8'h20, 8'h00, 0);
        repeat(4) @(posedge clk); // let writeback complete to l2_mem
        if (l2_mem[8'h00] === 8'hAB)
            $display("  PASS: writeback correct, l2_mem[0]=0x%02h", l2_mem[8'h00]);
        else
            $display("  FAIL: expected l2_mem[0]=0xAB, got 0x%02h", l2_mem[8'h00]);

        $display("All tests done.");
        $finish;
    end

endmodule