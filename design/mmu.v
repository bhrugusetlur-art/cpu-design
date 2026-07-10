// =============================================================
//  mmu.v  —  Memory management unit
//  Translates virtual data addresses (VA[7:4] = VPN, VA[3:0] =
//  offset) through a 4-entry TLB. On a miss, walks the one-byte
//  PTE at physical 0xF0+VPN through the cache hierarchy, fills
//  the TLB, and replays the captured request at {PPN, offset}.
//  An invalid PTE (bit 7 clear) latches the faulting VA and
//  freezes the CPU until reset. A completed STORE whose physical
//  address lands in the page table (0xF0-0xFF) flushes the TLB.
//
//  Owns the single-cycle request pulse toward L1 (which latches
//  the request and raises registered stall), replacing cpu_top's
//  old req_pending logic.
// =============================================================

module mmu (
    input  wire       clk, rst,

    // --- Datapath side (virtual) ---
    input  wire [7:0] cpu_addr, cpu_wdata,
    input  wire       cpu_we, cpu_req,
    output wire [7:0] cpu_rdata,
    output reg        stall,

    // --- Cache side (physical) ---
    output reg  [7:0] cache_addr, cache_wdata,
    output reg        cache_we, cache_req,
    input  wire [7:0] cache_rdata,
    input  wire       cache_stall,

    // --- Fault reporting ---
    output reg        page_fault,
    output reg  [7:0] fault_va
);

    localparam IDLE = 3'd0, WALK_ISSUE = 3'd1, WALK_WAIT = 3'd2,
               ACCESS_ISSUE = 3'd3, ACCESS_WAIT = 3'd4, FAULT = 3'd5;

    reg [2:0] state;
    reg [7:0] saved_va, saved_wdata, saved_pa;
    reg       saved_we;

    wire       tlb_hit;
    wire [3:0] tlb_ppn;

    wire walk_done   = (state == WALK_WAIT)   && !cache_stall;
    wire access_done = (state == ACCESS_WAIT) && !cache_stall;

    wire tlb_fill  = walk_done && cache_rdata[7];
    wire tlb_flush = access_done && saved_we && (saved_pa[7:4] == 4'hF);

    tlb tlb_inst (
        .clk(clk), .rst(rst),
        .lookup_vpn(cpu_addr[7:4]), .hit(tlb_hit), .hit_ppn(tlb_ppn),
        .fill(tlb_fill), .fill_vpn(saved_va[7:4]), .fill_ppn(cache_rdata[3:0]),
        .flush(tlb_flush)
    );

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state      <= IDLE;
            page_fault <= 1'b0;
            fault_va   <= 8'h00;
            saved_va   <= 8'h00;
            saved_wdata<= 8'h00;
            saved_pa   <= 8'h00;
            saved_we   <= 1'b0;
        end else begin
            case (state)
                IDLE: if (cpu_req) begin
                    saved_va    <= cpu_addr;
                    saved_wdata <= cpu_wdata;
                    saved_we    <= cpu_we;
                    if (tlb_hit) begin
                        saved_pa <= {tlb_ppn, cpu_addr[3:0]};
                        state    <= ACCESS_ISSUE;
                    end else
                        state <= WALK_ISSUE;
                end

                WALK_ISSUE: state <= WALK_WAIT;

                WALK_WAIT: if (!cache_stall) begin
                    if (cache_rdata[7]) begin
                        saved_pa <= {cache_rdata[3:0], saved_va[3:0]};
                        state    <= ACCESS_ISSUE;
                    end else begin
                        fault_va   <= saved_va;
                        page_fault <= 1'b1;
                        state      <= FAULT;
                    end
                end

                ACCESS_ISSUE: state <= ACCESS_WAIT;

                ACCESS_WAIT: if (!cache_stall) state <= IDLE;

                FAULT: ;  // frozen until reset

                default: state <= IDLE;
            endcase
        end
    end

    // Single-cycle request pulses; L1 latches addr/wdata/we with them
    always @(*) begin
        cache_req   = 1'b0;
        cache_we    = 1'b0;
        cache_addr  = 8'h00;
        cache_wdata = 8'h00;
        case (state)
            WALK_ISSUE: begin
                cache_req  = 1'b1;
                cache_addr = {4'hF, saved_va[7:4]};
            end
            ACCESS_ISSUE: begin
                cache_req   = 1'b1;
                cache_we    = saved_we;
                cache_addr  = saved_pa;
                cache_wdata = saved_wdata;
            end
        endcase
    end

    // Datapath stalls from the request cycle until the translated
    // access completes; a walk response must never look like a LOAD
    always @(*) begin
        case (state)
            IDLE:        stall = cpu_req;
            ACCESS_WAIT: stall = cache_stall;
            default:     stall = 1'b1;
        endcase
    end

    assign cpu_rdata = cache_rdata;

endmodule
