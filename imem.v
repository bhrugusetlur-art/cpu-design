// =============================================================
//  imem.v  —  Instruction ROM (Harvard architecture)
//  16-bit instructions, 256-word address space
//  Asynchronous read — instruction available same cycle as addr
//  Loaded at simulation start from MEM_FILE via $readmemh
// =============================================================

module imem #(
    parameter MEM_FILE = "program.mem"
) (
    input  wire [7:0]  addr,
    output wire [15:0] instr
);
    reg [15:0] mem [0:255];

    initial $readmemh(MEM_FILE, mem);

    assign instr = mem[addr];

endmodule
