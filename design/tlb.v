// =============================================================
//  tlb.v  —  Translation lookaside buffer
//  4 fully associative VPN→PPN entries, combinational lookup,
//  round-robin fill, synchronous flush (clears valid bits only)
// =============================================================

module tlb (
    input  wire       clk, rst,
    input  wire [3:0] lookup_vpn,
    output wire       hit,
    output wire [3:0] hit_ppn,
    input  wire       fill,
    input  wire [3:0] fill_vpn, fill_ppn,
    input  wire       flush
);
    reg       valid [0:3];
    reg [3:0] vpn   [0:3];
    reg [3:0] ppn   [0:3];
    reg [1:0] replace_way;

    wire hit0 = valid[0] && vpn[0] == lookup_vpn;
    wire hit1 = valid[1] && vpn[1] == lookup_vpn;
    wire hit2 = valid[2] && vpn[2] == lookup_vpn;
    wire hit3 = valid[3] && vpn[3] == lookup_vpn;
    assign hit = hit0 | hit1 | hit2 | hit3;
    assign hit_ppn = hit0 ? ppn[0] : hit1 ? ppn[1] :
                     hit2 ? ppn[2] : hit3 ? ppn[3] : 4'h0;

    integer i;
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            for (i = 0; i < 4; i = i + 1)
                valid[i] <= 1'b0;
            replace_way <= 2'd0;
        end else if (flush) begin
            for (i = 0; i < 4; i = i + 1)
                valid[i] <= 1'b0;
        end else if (fill) begin
            valid[replace_way] <= 1'b1;
            vpn[replace_way]   <= fill_vpn;
            ppn[replace_way]   <= fill_ppn;
            replace_way        <= replace_way + 2'd1;
        end
    end

endmodule
