// =============================================================
//  mmu_tb.v  —  Testbench for mmu (+ tlb)
//  Run with:
//    iverilog -g2012 -o mmu_sim sim/mmu_tb.v design/mmu.v design/tlb.v && vvp mmu_sim
//
//  Drives the datapath side like the real CPU (request held until
//  stall drops) and models the cache side with a 2-cycle responder
//  that mimics L1's registered stall/rdata timing.
// =============================================================
`timescale 1ns/1ps

module mmu_tb;

    reg        clk, rst;

    // Datapath side
    reg  [7:0] cpu_addr, cpu_wdata;
    reg        cpu_we, cpu_req;
    wire [7:0] cpu_rdata;
    wire       stall;

    // Cache side
    wire [7:0] cache_addr, cache_wdata;
    wire       cache_we, cache_req;
    reg  [7:0] cache_rdata;
    reg        cache_stall;

    wire       page_fault;
    wire [7:0] fault_va;

    mmu dut (
        .clk(clk), .rst(rst),
        .cpu_addr(cpu_addr), .cpu_wdata(cpu_wdata), .cpu_we(cpu_we), .cpu_req(cpu_req),
        .cpu_rdata(cpu_rdata), .stall(stall),
        .cache_addr(cache_addr), .cache_wdata(cache_wdata),
        .cache_we(cache_we), .cache_req(cache_req),
        .cache_rdata(cache_rdata), .cache_stall(cache_stall),
        .page_fault(page_fault), .fault_va(fault_va)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    integer pass_cnt, fail_cnt;

    // ----------------------------------------------------------
    // Cache responder: capture request, stall two clocks, respond
    // ----------------------------------------------------------
    reg [7:0] page_table   [0:15];
    reg [7:0] physical_mem [0:255];

    reg [7:0] captured_addr, captured_wdata;
    reg       captured_we;
    reg       resp_busy;
    reg       resp_cnt;

    integer req_cnt;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            cache_stall <= 0;
            resp_busy   <= 0;
            resp_cnt    <= 0;
            req_cnt     <= 0;
        end else if (!resp_busy) begin
            if (cache_req) begin
                captured_addr  <= cache_addr;
                captured_wdata <= cache_wdata;
                captured_we    <= cache_we;
                cache_stall    <= 1;
                resp_busy      <= 1;
                resp_cnt       <= 0;
                req_cnt        <= req_cnt + 1;
            end
        end else begin
            resp_cnt <= resp_cnt + 1;
            if (resp_cnt) begin
                if (captured_we) begin
                    if (captured_addr >= 8'hF0)
                        page_table[captured_addr[3:0]] <= captured_wdata;
                    else
                        physical_mem[captured_addr] <= captured_wdata;
                end else begin
                    cache_rdata <= (captured_addr >= 8'hF0) ?
                                   page_table[captured_addr[3:0]] :
                                   physical_mem[captured_addr];
                end
                cache_stall <= 0;
                resp_busy   <= 0;
            end
        end
    end

    // ----------------------------------------------------------
    // Datapath-side driver: hold request until stall drops
    // ----------------------------------------------------------
    task cpu_access;
        input  [7:0] va;
        input        we_in;
        input  [7:0] wd;
        output [7:0] rd;
        begin
            @(negedge clk);
            cpu_addr = va; cpu_wdata = wd; cpu_we = we_in; cpu_req = 1;
            @(negedge clk);
            while (stall) @(negedge clk);
            rd = cpu_rdata;
            cpu_req = 0; cpu_we = 0;
        end
    endtask

    task check8;
        input [7:0]   got, want;
        input [151:0] name;
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

    integer i, base_cnt;
    reg [7:0] rd;

    initial begin
        $dumpfile("mmu.vcd");
        $dumpvars(0, mmu_tb);
        pass_cnt = 0; fail_cnt = 0;
        rst = 1; cpu_addr = 0; cpu_wdata = 0; cpu_we = 0; cpu_req = 0;
        cache_rdata = 0;

        for (i = 0; i < 16; i = i + 1)  page_table[i]   = 8'h00;
        for (i = 0; i < 256; i = i + 1) physical_mem[i] = 8'h00;
        page_table[2]  = 8'h83;   // VPN 2 → PPN 3, valid
        page_table[4]  = 8'h00;   // VPN 4 invalid
        page_table[15] = 8'h8F;   // VPN F → PPN F (page-table page itself)
        physical_mem[8'h31] = 8'h77;
        physical_mem[8'h32] = 8'h66;
        physical_mem[8'h51] = 8'h99;

        @(posedge clk); #1;
        rst = 0;

        // --------------------------------------------------
        // Test 1: cold LOAD VA 0x21 — walk PA 0xF2, replay PA 0x31
        // --------------------------------------------------
        $display("TEST 1: TLB-miss LOAD walks then replays");
        base_cnt = req_cnt;
        cpu_access(8'h21, 1'b0, 8'h00, rd);
        check8(rd, 8'h77, "LOAD VA 0x21 data");
        check8(req_cnt - base_cnt, 8'd2, "cache requests (walk+replay)");

        // --------------------------------------------------
        // Test 2: LOAD VA 0x22 — TLB hit, replay only
        // --------------------------------------------------
        $display("TEST 2: TLB-hit LOAD replays only");
        base_cnt = req_cnt;
        cpu_access(8'h22, 1'b0, 8'h00, rd);
        check8(rd, 8'h66, "LOAD VA 0x22 data");
        check8(req_cnt - base_cnt, 8'd1, "cache requests (replay only)");

        // --------------------------------------------------
        // Test 3: STORE VA 0xF2 rewrites PTE[2] and flushes the TLB
        // --------------------------------------------------
        $display("TEST 3: PTE STORE flushes TLB");
        base_cnt = req_cnt;
        cpu_access(8'hF2, 1'b1, 8'h85, rd);   // VPN 2 → PPN 5 now
        check8(req_cnt - base_cnt, 8'd2, "cache requests (walk+write)");
        check8(page_table[2], 8'h85, "PTE[2] rewritten");

        // --------------------------------------------------
        // Test 4: LOAD VA 0x21 walks again and uses the new PTE
        // --------------------------------------------------
        $display("TEST 4: post-flush LOAD re-walks with new mapping");
        base_cnt = req_cnt;
        cpu_access(8'h21, 1'b0, 8'h00, rd);
        check8(rd, 8'h99, "LOAD VA 0x21 remapped to PA 0x51");
        check8(req_cnt - base_cnt, 8'd2, "cache requests (walk+replay)");

        // --------------------------------------------------
        // Test 5: LOAD VA 0x40 — invalid PTE, permanent fault
        // --------------------------------------------------
        $display("TEST 5: invalid PTE faults and freezes");
        base_cnt = req_cnt;
        @(negedge clk);
        cpu_addr = 8'h40; cpu_we = 0; cpu_req = 1;   // held forever, CPU is stalled
        for (i = 0; i < 12; i = i + 1) @(negedge clk);
        check8({7'b0, page_fault}, 8'h01, "page_fault asserted");
        check8(fault_va, 8'h40, "fault_va latched");
        check8({7'b0, stall}, 8'h01, "stall held in fault");
        check8(req_cnt - base_cnt, 8'd1, "cache requests (walk only)");
        base_cnt = req_cnt;
        for (i = 0; i < 10; i = i + 1) @(negedge clk);
        check8(req_cnt - base_cnt, 8'd0, "no cache requests after fault");
        check8(fault_va, 8'h40, "fault_va stable");

        $display("\n%0d passed, %0d failed.", pass_cnt, fail_cnt);
        if (fail_cnt != 0) $fatal(1, "MMU regression failed");
        $finish;
    end

endmodule
