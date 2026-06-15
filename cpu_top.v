// =============================================================
//  cpu_top.v  —  Top-level: datapath + cache hierarchy + dmem
//
//  datapath ←→ cache_hierarchy ←→ dmem
//
//  Instruction memory (imem) lives inside datapath — Harvard
//  architecture means instruction and data paths are separate.
//  Only data memory goes through the cache hierarchy.
//
//  Stall handshake:
//    cache_req = dp_cpu_req && !req_pending
//      — forward the memory request for exactly one cycle per instruction
//    mem_stall  = dp_stall || cache_req
//      — hold the PC (and reg-write gate) during issue AND during miss
//    req_pending clears when dp_stall=0, sets once dp_stall goes high
//
//  Without this gating, the registered stall from L1 arrives one
//  cycle after the request is accepted, so the PC advances past the
//  very next instruction before that instruction can issue.
// =============================================================

module cpu_top #(
    parameter MEM_FILE = "program.mem"
) (
    input  wire clk,
    input  wire rst,
    output wire halt,
    output wire [7:0] pc_out
);

    // Datapath ↔ cache_hierarchy
    wire [7:0] dp_cpu_addr, dp_cpu_wdata, dp_cpu_rdata;
    wire       dp_cpu_we, dp_cpu_req;
    wire       dp_stall;   // stall signal OUT of cache_hierarchy

    // cache_hierarchy ↔ dmem
    wire [7:0] mem_addr, mem_wdata, mem_rdata;
    wire       mem_we, mem_re, mem_ready;

    // req_pending: asserted after a cache request is issued, held until
    // dp_stall drops.  Prevents the same LOAD/STORE from being re-issued
    // while L1 is processing it.
    reg req_pending;
    always @(posedge clk or posedge rst) begin
        if (rst)
            req_pending <= 1'b0;
        else if (!dp_stall)
            req_pending <= 1'b0;              // transaction complete, reset
        else if (dp_cpu_req && !req_pending)
            req_pending <= 1'b1;              // first stall cycle, lock in
    end

    wire cache_req = dp_cpu_req && !req_pending;

    // mem_stall: holds the PC and reg-file write-enable during issue (one
    // cycle before dp_stall appears) and throughout the miss.
    wire mem_stall = dp_stall || cache_req;

    datapath #(.MEM_FILE(MEM_FILE)) dp (
        .clk      (clk),
        .rst      (rst),
        .cpu_addr (dp_cpu_addr),
        .cpu_wdata(dp_cpu_wdata),
        .cpu_we   (dp_cpu_we),
        .cpu_req  (dp_cpu_req),
        .cpu_rdata(dp_cpu_rdata),
        .stall    (mem_stall),
        .halt     (halt),
        .pc_out   (pc_out)
    );

    cache_hierarchy cache (
        .clk      (clk),
        .rst      (rst),
        .cpu_addr (dp_cpu_addr),
        .cpu_wdata(dp_cpu_wdata),
        .cpu_we   (dp_cpu_we),
        .cpu_req  (cache_req),
        .cpu_rdata(dp_cpu_rdata),
        .stall    (dp_stall),
        .mem_addr (mem_addr),
        .mem_wdata(mem_wdata),
        .mem_we   (mem_we),
        .mem_re   (mem_re),
        .mem_rdata(mem_rdata),
        .mem_ready(mem_ready)
    );

    dmem dmem_inst (
        .clk  (clk),
        .addr (mem_addr),
        .wdata(mem_wdata),
        .we   (mem_we),
        .re   (mem_re),
        .rdata(mem_rdata),
        .ready(mem_ready)
    );

endmodule
