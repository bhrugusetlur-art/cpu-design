// =============================================================
//  dmem.v  —  Synchronous data RAM
//  8-bit data, 256-byte address space
//  Write: combinational address capture, data written on posedge
//  Read:  1-cycle latency — rdata valid on posedge after re asserted
//  ready: pulses high for one cycle when operation completes
//  Interface matches L2 cache mem_* ports for direct wiring
// =============================================================

module dmem (
    input  wire        clk,
    input  wire [7:0]  addr,
    input  wire [7:0]  wdata,
    input  wire        we,
    input  wire        re,
    output reg  [7:0]  rdata,
    output reg         ready
);
    reg [7:0] mem [0:255];

    // Identity-mapped page table at 0xF0-0xFF (valid bit | PPN = VPN).
    // Set at FPGA configuration / simulation start, not on reset, so a
    // program can overwrite PTEs and the table survives CPU reset.
    integer init_i;
    initial begin
        for (init_i = 0; init_i < 16; init_i = init_i + 1)
            mem[8'hF0 + init_i] = 8'h80 | init_i[7:0];
    end

    always @(posedge clk) begin
        ready <= 1'b0;
        if (we) begin
            mem[addr] <= wdata;
            ready     <= 1'b1;
        end
        if (re) begin
            rdata <= mem[addr];
            ready <= 1'b1;
        end
    end

endmodule
