// =============================================================
//  cache_hierarchy_tb.v  —  Testbench for cache_hierarchy
//  Run with:
//    iverilog -g2012 -o hier_tb cache_hierarchy_tb.v \
//             cache_hierarchy.v l1_cache.v l2_cache.v && vvp hier_tb
// =============================================================
`timescale 1ns/1ps

module cache_hierarchy_tb;

    reg        clk, rst;
    reg  [7:0] cpu_addr, cpu_wdata;
    reg        cpu_we, cpu_req;
    wire [7:0] cpu_rdata;
    wire       stall;

    wire [7:0] mem_addr, mem_wdata;
    wire       mem_we, mem_re;
    reg  [7:0] mem_rdata;
    reg        mem_ready;

    cache_hierarchy dut (
        .clk(clk), .rst(rst),
        .cpu_addr(cpu_addr), .cpu_wdata(cpu_wdata),
        .cpu_we(cpu_we), .cpu_req(cpu_req),
        .cpu_rdata(cpu_rdata), .stall(stall),
        .mem_addr(mem_addr), .mem_wdata(mem_wdata),
        .mem_we(mem_we), .mem_re(mem_re),
        .mem_rdata(mem_rdata), .mem_ready(mem_ready)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    // Backing memory: 256 bytes, initialized as mem[i] = i
    reg [7:0] mem [0:255];
    integer k;

    initial begin
        for (k = 0; k < 256; k = k + 1)
            mem[k] = k[7:0];
        mem_rdata = 0;
        mem_ready = 0;
    end

    // Memory stub: responds 2 cycles after request
    always @(posedge clk) begin
        if (mem_re) begin
            @(posedge clk); @(posedge clk);
            mem_rdata <= mem[mem_addr];
            mem_ready <= 1;
            @(posedge clk);
            mem_ready <= 0;
        end
    end

    always @(posedge clk) begin
        if (mem_we) begin
            @(posedge clk); @(posedge clk);
            mem[mem_addr] <= mem_wdata;
            mem_ready <= 1;
            @(posedge clk);
            mem_ready <= 0;
        end
    end

    // Issue one CPU request; wait for stall to clear
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
            #1; cpu_req = 0;
            @(posedge clk);
            while (stall) @(posedge clk);
            #1;
        end
    endtask

    initial begin
        $dumpfile("cache_hierarchy.vcd");
        $dumpvars(0, cache_hierarchy_tb);

        rst = 1; cpu_req = 0; cpu_we = 0;
        cpu_addr = 0; cpu_wdata = 0;
        repeat(4) @(posedge clk);
        rst = 0;
        @(posedge clk);

        // --------------------------------------------------
        // Test 1: cold read — L1 miss → L2 miss → memory fetch
        // --------------------------------------------------
        $display("TEST 1: cold read addr=0x00 (L1 miss → L2 miss → memory)");
        cpu_request(8'h00, 8'h00, 0);
        if (cpu_rdata === mem[8'h00])
            $display("  PASS: rdata=0x%02h", cpu_rdata);
        else
            $display("  FAIL: expected 0x%02h got 0x%02h", mem[8'h00], cpu_rdata);

        // --------------------------------------------------
        // Test 2: L1 hit — re-read same address, no cache traffic below L1
        // --------------------------------------------------
        $display("TEST 2: L1 hit addr=0x00");
        cpu_request(8'h00, 8'h00, 0);
        if (cpu_rdata === 8'h00)
            $display("  PASS: rdata=0x%02h", cpu_rdata);
        else
            $display("  FAIL: expected 0x00 got 0x%02h", cpu_rdata);

        // --------------------------------------------------
        // Test 3: L2 hit after L1 eviction
        //   Write 0xAB to 0x00 → dirty in L1
        //   Read 0x20 (same L1 index=0, different tag) → L1 evicts 0x00
        //     dirty, writes block back to L2 → L2 now holds updated copy
        //   Re-read 0x00 → L1 misses again, L2 serves updated 0xAB
        // --------------------------------------------------
        $display("TEST 3: L2 hit after L1 dirty eviction");
        cpu_request(8'h00, 8'hAB, 1);   // write — L1 dirty
        cpu_request(8'h20, 8'h00, 0);   // evict 0x00 from L1, flush to L2
        cpu_request(8'h00, 8'h00, 0);   // re-read: L1 miss, L2 hit
        if (cpu_rdata === 8'hAB)
            $display("  PASS: rdata=0x%02h (L2 served updated value)", cpu_rdata);
        else
            $display("  FAIL: expected 0xAB got 0x%02h", cpu_rdata);

        // --------------------------------------------------
        // Test 4: L1 → L2 → memory dirty write-back chain
        //   Use set 1 (index=001, addrs 0x04/0x24/0x44/0x64/0x84) so
        //   L2 starts cold for this set and LRU is predictable.
        //
        //   Write 0xCD to 0x04  → L1 miss fill + write, L2 way 0 filled
        //   Read  0x24          → L1 evicts dirty 0x04 → L2 way 0 dirty
        //   Read  0x44          → fills L2 way 2
        //   Read  0x64          → fills L2 way 3  (all 4 ways now full)
        //                         LRU = way 0 (0x04, dirty 0xCD)
        //   Read  0x84          → L2 evicts way 0, writes 0xCD to memory
        // --------------------------------------------------
        $display("TEST 4: L1→L2→memory dirty write-back chain (set 1)");
        cpu_request(8'h04, 8'hCD, 1);
        cpu_request(8'h24, 8'h00, 0);
        cpu_request(8'h44, 8'h00, 0);
        cpu_request(8'h64, 8'h00, 0);
        cpu_request(8'h84, 8'h00, 0);
        repeat(4) @(posedge clk);
        if (mem[8'h04] === 8'hCD)
            $display("  PASS: dirty write-back correct, mem[0x04]=0x%02h", mem[8'h04]);
        else
            $display("  FAIL: expected mem[0x04]=0xCD, got 0x%02h", mem[8'h04]);

        $display("All tests done.");
        $finish;
    end

endmodule
