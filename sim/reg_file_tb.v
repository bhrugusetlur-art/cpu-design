// =============================================================
//  reg_file_tb.v  —  Testbench for reg_file
//  Run with:
//    iverilog -g2012 -o rf_tb sim/reg_file_tb.v design/reg_file.v && vvp rf_tb
// =============================================================
`timescale 1ns/1ps

module reg_file_tb;

    reg        clk, rst;
    reg  [1:0] rs1_addr, rs2_addr, rd_addr;
    reg  [7:0] rd_data;
    reg        wr_en;
    wire [7:0] rs1_data, rs2_data;
    wire [7:0] debug_r0, debug_r1, debug_r2, debug_r3;

    reg_file dut (
        .clk(clk), .rst(rst),
        .rs1_addr(rs1_addr), .rs1_data(rs1_data),
        .rs2_addr(rs2_addr), .rs2_data(rs2_data),
        .rd_addr(rd_addr), .rd_data(rd_data), .wr_en(wr_en),
        .debug_r0(debug_r0), .debug_r1(debug_r1),
        .debug_r2(debug_r2), .debug_r3(debug_r3)
    );

    initial clk = 0;
    always #5 clk = ~clk;
    integer fail_cnt;

    // Write rd_data into rd_addr on next rising edge
    task write_reg;
        input [1:0] addr;
        input [7:0] data;
        begin
            @(negedge clk);
            rd_addr = addr; rd_data = data; wr_en = 1;
            @(posedge clk);
            #1; wr_en = 0;
        end
    endtask

    initial begin
        $dumpfile("reg_file.vcd");
        $dumpvars(0, reg_file_tb);

        rst = 1; wr_en = 0;
        rd_addr = 0; rd_data = 0;
        rs1_addr = 0; rs2_addr = 0; fail_cnt = 0;
        repeat(2) @(posedge clk);
        rst = 0;
        @(posedge clk); #1;

        // --------------------------------------------------
        // Test 1: all registers zero after reset
        // --------------------------------------------------
        $display("TEST 1: all registers zero after reset");
        begin : t1
            reg ok; integer i;
            ok = 1;
            for (i = 0; i < 4; i = i + 1) begin
                rs1_addr = i[1:0]; #1;
                if (rs1_data !== 8'h00) begin
                    $display("  FAIL: R%0d = 0x%02h, expected 0x00", i, rs1_data);
                    ok = 0;
                end
            end
            if (ok) $display("  PASS: R0–R3 all 0x00");
            else fail_cnt = fail_cnt + 1;
        end

        // --------------------------------------------------
        // Test 2: write each register and read it back
        // --------------------------------------------------
        $display("TEST 2: write and read back R0–R3");
        begin : t2
            reg ok;
            ok = 1;
            write_reg(2'd0, 8'hAA);
            write_reg(2'd1, 8'hBB);
            write_reg(2'd2, 8'hCC);
            write_reg(2'd3, 8'hDD);
            // read all four via port 1
            rs1_addr = 0; #1;
            if (rs1_data !== 8'hAA) begin $display("  FAIL R0: got 0x%02h", rs1_data); ok=0; end
            rs1_addr = 1; #1;
            if (rs1_data !== 8'hBB) begin $display("  FAIL R1: got 0x%02h", rs1_data); ok=0; end
            rs1_addr = 2; #1;
            if (rs1_data !== 8'hCC) begin $display("  FAIL R2: got 0x%02h", rs1_data); ok=0; end
            rs1_addr = 3; #1;
            if (rs1_data !== 8'hDD) begin $display("  FAIL R3: got 0x%02h", rs1_data); ok=0; end
            if (ok) $display("  PASS: R0=0xAA R1=0xBB R2=0xCC R3=0xDD");
            else fail_cnt = fail_cnt + 1;
        end

        // --------------------------------------------------
        // Test 3: simultaneous two-port read
        // --------------------------------------------------
        $display("TEST 3: simultaneous read on both ports");
        rs1_addr = 2'd0; rs2_addr = 2'd3; #1;
        if (rs1_data === 8'hAA && rs2_data === 8'hDD)
            $display("  PASS: port1=0x%02h port2=0x%02h", rs1_data, rs2_data);
        else begin
            $display("  FAIL: port1=0x%02h (want 0xAA)  port2=0x%02h (want 0xDD)",
                     rs1_data, rs2_data);
            fail_cnt = fail_cnt + 1;
        end

        // --------------------------------------------------
        // Test 4: wr_en=0 does not modify register
        // --------------------------------------------------
        $display("TEST 4: write disabled (wr_en=0) does not change register");
        @(negedge clk);
        rd_addr = 2'd1; rd_data = 8'hFF; wr_en = 0;
        @(posedge clk); #1;
        rs1_addr = 2'd1; #1;
        if (rs1_data === 8'hBB)
            $display("  PASS: R1 still 0x%02h", rs1_data);
        else begin
            $display("  FAIL: R1 = 0x%02h, expected 0xBB", rs1_data);
            fail_cnt = fail_cnt + 1;
        end

        // --------------------------------------------------
        // Test 5: write and read same register — old value
        //         visible in the write cycle, new value next cycle
        // --------------------------------------------------
        $display("TEST 5: read-during-write returns old value");
        @(negedge clk);
        rs1_addr = 2'd2;          // point port 1 at R2 (currently 0xCC)
        rd_addr  = 2'd2;
        rd_data  = 8'h42;
        wr_en    = 1;
        #1;                        // combinational reads settle before clock edge
        if (rs1_data === 8'hCC)
            $display("  PASS: read sees old value 0x%02h during write cycle", rs1_data);
        else begin
            $display("  FAIL: expected 0xCC during write, got 0x%02h", rs1_data);
            fail_cnt = fail_cnt + 1;
        end
        @(posedge clk); #1; wr_en = 0;
        if (rs1_data === 8'h42)
            $display("  PASS: read sees new value 0x%02h after clock edge", rs1_data);
        else begin
            $display("  FAIL: expected 0x42 after write, got 0x%02h", rs1_data);
            fail_cnt = fail_cnt + 1;
        end

        $display("All tests done.");
        if (fail_cnt != 0) $fatal(1, "Register file regression failed");
        $finish;
    end

endmodule
