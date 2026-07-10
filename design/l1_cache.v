// =============================================================
//  l1_cache.v  —  Direct-mapped, write-back L1 cache
//  8 lines, 4-byte blocks, 8-bit address space
//
//  Address breakdown (8-bit):
//    [7:5] tag    (3 bits)
//    [4:2] index  (3 bits  →  8 lines)
//    [1:0] offset (2 bits  →  4 bytes/block)
// =============================================================

module l1_cache (
    input  wire        clk,
    input  wire        rst,

    // --- CPU side ---
    input  wire [7:0]  cpu_addr,
    input  wire [7:0]  cpu_wdata,
    input  wire        cpu_we,
    input  wire        cpu_req,
    output reg  [7:0]  cpu_rdata,
    output reg         stall,

    // --- L2 side ---
    output reg  [7:0]  l2_addr,
    output reg  [7:0]  l2_wdata,
    output reg         l2_we,
    output reg         l2_re,
    input  wire [7:0]  l2_rdata,
    input  wire        l2_ready
);

    // ----------------------------------------------------------
    // Cache storage
    // ----------------------------------------------------------
    reg [7:0] data  [0:7][0:3];
    reg [2:0] tag   [0:7];
    reg       valid [0:7];
    reg       dirty [0:7];

    // ----------------------------------------------------------
    // Address decomposition
    // ----------------------------------------------------------
    wire [2:0] addr_tag    = cpu_addr[7:5];
    wire [2:0] addr_index  = cpu_addr[4:2];
    wire [1:0] addr_offset = cpu_addr[1:0];

    wire hit = valid[addr_index] && (tag[addr_index] == addr_tag);

    // ----------------------------------------------------------
    // State machine
    // ----------------------------------------------------------
    localparam IDLE      = 3'd0;
    localparam HIT_CHECK = 3'd1;
    localparam WRITEBACK = 3'd2;
    localparam FILL      = 3'd3;
    localparam DONE      = 3'd4;

    reg [2:0] state;
    reg [1:0] byte_cnt;
    reg       l2_pend;   // one L2 request outstanding; wait for l2_ready

    // Latched request
    reg [7:0] req_addr;
    reg [7:0] req_wdata;
    reg       req_we;

    wire [2:0] req_tag    = req_addr[7:5];
    wire [2:0] req_index  = req_addr[4:2];
    wire [1:0] req_offset = req_addr[1:0];

    integer i, j;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state    <= IDLE;
            stall    <= 0;
            l2_we    <= 0;
            l2_re    <= 0;
            byte_cnt <= 0;
            l2_pend  <= 0;
            for (i = 0; i < 8; i = i + 1) begin
                valid[i] <= 0;
                dirty[i] <= 0;
                tag[i]   <= 0;
                for (j = 0; j < 4; j = j + 1)
                    data[i][j] <= 0;
            end
        end else begin
            l2_we <= 0;
            l2_re <= 0;

            case (state)

                // ------------------------------------------------
                // IDLE: wait for a CPU request
                // ------------------------------------------------
                IDLE: begin
                    if (cpu_req) begin
                        req_addr  <= cpu_addr;
                        req_wdata <= cpu_wdata;
                        req_we    <= cpu_we;
                        stall     <= 1;
                        state     <= HIT_CHECK;
                    end
                end

                // ------------------------------------------------
                // HIT_CHECK: tag comparison, serve hit or route miss
                // ------------------------------------------------
                HIT_CHECK: begin
                    if (valid[req_index] && (tag[req_index] == req_tag)) begin
                        // HIT
                        if (req_we) begin
                            data[req_index][req_offset] <= req_wdata;
                            dirty[req_index]            <= 1;
                        end else begin
                            cpu_rdata <= data[req_index][req_offset];
                        end
                        stall <= 0;
                        state <= IDLE;
                    end else begin
                        // MISS — flush dirty line first if needed
                        byte_cnt <= 0;
                        if (dirty[req_index] && valid[req_index])
                            state <= WRITEBACK;
                        else
                            state <= FILL;
                    end
                end

                // ------------------------------------------------
                // WRITEBACK: send each byte of the dirty line to L2
                // ------------------------------------------------
                WRITEBACK: begin
                    if (!l2_pend) begin
                        // Issue write for current byte
                        l2_addr  <= {tag[req_index], req_index, byte_cnt};
                        l2_wdata <= data[req_index][byte_cnt];
                        l2_we    <= 1;
                        l2_pend  <= 1;
                    end else if (l2_ready) begin
                        l2_pend <= 0;
                        if (byte_cnt == 2'd3) begin
                            dirty[req_index] <= 0;
                            byte_cnt         <= 0;
                            state            <= FILL;
                        end else begin
                            byte_cnt <= byte_cnt + 1;
                        end
                    end
                end

                // ------------------------------------------------
                // FILL: fetch 4 bytes from L2 into this cache line
                // ------------------------------------------------
                FILL: begin
                    if (!l2_pend) begin
                        l2_addr <= {req_tag, req_index, byte_cnt};
                        l2_re   <= 1;
                        l2_pend <= 1;
                    end else if (l2_ready) begin
                        l2_pend <= 0;
                        data[req_index][byte_cnt] <= l2_rdata;
                        if (byte_cnt == 2'd3) begin
                            tag[req_index]   <= req_tag;
                            valid[req_index] <= 1;
                            byte_cnt         <= 0;
                            state            <= DONE;
                        end else begin
                            byte_cnt <= byte_cnt + 1;
                        end
                    end
                end

                // ------------------------------------------------
                // DONE: service the original request on the warm line
                // ------------------------------------------------
                DONE: begin
                    if (req_we) begin
                        data[req_index][req_offset] <= req_wdata;
                        dirty[req_index]            <= 1;
                    end else begin
                        cpu_rdata <= data[req_index][req_offset];
                    end
                    stall <= 0;
                    state <= IDLE;
                end

                default: state <= IDLE;

            endcase
        end
    end

endmodule