// =============================================================
//  l2_cache.v  —  4-way set-associative, write-back L2 cache
//  8 sets × 4 ways, 4-byte blocks, 8-bit address space
//  LRU replacement policy
//
//  Address breakdown (8-bit):
//    [7:5] tag    (3 bits)
//    [4:2] index  (3 bits  →  8 sets)
//    [1:0] offset (2 bits  →  4 bytes/block)
//
//  L1-side ports mirror L1's l2_* signal names so
//  cache_hierarchy.v can wire them together directly.
// =============================================================

module l2_cache (
    input  wire        clk,
    input  wire        rst,

    // --- L1 side (matches L1's l2_* ports) ---
    input  wire [7:0]  cpu_addr,
    input  wire [7:0]  cpu_wdata,
    input  wire        cpu_we,
    input  wire        cpu_re,
    output reg  [7:0]  cpu_rdata,
    output reg         cpu_ready,

    // --- Memory side ---
    output reg  [7:0]  mem_addr,
    output reg  [7:0]  mem_wdata,
    output reg         mem_we,
    output reg         mem_re,
    input  wire [7:0]  mem_rdata,
    input  wire        mem_ready
);

    // ----------------------------------------------------------
    // Cache storage: [set][way][byte_offset]
    // ----------------------------------------------------------
    reg [7:0] data  [0:7][0:3][0:3];
    reg [2:0] tag   [0:7][0:3];
    reg       valid [0:7][0:3];
    reg       dirty [0:7][0:3];
    reg [1:0] lru   [0:7][0:3];   // 0 = LRU, 3 = MRU

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
    reg [1:0] victim_way;

    // Latched request
    reg [7:0] req_addr;
    reg [7:0] req_wdata;
    reg       req_we;

    wire [2:0] req_tag    = req_addr[7:5];
    wire [2:0] req_index  = req_addr[4:2];
    wire [1:0] req_offset = req_addr[1:0];

    // ----------------------------------------------------------
    // Hit detection: 4-way parallel tag compare
    // ----------------------------------------------------------
    wire hit_w0 = valid[req_index][0] && (tag[req_index][0] == req_tag);
    wire hit_w1 = valid[req_index][1] && (tag[req_index][1] == req_tag);
    wire hit_w2 = valid[req_index][2] && (tag[req_index][2] == req_tag);
    wire hit_w3 = valid[req_index][3] && (tag[req_index][3] == req_tag);

    wire       hit     = hit_w0 | hit_w1 | hit_w2 | hit_w3;
    wire [1:0] hit_way = hit_w0 ? 2'd0 :
                         hit_w1 ? 2'd1 :
                         hit_w2 ? 2'd2 : 2'd3;

    // Way whose lru counter == 0 (least recently used)
    wire [1:0] lru_way = (lru[req_index][0] == 2'd0) ? 2'd0 :
                         (lru[req_index][1] == 2'd0) ? 2'd1 :
                         (lru[req_index][2] == 2'd0) ? 2'd2 : 2'd3;

    integer i, j, k;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state     <= IDLE;
            cpu_ready <= 0;
            mem_we    <= 0;
            mem_re    <= 0;
            byte_cnt  <= 0;
            for (i = 0; i < 8; i = i + 1) begin
                for (j = 0; j < 4; j = j + 1) begin
                    valid[i][j] <= 0;
                    dirty[i][j] <= 0;
                    tag[i][j]   <= 0;
                    lru[i][j]   <= j[1:0];   // way 0 = LRU, way 3 = MRU at reset
                    for (k = 0; k < 4; k = k + 1)
                        data[i][j][k] <= 0;
                end
            end
        end else begin
            mem_we    <= 0;
            mem_re    <= 0;
            cpu_ready <= 0;

            case (state)

                // ------------------------------------------------
                // IDLE: wait for a request from L1
                // ------------------------------------------------
                IDLE: begin
                    if (cpu_we || cpu_re) begin
                        req_addr  <= cpu_addr;
                        req_wdata <= cpu_wdata;
                        req_we    <= cpu_we;
                        state     <= HIT_CHECK;
                    end
                end

                // ------------------------------------------------
                // HIT_CHECK: 4-way tag compare, serve hit or route miss
                // ------------------------------------------------
                HIT_CHECK: begin
                    if (hit) begin
                        if (req_we) begin
                            data[req_index][hit_way][req_offset] <= req_wdata;
                            dirty[req_index][hit_way]            <= 1;
                        end else begin
                            cpu_rdata <= data[req_index][hit_way][req_offset];
                        end
                        // Promote hit_way to MRU; age down everything with higher rank
                        for (k = 0; k < 4; k = k + 1) begin
                            if (k != hit_way && lru[req_index][k] > lru[req_index][hit_way])
                                lru[req_index][k] <= lru[req_index][k] - 1;
                        end
                        lru[req_index][hit_way] <= 2'd3;
                        cpu_ready <= 1;
                        state     <= IDLE;
                    end else begin
                        // Miss: select LRU way as victim
                        victim_way <= lru_way;
                        byte_cnt   <= 0;
                        if (valid[req_index][lru_way] && dirty[req_index][lru_way])
                            state <= WRITEBACK;
                        else
                            state <= FILL;
                    end
                end

                // ------------------------------------------------
                // WRITEBACK: flush dirty victim block to memory
                // ------------------------------------------------
                WRITEBACK: begin
                    if (!mem_we && !mem_ready) begin
                        mem_addr  <= {tag[req_index][victim_way], req_index, byte_cnt};
                        mem_wdata <= data[req_index][victim_way][byte_cnt];
                        mem_we    <= 1;
                    end else if (mem_ready) begin
                        if (byte_cnt == 2'd3) begin
                            dirty[req_index][victim_way] <= 0;
                            byte_cnt                     <= 0;
                            state                        <= FILL;
                        end else begin
                            byte_cnt <= byte_cnt + 1;
                        end
                    end
                end

                // ------------------------------------------------
                // FILL: fetch new block from memory into victim slot
                // ------------------------------------------------
                FILL: begin
                    if (!mem_re && !mem_ready) begin
                        mem_addr <= {req_tag, req_index, byte_cnt};
                        mem_re   <= 1;
                    end else if (mem_ready) begin
                        data[req_index][victim_way][byte_cnt] <= mem_rdata;
                        if (byte_cnt == 2'd3) begin
                            tag[req_index][victim_way]   <= req_tag;
                            valid[req_index][victim_way] <= 1;
                            // Promote newly filled way to MRU
                            for (k = 0; k < 4; k = k + 1) begin
                                if (k != victim_way && lru[req_index][k] > lru[req_index][victim_way])
                                    lru[req_index][k] <= lru[req_index][k] - 1;
                            end
                            lru[req_index][victim_way] <= 2'd3;
                            byte_cnt <= 0;
                            state    <= DONE;
                        end else begin
                            byte_cnt <= byte_cnt + 1;
                        end
                    end
                end

                // ------------------------------------------------
                // DONE: service the original request on warm line
                // ------------------------------------------------
                DONE: begin
                    if (req_we) begin
                        data[req_index][victim_way][req_offset] <= req_wdata;
                        dirty[req_index][victim_way]            <= 1;
                    end else begin
                        cpu_rdata <= data[req_index][victim_way][req_offset];
                    end
                    cpu_ready <= 1;
                    state     <= IDLE;
                end

                default: state <= IDLE;

            endcase
        end
    end

endmodule
