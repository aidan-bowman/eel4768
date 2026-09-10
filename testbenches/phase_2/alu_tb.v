`timescale 1ns / 1ps
`default_nettype none

module alu_tb;

    parameter TRACE_FILE = "../../course_files/phase_2/traces/alu.trace";

    reg [2:0]  i_opsel;
    reg        i_sub;
    reg        i_unsigned;
    reg        i_arith;
    reg [31:0] i_op1;
    reg [31:0] i_op2;

    wire [31:0] o_result;
    wire        o_eq;
    wire        o_slt;

    integer fd;
    integer rc;
    integer passed;
    integer failed;
    integer line_no;
    integer data_count;

    reg [31:0] exp_result;
    reg        exp_eq;
    reg        exp_slt;

    alu dut (
        .i_opsel    (i_opsel),
        .i_sub      (i_sub),
        .i_unsigned(i_unsigned),
        .i_arith    (i_arith),
        .i_op1      (i_op1),
        .i_op2      (i_op2),
        .o_result   (o_result),
        .o_eq       (o_eq),
        .o_slt      (o_slt)
    );

    initial begin
        $dumpfile("alu_trace_tb.vcd");
        $dumpvars(0, alu_tb);

        passed = 0;
        failed = 0;
        line_no = 0;
        data_count = 0;

        fd = $fopen(TRACE_FILE, "r");
        if (fd == 0) begin
            $display("ERROR: Could not open %0s", TRACE_FILE);
            $finish;
        end

        $display("========== ALU trace testbench ==========");
        $display("Trace: %0s", TRACE_FILE);

        // Comments/blank lines are skipped by scanning for the six input
        // fields. Every successful fscanf is one trace vector.
        while (!$feof(fd)) begin
            rc = $fscanf(fd, "%b %b %b %b %h %h %h %b %b\n",
                         i_opsel, i_sub, i_unsigned, i_arith,
                         i_op1, i_op2, exp_result, exp_eq, exp_slt);

            if (rc == 9) begin
                data_count = data_count + 1;
                #1;

                if (o_result === exp_result &&
                    o_eq     === exp_eq &&
                    o_slt    === exp_slt) begin
                    passed = passed + 1;
                end else begin
                    failed = failed + 1;
                    $display("[FAIL] vector %0d", data_count);
                    $display("       inputs: opsel=%b sub=%b unsigned=%b arith=%b op1=%h op2=%h",
                             i_opsel, i_sub, i_unsigned, i_arith, i_op1, i_op2);
                    $display("       result: %h expected %h", o_result, exp_result);
                    $display("       eq:     %b expected %b", o_eq, exp_eq);
                    $display("       slt:    %b expected %b", o_slt, exp_slt);
                end
            end
        end

        $fclose(fd);

        $display("-----------------------------------------");
        $display("%0d trace vectors checked", data_count);
        $display("%0d passed, %0d failed", passed, failed);

        if (failed == 0)
            $display("ALL TRACE TESTS PASSED");
        else
            $display("TRACE TEST FAILED");

        $finish;
    end

endmodule

`default_nettype wire
