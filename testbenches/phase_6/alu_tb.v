`timescale 1ns/1ps
`default_nettype none

module alu_tb;
    reg clk, rst;
    reg [2:0] opsel;
    reg sub, unsigned_cmp, arith, mext, advance;
    reg [31:0] op1, op2;
    wire [31:0] result;
    wire eq, slt, busy;
    integer passed, failed;

    alu dut (
        .i_clk(clk), .i_rst(rst), .i_opsel(opsel), .i_sub(sub),
        .i_unsigned(unsigned_cmp), .i_arith(arith), .i_mext(mext),
        .i_advance(advance), .i_op1(op1), .i_op2(op2),
        .o_result(result), .o_eq(eq), .o_slt(slt), .o_busy(busy)
    );
    always #5 clk = ~clk;

    task check_result;
        input [8*36-1:0] label;
        input [31:0] expected;
        begin
            if (result === expected) begin
                $display("PASS %0s: %08x", label, result);
                passed = passed + 1;
            end else begin
                $display("FAIL %0s: got %08x expected %08x", label, result, expected);
                failed = failed + 1;
            end
        end
    endtask

    task run_m;
        input [8*36-1:0] label;
        input [2:0] function_code;
        input [31:0] a;
        input [31:0] b;
        input [31:0] expected;
        integer cycles;
        begin
            @(negedge clk);
            opsel = function_code;
            op1 = a;
            op2 = b;
            mext = 1'b1;
            advance = 1'b0;
            #1;
            cycles = 0;
            while (busy && cycles < 50) begin
                @(negedge clk);
                cycles = cycles + 1;
            end
            if (busy) begin
                $display("FAIL %0s: operation remained busy", label);
                failed = failed + 1;
            end else begin
                check_result(label, expected);
            end
            // The result must remain available until the EX instruction advances.
            @(negedge clk);
            check_result("held M result", expected);
            advance = 1'b1;
            @(posedge clk);
            #1;
            @(negedge clk);
            advance = 1'b0;
            mext = 1'b0;
            #1;
        end
    endtask

    initial begin
        clk = 0; rst = 1; opsel = 0; sub = 0; unsigned_cmp = 0;
        arith = 0; mext = 0; advance = 0; op1 = 0; op2 = 0;
        passed = 0; failed = 0;
        repeat (2) @(posedge clk);
        @(negedge clk); rst = 0;

        opsel = 3'b000; op1 = 32'd7; op2 = 32'd9; #1;
        check_result("add", 32'd16);
        sub = 1; #1; check_result("subtract", 32'hfffffffe); sub = 0;
        opsel = 3'b001; op1 = 32'd3; op2 = 32'd4; #1;
        check_result("shift left", 32'd48);
        opsel = 3'b100; op1 = 32'hff00aa55; op2 = 32'h0f0f0f0f; #1;
        check_result("xor", 32'hf00fa55a);

        run_m("mul",   3'b000, 32'd7, 32'd3, 32'd21);
        run_m("mulh",  3'b001, 32'hfffffff9, 32'd3, 32'hffffffff);
        run_m("mulhsu",3'b010, 32'hfffffff9, 32'd3, 32'hffffffff);
        run_m("mulhu", 3'b011, 32'hffffffff, 32'd2, 32'd1);
        run_m("div",   3'b100, 32'hffffffec, 32'd3, 32'hfffffffa);
        run_m("divu",  3'b101, 32'd20, 32'd3, 32'd6);
        run_m("rem",   3'b110, 32'hffffffec, 32'd3, 32'hfffffffe);
        run_m("remu",  3'b111, 32'd20, 32'd3, 32'd2);
        run_m("div by zero", 3'b100, 32'd23, 32'd0, 32'hffffffff);
        run_m("rem by zero", 3'b110, 32'd23, 32'd0, 32'd23);
        run_m("signed overflow", 3'b100, 32'h80000000, 32'hffffffff, 32'h80000000);

        $display("\nALU tests: %0d passed, %0d failed", passed, failed);
        if (failed != 0) $fatal(1, "ALU testbench failed");
        $display("All ALU tests passed");
        $finish;
    end
endmodule

`default_nettype wire
