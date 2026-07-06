// ================================================================
//  basys3_top.v - Basys3 FPGA wrapper for cpu_top
//
//  sw[1:0] speed:
//    00 = 1 Hz
//    01 = 2 Hz
//    10 = 4 Hz
//    11 = single-step with btnR
//
//  sw[3:2] LED[7:0] register select:
//    00 = R0
//    01 = R1
//    10 = R2
//    11 = R3
// ================================================================

module basys3_top (
    input  wire        clk100,
    input  wire        btnC,
    input  wire        btnR,
    input  wire [3:0]  sw,
    output wire [15:0] led,
    output wire [6:0]  seg,
    output wire [3:0]  an
);

reg [1:0] rst_meta = 2'b00;
always @(posedge clk100) rst_meta <= {rst_meta[0], btnC};

reg [19:0] dbnc_cnt = 20'd999_999;
reg        rst      = 1'b1;

always @(posedge clk100) begin
    if (rst_meta[1]) begin
        dbnc_cnt <= 20'd999_999;
        rst      <= 1'b1;
    end else if (dbnc_cnt != 0) begin
        dbnc_cnt <= dbnc_cnt - 1;
    end else begin
        rst <= 1'b0;
    end
end

reg [1:0] btn_meta = 2'b00;
always @(posedge clk100) btn_meta <= {btn_meta[0], btnR};

reg  btn_prev = 1'b0;
wire step_pulse = btn_meta[1] && !btn_prev;
always @(posedge clk100) btn_prev <= btn_meta[1];

wire [25:0] half_period =
    (sw[1:0] == 2'b00) ? 26'd49_999_999 :
    (sw[1:0] == 2'b01) ? 26'd24_999_999 :
                         26'd12_499_999;

reg [25:0] clk_cnt   = 26'd0;
reg        cpu_clk_r = 1'b0;

always @(posedge clk100 or posedge rst) begin
    if (rst) begin
        clk_cnt   <= 0;
        cpu_clk_r <= 0;
    end else if (sw[1:0] == 2'b11) begin
        clk_cnt   <= 0;
        cpu_clk_r <= step_pulse;
    end else begin
        if (clk_cnt >= half_period) begin
            clk_cnt   <= 0;
            cpu_clk_r <= ~cpu_clk_r;
        end else begin
            clk_cnt <= clk_cnt + 1;
        end
    end
end

wire cpu_clk = cpu_clk_r;

wire [7:0] pc_out;
wire       halt;
wire [7:0] debug_r0, debug_r1, debug_r2, debug_r3;

cpu_top #(.MEM_FILE("program.mem")) core (
    .clk      (cpu_clk),
    .rst      (rst),
    .halt     (halt),
    .pc_out   (pc_out),
    .debug_r0 (debug_r0),
    .debug_r1 (debug_r1),
    .debug_r2 (debug_r2),
    .debug_r3 (debug_r3)
);

reg [7:0] led_reg_value;
always @(*) begin
    case (sw[3:2])
        2'b00:   led_reg_value = debug_r0;
        2'b01:   led_reg_value = debug_r1;
        2'b10:   led_reg_value = debug_r2;
        default: led_reg_value = debug_r3;
    endcase
end

assign led = {6'b0, cpu_clk, halt, led_reg_value};

reg [14:0] seg_cnt = 15'd0;
reg [1:0]  dig_sel = 2'd0;

always @(posedge clk100 or posedge rst) begin
    if (rst) begin
        seg_cnt <= 0;
        dig_sel <= 0;
    end else begin
        if (seg_cnt == 15'd24_999) begin
            seg_cnt <= 0;
            dig_sel <= dig_sel + 1;
        end else begin
            seg_cnt <= seg_cnt + 1;
        end
    end
end

function [6:0] hex_seg;
    input [3:0] d;
    case (d)
        4'h0: hex_seg = 7'b1000000;
        4'h1: hex_seg = 7'b1111001;
        4'h2: hex_seg = 7'b0100100;
        4'h3: hex_seg = 7'b0110000;
        4'h4: hex_seg = 7'b0011001;
        4'h5: hex_seg = 7'b0010010;
        4'h6: hex_seg = 7'b0000010;
        4'h7: hex_seg = 7'b1111000;
        4'h8: hex_seg = 7'b0000000;
        4'h9: hex_seg = 7'b0010000;
        4'hA: hex_seg = 7'b0001000;
        4'hB: hex_seg = 7'b0000011;
        4'hC: hex_seg = 7'b1000110;
        4'hD: hex_seg = 7'b0100001;
        4'hE: hex_seg = 7'b0000110;
        default: hex_seg = 7'b0001110;
    endcase
endfunction

localparam SEG_H   = 7'b0001001;
localparam SEG_BLK = 7'b1111111;

reg [6:0] seg_r = SEG_BLK;
reg [3:0] an_r  = 4'b1111;

always @(*) begin
    case (dig_sel)
        2'b00: begin an_r = 4'b1110; seg_r = hex_seg(pc_out[3:0]);   end
        2'b01: begin an_r = 4'b1101; seg_r = hex_seg(pc_out[7:4]);   end
        2'b10: begin an_r = 4'b1011; seg_r = SEG_BLK;                end
        2'b11: begin an_r = 4'b0111; seg_r = halt ? SEG_H : SEG_BLK; end
    endcase
end

assign seg = seg_r;
assign an  = an_r;

endmodule