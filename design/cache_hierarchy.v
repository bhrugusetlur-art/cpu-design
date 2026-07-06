// =============================================================
//  cache_hierarchy.v  —  Wires L1 cache → L2 cache → data memory
//
//  CPU-side interface matches l1_cache's cpu_* / stall ports.
//  Memory-side interface matches l2_cache's mem_* ports.
//  Stall propagation is handled entirely by l1_cache.
// =============================================================

module cache_hierarchy (
    input  wire        clk,
    input  wire        rst,

    // --- CPU side ---
    input  wire [7:0]  cpu_addr,
    input  wire [7:0]  cpu_wdata,
    input  wire        cpu_we,
    input  wire        cpu_req,
    output wire [7:0]  cpu_rdata,
    output wire        stall,

    // --- Memory side (connect to dmem) ---
    output wire [7:0]  mem_addr,
    output wire [7:0]  mem_wdata,
    output wire        mem_we,
    output wire        mem_re,
    input  wire [7:0]  mem_rdata,
    input  wire        mem_ready
);

    // L1-to-L2 interconnect
    wire [7:0] l1l2_addr;
    wire [7:0] l1l2_wdata;
    wire       l1l2_we;
    wire       l1l2_re;
    wire [7:0] l2l1_rdata;
    wire       l2l1_ready;

    l1_cache l1 (
        .clk      (clk),
        .rst      (rst),
        .cpu_addr (cpu_addr),
        .cpu_wdata(cpu_wdata),
        .cpu_we   (cpu_we),
        .cpu_req  (cpu_req),
        .cpu_rdata(cpu_rdata),
        .stall    (stall),
        .l2_addr  (l1l2_addr),
        .l2_wdata (l1l2_wdata),
        .l2_we    (l1l2_we),
        .l2_re    (l1l2_re),
        .l2_rdata (l2l1_rdata),
        .l2_ready (l2l1_ready)
    );

    l2_cache l2 (
        .clk      (clk),
        .rst      (rst),
        .cpu_addr (l1l2_addr),
        .cpu_wdata(l1l2_wdata),
        .cpu_we   (l1l2_we),
        .cpu_re   (l1l2_re),
        .cpu_rdata(l2l1_rdata),
        .cpu_ready(l2l1_ready),
        .mem_addr (mem_addr),
        .mem_wdata(mem_wdata),
        .mem_we   (mem_we),
        .mem_re   (mem_re),
        .mem_rdata(mem_rdata),
        .mem_ready(mem_ready)
    );

endmodule
