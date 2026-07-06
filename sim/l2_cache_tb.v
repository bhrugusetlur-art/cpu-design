// =============================================================
//  l2_cache_tb.v  —  Testbench for l2_cache
//  Run with:
//    iverilog -g2012 -o l2_tb sim/l2_cache_tb.v design/l2_cache.v && vvp l2_tb
// =============================================================
`timescale 1ns/1ps

module l2_cache_tb;

    reg        clk, rst;
    reg  [7:0] cpu_addr, cpu_wdata;
    reg        cpu_we, cpu_re;
    wire [7:0] cpu_rdata;
    wire       cpu_ready;

    wire [7:0] mem_addr, mem_wdata;
    wire       mem_we, mem_re;
    reg  [7:0] mem_rdata;
    reg        mem_ready;

    l2_cache dut (
        .clk(clk), .rst(rst),
        .cpu_addr(cpu_addr), .cpu_wdata(cpu_wdata),
        .cpu_we(cpu_we), .cpu_re(cpu_re),
        .cpu_rdata(cpu_rdata), .cpu_ready(cpu_ready),
        .mem_addr(mem_addr), .mem_wdata(mem_wdata),
        .mem_we(mem_we), .mem_re(mem_re),
        .mem_rdata(mem_rdata), .mem_ready(mem_ready)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    // Backing memory: 256 bytes, initialized as mem_store[i] = i
    reg [7:0] mem_store [0:255];
    integer k;

    initial begin
        for (k = 0; k < 256; k = k + 1)
            mem_store[k] = k[7:0];
        mem_rdata = 0;
        mem_ready = 0;
    end

    // Memory stub: responds 2 cycles after request
    always @(posedge clk) begin
        if (mem_re) begin
            @(posedge clk); @(posedge clk);
            mem_rdata <= mem_store[mem_addr];
            mem_ready <= 1;
            @(posedge clk);
            mem_ready <= 0;
        end
    end

    always @(posedge clk) begin
        if (mem_we) begin
            @(posedge clk); @(posedge clk);
            mem_store[mem_addr] <= mem_wdata;
            mem_ready <= 1;
            @(posedge clk);
            mem_ready <= 0;
        end
    end

    // Issue a single-byte read and wait for cpu_ready
    task l2_read;
        input [7:0] addr;
        begin
            @(negedge clk);
            cpu_addr = addr;
            cpu_re   = 1;
            cpu_we   = 0;
            @(posedge clk);
            #1; cpu_re = 0;
            while (!cpu_ready) @(posedge clk);
            #1;
        end
    endtask

    // Issue a single-byte write and wait for cpu_ready
    task l2_write;
        input [7:0] addr;
        input [7:0] wdata;
        begin
            @(negedge clk);
            cpu_addr  = addr;
            cpu_wdata = wdata;
            cpu_we    = 1;
            cpu_re    = 0;
            @(posedge clk);
            #1; cpu_we = 0;
            while (!cpu_ready) @(posedge clk);
            #1;
        end
    endtask

    initial begin
        $dumpfile("l2_cache.vcd");
        $dumpvars(0, l2_cache_tb);

        rst = 1; cpu_re = 0; cpu_we = 0;
        cpu_addr = 0; cpu_wdata = 0;
        repeat(4) @(posedge clk);
        rst = 0;
        @(posedge clk);

        // --------------------------------------------------
        // Test 1: cold read — compulsory miss, fetch from memory
        // --------------------------------------------------
        $display("TEST 1: cold read addr=0x00");
        l2_read(8'h00);
        if (cpu_rdata === mem_store[8'h00])
            $display("  PASS: rdata=0x%02h", cpu_rdata);
        else
            $display("  FAIL: expected 0x%02h got 0x%02h", mem_store[8'h00], cpu_rdata);

        // --------------------------------------------------
        // Test 2: hit — re-read same address, no memory traffic
        // --------------------------------------------------
        $display("TEST 2: read hit addr=0x00");
        l2_read(8'h00);
        if (cpu_rdata === 8'h00)
            $display("  PASS: rdata=0x%02h", cpu_rdata);
        else
            $display("  FAIL: expected 0x00 got 0x%02h", cpu_rdata);

        // --------------------------------------------------
        // Test 3: write hit then read back
        // --------------------------------------------------
        $display("TEST 3: write 0xAB to addr=0x00, read back");
        l2_write(8'h00, 8'hAB);
        l2_read(8'h00);
        if (cpu_rdata === 8'hAB)
            $display("  PASS: rdata=0x%02h", cpu_rdata);
        else
            $display("  FAIL: expected 0xAB got 0x%02h", cpu_rdata);

        // --------------------------------------------------
        // Test 4: LRU eviction with dirty write-back
        //   All 5 addresses share set 0 (index = 000):
        //     tag 0: 0x00 (already in way 0, dirty with 0xAB at byte 0)
        //     tag 1: 0x20  →  fills way 1
        //     tag 2: 0x40  →  fills way 2
        //     tag 3: 0x60  →  fills way 3
        //   After the four fills, way 0 is LRU.
        //   tag 4: 0x80  →  cold miss, must evict way 0 (LRU, dirty)
        //   Verify mem_store[0x00] == 0xAB after write-back.
        // --------------------------------------------------
        $display("TEST 4: LRU eviction — fill 4 ways, access 5th conflicts, writeback LRU");
        l2_read(8'h20);
        l2_read(8'h40);
        l2_read(8'h60);
        // All 4 ways of set 0 filled; way 0 (tag 0, dirty 0xAB) is now LRU.
        l2_read(8'h80);
        // l2_read returns after fill of 0x80 is done, so writeback of way 0 is complete.
        if (mem_store[8'h00] === 8'hAB)
            $display("  PASS: dirty write-back correct, mem[0x00]=0x%02h", mem_store[8'h00]);
        else
            $display("  FAIL: expected mem[0x00]=0xAB, got 0x%02h", mem_store[8'h00]);

        $display("All tests done.");
        $finish;
    end

endmodule
