`timescale 1ns / 1ps
`default_nettype none

module alu_tb;

    reg  [2:0]  opsel;
    reg         sub;
    reg         uns;
    reg         arith;
    reg  [31:0] op1;
    reg  [31:0] op2;

    wire [31:0] result;
    wire        eq;
    wire        slt;

    integer passed;
    integer failed;
    integer i;
    integer seed;

    alu dut (
        .i_opsel      (opsel),
        .i_sub        (sub),
        .i_unsigned   (uns),
        .i_arith      (arith),
        .i_op1        (op1),
        .i_op2        (op2),
        .o_result     (result),
        .o_eq         (eq),
        .o_slt        (slt)
    );

    function [31:0] model_result;
        input [2:0]  f_opsel;
        input        f_sub;
        input        f_arith;
        input [31:0] f_op1;
        input [31:0] f_op2;
        reg [31:0]   v;
        begin
            case (f_opsel)
                3'b000: v = f_sub ? (f_op1 - f_op2) : (f_op1 + f_op2);
                3'b001: v = f_op1 << f_op2[4:0];
                3'b010: v = {31'b0, ($signed(f_op1) < $signed(f_op2))};
                3'b011: v = {31'b0, (f_op1 < f_op2)};
                3'b100: v = f_op1 ^ f_op2;
                3'b101: v = f_arith ? $signed(f_op1) >>> f_op2[4:0]
                                     : f_op1 >> f_op2[4:0];
                3'b110: v = f_op1 | f_op2;
                default: v = f_op1 & f_op2;
            endcase
            model_result = v;
        end
    endfunction

    task check;
        input [511:0] label;
        input [2:0]  t_opsel;
        input        t_sub;
        input        t_uns;
        input        t_arith;
        input [31:0] t_op1;
        input [31:0] t_op2;
        input [31:0] expected_result;
        input        expected_eq;
        input        expected_slt;
        begin
            opsel = t_opsel;
            sub   = t_sub;
            uns   = t_uns;
            arith = t_arith;
            op1   = t_op1;
            op2   = t_op2;
            #1;

            if (result === expected_result &&
                eq     === expected_eq &&
                slt    === expected_slt) begin
                passed = passed + 1;
                $display("[PASS] %0s", label);
            end else begin
                failed = failed + 1;
                $display("[FAIL] %0s", label);
                $display("       op1=%h op2=%h opsel=%b sub=%b unsigned=%b arith=%b",
                         t_op1, t_op2, t_opsel, t_sub, t_uns, t_arith);
                $display("       result=%h expected=%h", result, expected_result);
                $display("       eq=%b expected=%b, slt=%b expected=%b",
                         eq, expected_eq, slt, expected_slt);
            end
        end
    endtask

    reg [31:0] rand_a;
    reg [31:0] rand_b;
    reg [2:0]  rand_op;
    reg        rand_sub;
    reg        rand_uns;
    reg        rand_arith;
    reg [31:0] rand_expected;
    reg        rand_eq;
    reg        rand_slt;

    initial begin
        $dumpfile("alu_tb.vcd");
        $dumpvars(0, alu_tb);

        passed = 0;
        failed = 0;
        seed   = 32'd4768;

        $display("========== ALU testbench ==========");

        $display("--- add/sub ---");
        check("add: 7 + 9", 3'b000, 0, 0, 0, 7, 9, 16, 0, 0);
        check("add: zero", 3'b000, 0, 0, 0, 0, 0, 0, 1, 0);
        check("add: wrap", 3'b000, 0, 0, 0, 32'hffff_ffff, 1, 0, 0, 0);
        check("sub: 9 - 7", 3'b000, 1, 0, 0, 9, 7, 2, 0, 0);
        check("sub: 7 - 9", 3'b000, 1, 0, 0, 7, 9, 32'hffff_fffe, 0, 0);
        check("sub: equal", 3'b000, 1, 0, 0, 42, 42, 0, 1, 0);

        $display("--- logical operations ---");
        check("xor", 3'b100, 0, 0, 0, 32'h5a5a_1234, 32'ha5a5_4321,
              32'hffff_5115, 0, 0);
        check("or", 3'b110, 0, 0, 0, 32'h0f00_00f0, 32'h00f0_0f00,
              32'h0ff0_0ff0, 0, 0);
        check("and", 3'b111, 0, 0, 0, 32'hffff_0000, 32'h0f0f_f0f0,
              32'h0f0f_0000, 0, 0);

        $display("--- shifts ---");
        check("sll: 1 << 4", 3'b001, 0, 0, 0, 1, 4, 16, 0, 0);
        check("sll: shift 31", 3'b001, 0, 0, 0, 1, 31, 32'h8000_0000, 0, 0);
        check("sll: shift 32 becomes shift 0", 3'b001, 0, 0, 0, 32'h1234_5678, 32, 32'h1234_5678, 0, 0);
        check("srl: positive", 3'b101, 0, 0, 0, 32'h8000_0000, 4, 32'h0800_0000, 0, 0);
        check("srl: all ones", 3'b101, 0, 0, 0, 32'hffff_ffff, 28, 15, 0, 0);
        check("sra: negative", 3'b101, 0, 0, 1, 32'h8000_0000, 4, 32'hf800_0000, 0, 0);
        check("sra: -1", 3'b101, 0, 0, 1, 32'hffff_ffff, 31, 32'hffff_ffff, 0, 0);

        $display("--- comparisons ---");
        check("slt signed: -1 < 1", 3'b010, 0, 0, 0, 32'hffff_ffff, 1, 1, 0, 1);
        check("slt signed: 1 !< -1", 3'b010, 0, 0, 0, 1, 32'hffff_ffff, 0, 0, 0);
        check("sltu unsigned: 0xffffffff !< 1", 3'b011, 0, 1, 0, 32'hffff_ffff, 1, 0, 0, 0);
        check("sltu unsigned: 1 < 0xffffffff", 3'b011, 0, 1, 0, 1, 32'hffff_ffff, 1, 0, 1);

        $display("--- random reference-model tests ---");
        for (i = 0; i < 1000; i = i + 1) begin
            rand_a     = $random(seed);
            rand_b     = $random(seed);
            rand_op    = $random(seed);
            rand_sub   = $random(seed);
            rand_uns   = $random(seed);
            rand_arith = $random(seed);

            rand_expected = model_result(rand_op, rand_sub, rand_arith, rand_a, rand_b);
            rand_eq = (rand_a == rand_b);
            rand_slt = rand_uns ? (rand_a < rand_b)
                                : ($signed(rand_a) < $signed(rand_b));

            opsel = rand_op;
            sub   = rand_sub;
            uns   = rand_uns;
            arith = rand_arith;
            op1   = rand_a;
            op2   = rand_b;
            #1;

            if (result !== rand_expected || eq !== rand_eq || slt !== rand_slt) begin
                failed = failed + 1;
                $display("[FAIL] random %0d: op1=%h op2=%h opsel=%b",
                         i, rand_a, rand_b, rand_op);
                $display("       result=%h expected=%h eq=%b/%b slt=%b/%b",
                         result, rand_expected, eq, rand_eq, slt, rand_slt);
            end else begin
                passed = passed + 1;
            end
        end

        $display("==================================");
        $display("%0d passed, %0d failed", passed, failed);
        if (failed == 0) $display("ALL TESTS PASSED");
        else             $display("TEST FAILED");
        $finish;
    end

endmodule

`default_nettype wire
