// =============================================================
//  cpu_top.v - Top-level: datapath + MMU + cache hierarchy + dmem
//  Data addresses from the datapath are virtual; the MMU owns the
//  cache request handshake and translates through its TLB.
// =============================================================

module cpu_top #(
    parameter MEM_FILE = "program.mem"
) (
    input  wire clk,
    input  wire rst,
    output wire halt,
    output wire [7:0] pc_out,

    output wire [7:0] debug_r0,
    output wire [7:0] debug_r1,
    output wire [7:0] debug_r2,
    output wire [7:0] debug_r3,
    output wire       debug_zero_flag,
    output wire [15:0] debug_instr,
    output wire [7:0] debug_cpu_addr,
    output wire       debug_cpu_req,
    output wire       debug_cpu_we,
    output wire       debug_stall,
    output wire       debug_page_fault,
    output wire [7:0] debug_fault_va
);

    wire [7:0] dp_cpu_addr, dp_cpu_wdata, dp_cpu_rdata;
    wire       dp_cpu_we, dp_cpu_req;
    wire       dp_stall;

    wire [7:0] mmu_addr, mmu_wdata, mmu_rdata;
    wire       mmu_we, mmu_req, mmu_stall;

    wire [7:0] mem_addr, mem_wdata, mem_rdata;
    wire       mem_we, mem_re, mem_ready;

    assign debug_cpu_addr = dp_cpu_addr;
    assign debug_cpu_req  = mmu_req;
    assign debug_cpu_we   = mmu_we;
    assign debug_stall    = mmu_stall;

    datapath #(.MEM_FILE(MEM_FILE)) dp (
        .clk      (clk),
        .rst      (rst),
        .cpu_addr (dp_cpu_addr),
        .cpu_wdata(dp_cpu_wdata),
        .cpu_we   (dp_cpu_we),
        .cpu_req  (dp_cpu_req),
        .cpu_rdata(dp_cpu_rdata),
        .stall    (mmu_stall),
        .halt     (halt),
        .pc_out   (pc_out),
        .debug_r0 (debug_r0),
        .debug_r1 (debug_r1),
        .debug_r2 (debug_r2),
        .debug_r3 (debug_r3),
        .debug_zero_flag(debug_zero_flag),
        .debug_instr(debug_instr)
    );

    mmu vm (
        .clk       (clk),
        .rst       (rst),
        .cpu_addr  (dp_cpu_addr),
        .cpu_wdata (dp_cpu_wdata),
        .cpu_we    (dp_cpu_we),
        .cpu_req   (dp_cpu_req),
        .cpu_rdata (dp_cpu_rdata),
        .stall     (mmu_stall),
        .cache_addr (mmu_addr),
        .cache_wdata(mmu_wdata),
        .cache_we   (mmu_we),
        .cache_req  (mmu_req),
        .cache_rdata(mmu_rdata),
        .cache_stall(dp_stall),
        .page_fault(debug_page_fault),
        .fault_va  (debug_fault_va)
    );

    cache_hierarchy cache (
        .clk      (clk),
        .rst      (rst),
        .cpu_addr (mmu_addr),
        .cpu_wdata(mmu_wdata),
        .cpu_we   (mmu_we),
        .cpu_req  (mmu_req),
        .cpu_rdata(mmu_rdata),
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
