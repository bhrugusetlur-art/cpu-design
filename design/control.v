// =============================================================
//  control.v  —  Instruction decoder (combinational)
//
//  Decodes instr[15:12] (opcode) into control signals.
//  Register addresses and immediate are wired directly from
//  instruction bits — no decoding needed.
//
//  wb_sel (write-back mux):
//    2'b00  WB_ALU  — ALU result   (ADD/SUB/AND/OR/NOT)
//    2'b01  WB_MEM  — cache rdata  (LOAD)
//    2'b10  WB_IMM  — immediate    (MOV Rd, #imm)
//    2'b11  WB_RS1  — rs1_data     (MOV Rd, Rs)
// =============================================================

module control (
    input  wire [15:0] instr,

    // Register addresses (direct slice — always valid)
    output wire [1:0]  rd_addr,    // instr[11:10]
    output wire [1:0]  rs1_addr,   // instr[9:8]
    output wire [7:0]  imm,        // instr[7:0]  (immediate or jump target)

    // Decoded control signals
    output reg  [2:0]  alu_op,
    output reg  [1:0]  wb_sel,
    output reg         reg_wr_en,
    output reg         mem_req,    // assert to cache (LOAD or STORE)
    output reg         mem_we,     // 1 = write (STORE), 0 = read (LOAD)
    output reg         jump,       // unconditional branch (JMP)
    output reg         branch,     // conditional branch (JZ)
    output reg         halt
);
    localparam MOV_RR  = 4'b0000;
    localparam MOV_IMM = 4'b0001;
    localparam OP_ADD  = 4'b0010;
    localparam OP_SUB  = 4'b0011;
    localparam OP_AND  = 4'b0100;
    localparam OP_OR   = 4'b0101;
    localparam OP_NOT  = 4'b0110;
    localparam LOAD    = 4'b0111;
    localparam STORE   = 4'b1000;
    localparam JMP     = 4'b1001;
    localparam JZ      = 4'b1010;
    localparam HALT    = 4'b1111;

    localparam WB_ALU  = 2'b00;
    localparam WB_MEM  = 2'b01;
    localparam WB_IMM  = 2'b10;
    localparam WB_RS1  = 2'b11;

    assign rd_addr  = instr[11:10];
    assign rs1_addr = instr[9:8];
    assign imm      = instr[7:0];

    always @(*) begin
        // safe no-op defaults
        alu_op    = 3'b000;
        wb_sel    = WB_ALU;
        reg_wr_en = 1'b0;
        mem_req   = 1'b0;
        mem_we    = 1'b0;
        jump      = 1'b0;
        branch    = 1'b0;
        halt      = 1'b0;

        case (instr[15:12])
            MOV_RR:  begin reg_wr_en = 1; wb_sel = WB_RS1;                     end
            MOV_IMM: begin reg_wr_en = 1; wb_sel = WB_IMM;                     end
            OP_ADD:  begin reg_wr_en = 1; wb_sel = WB_ALU; alu_op = 3'b010;   end
            OP_SUB:  begin reg_wr_en = 1; wb_sel = WB_ALU; alu_op = 3'b011;   end
            OP_AND:  begin reg_wr_en = 1; wb_sel = WB_ALU; alu_op = 3'b100;   end
            OP_OR:   begin reg_wr_en = 1; wb_sel = WB_ALU; alu_op = 3'b101;   end
            OP_NOT:  begin reg_wr_en = 1; wb_sel = WB_ALU; alu_op = 3'b110;   end
            LOAD:    begin reg_wr_en = 1; wb_sel = WB_MEM; mem_req = 1;        end
            STORE:   begin                                  mem_req = 1; mem_we = 1; end
            JMP:     begin jump   = 1;                                          end
            JZ:      begin branch = 1;                                          end
            HALT:    begin halt   = 1;                                          end
            default: ;
        endcase
    end

endmodule
