// =============================================================
//  cpu_top.v - Top-level: datapath + cache hierarchy + dmem
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
    output wire       debug_stall
);

    wire [7:0] dp_cpu_addr, dp_cpu_wdata, dp_cpu_rdata;
    wire       dp_cpu_we, dp_cpu_req;
    wire       dp_stall;

    wire [7:0] mem_addr, mem_wdata, mem_rdata;
    wire       mem_we, mem_re, mem_ready;

    reg req_pending;
    always @(posedge clk or posedge rst) begin
        if (rst)
            req_pending <= 1'b0;
        else if (!dp_stall)
            req_pending <= 1'b0;
        else if (dp_cpu_req && !req_pending)
            req_pending <= 1'b1;
    end

    wire cache_req = dp_cpu_req && !req_pending;
    wire mem_stall = dp_stall || cache_req;

    assign debug_cpu_addr = dp_cpu_addr;
    assign debug_cpu_req  = cache_req;
    assign debug_cpu_we   = dp_cpu_we;
    assign debug_stall    = mem_stall;

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
        .pc_out   (pc_out),
        .debug_r0 (debug_r0),
        .debug_r1 (debug_r1),
        .debug_r2 (debug_r2),
        .debug_r3 (debug_r3),
        .debug_zero_flag(debug_zero_flag),
        .debug_instr(debug_instr)
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
