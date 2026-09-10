`timescale 1ns / 1ps
`default_nettype none

module imm_tb;

    reg  [31:0] inst;
    reg  [5:0]  format;
    wire [31:0] immediate;

    integer passed;
    integer failed;

    imm dut (
        .i_inst      (inst),
        .i_format    (format),
        .o_immediate (immediate)
    );

    task check;
        input [511:0] label;
        input [31:0] t_inst;
        input [5:0]  t_format;
        input [31:0] expected;
        begin
            inst   = t_inst;
            format = t_format;
            #1;
            if (immediate === expected) begin
                passed = passed + 1;
                $display("[PASS] %0s", label);
            end else begin
                failed = failed + 1;
                $display("[FAIL] %0s", label);
                $display("       inst=%h format=%b immediate=%h expected=%h",
                         t_inst, t_format, immediate, expected);
            end
        end
    endtask

    initial begin
        $dumpfile("imm_tb.vcd");
        $dumpvars(0, imm_tb);

        passed = 0;
        failed = 0;

        $display("========== IMM testbench ==========");

        // I-type: addi x5,x6,8 and addi x5,x6,-1
        check("I-type positive", 32'h00830293, 6'b000010, 32'd8);
        check("I-type negative", 32'hfff30293, 6'b000010, 32'hffff_ffff);

        // S-type: sw x5,8(x6) and sw x5,-8(x6)
        check("S-type positive", 32'h00532423, 6'b000100, 32'd8);
        check("S-type negative", 32'hfe532c23, 6'b000100, 32'hffff_fff8);

        // B-type: beq x5,x6,+16 and beq x5,x6,-4
        check("B-type positive", 32'h00628863, 6'b001000, 32'd16);
        check("B-type negative", 32'hfe629ee3, 6'b001000, 32'hffff_fffc);

        // U-type: lui x5,0x12345
        check("U-type", 32'h123452b7, 6'b010000, 32'h1234_5000);

        // J-type: jal x5,+16 and jal x5,-4
        check("J-type positive", 32'h010002ef, 6'b100000, 32'd16);
        check("J-type negative", 32'hffdff2ef, 6'b100000, 32'hffff_fffc);

        // R-type / illegal format defaults to zero.
        check("R-type default", 32'h007302b3, 6'b000001, 32'd0);
        check("zero format default", 32'h00000000, 6'b000000, 32'd0);

        $display("===================================");
        $display("%0d passed, %0d failed", passed, failed);
        if (failed == 0) $display("ALL TESTS PASSED");
        else             $display("TEST FAILED");
        $finish;
    end

endmodule

`default_nettype wire
