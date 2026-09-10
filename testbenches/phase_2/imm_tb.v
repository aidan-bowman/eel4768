`timescale 1ns / 1ps
`default_nettype none

module imm_tb;

    parameter TRACE_FILE = "../../course_files/phase_2/traces/imm.trace";

    reg  [31:0] i_inst;
    reg  [5:0]  i_format;
    wire [31:0] o_immediate;

    integer fd;
    integer rc;
    integer passed;
    integer failed;
    integer data_count;

    reg [31:0] exp_immediate;

    imm dut (
        .i_inst      (i_inst),
        .i_format    (i_format),
        .o_immediate (o_immediate)
    );

    initial begin
        $dumpfile("imm_trace_tb.vcd");
        $dumpvars(0, imm_tb);

        passed = 0;
        failed = 0;
        data_count = 0;

        fd = $fopen(TRACE_FILE, "r");
        if (fd == 0) begin
            $display("ERROR: Could not open %0s", TRACE_FILE);
            $finish;
        end

        $display("========== IMM trace testbench ==========");
        $display("Trace: %0s", TRACE_FILE);

        while (!$feof(fd)) begin
            rc = $fscanf(fd, "%h %h %h\n",
                         i_inst, i_format, exp_immediate);

            if (rc == 3) begin
                data_count = data_count + 1;
                #1;

                if (o_immediate === exp_immediate) begin
                    passed = passed + 1;
                end else begin
                    failed = failed + 1;
                    $display("[FAIL] vector %0d", data_count);
                    $display("       inst=%h format=%h", i_inst, i_format);
                    $display("       immediate=%h expected=%h",
                             o_immediate, exp_immediate);
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
