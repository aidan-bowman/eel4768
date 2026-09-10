`timescale 1ns / 1ps
`default_nettype none

module rf_trace_tb #(
    parameter BYPASS_EN = 0,
    parameter TRACE_FILE = "../../course_files/phase_2/traces/rf_no_bypass.trace"
);

    reg        i_clk;
    reg        i_rst;
    reg [4:0]  i_rs1_raddr;
    reg [4:0]  i_rs2_raddr;
    reg        i_rd_wen;
    reg [4:0]  i_rd_waddr;
    reg [31:0] i_rd_wdata;

    wire [31:0] o_rs1_rdata;
    wire [31:0] o_rs2_rdata;

    integer fd;
    integer rc;
    integer passed;
    integer failed;
    integer data_count;

    reg [31:0] exp_rs1;
    reg [31:0] exp_rs2;

    rf #(.BYPASS_EN(BYPASS_EN)) dut (
        .i_clk       (i_clk),
        .i_rst       (i_rst),
        .i_rs1_raddr (i_rs1_raddr),
        .o_rs1_rdata (o_rs1_rdata),
        .i_rs2_raddr (i_rs2_raddr),
        .o_rs2_rdata (o_rs2_rdata),
        .i_rd_wen    (i_rd_wen),
        .i_rd_waddr  (i_rd_waddr),
        .i_rd_wdata  (i_rd_wdata)
    );

    task clock_edge;
        begin
            #1 i_clk = 1'b1;
            #1 i_clk = 1'b0;
            #1;
        end
    endtask

    initial begin
        $dumpfile(BYPASS_EN ? "rf_bypass_trace_tb.vcd"
                            : "rf_no_bypass_trace_tb.vcd");
        $dumpvars(0, rf_trace_tb);

        i_clk = 1'b0;
        passed = 0;
        failed = 0;
        data_count = 0;

        fd = $fopen(TRACE_FILE, "r");
        if (fd == 0) begin
            $display("ERROR: Could not open %0s", TRACE_FILE);
            $finish;
        end

        $display("========== RF trace testbench ==========");
        $display("BYPASS_EN: %0d", BYPASS_EN);
        $display("Trace: %0s", TRACE_FILE);

        while (!$feof(fd)) begin
            rc = $fscanf(fd, "%b %h %h %b %h %h %h %h\n",
                         i_rst,
                         i_rs1_raddr,
                         i_rs2_raddr,
                         i_rd_wen,
                         i_rd_waddr,
                         i_rd_wdata,
                         exp_rs1,
                         exp_rs2);

            if (rc == 8) begin
                data_count = data_count + 1;

                // The trace describes the inputs and the asynchronous outputs
                // for this cycle. Check outputs before advancing the clock.
                #1;

                if (o_rs1_rdata === exp_rs1 &&
                    o_rs2_rdata === exp_rs2) begin
                    passed = passed + 1;
                end else begin
                    failed = failed + 1;
                    $display("[FAIL] vector %0d", data_count);
                    $display("       rst=%b rs1=%h rs2=%h wen=%b waddr=%h wdata=%h",
                             i_rst, i_rs1_raddr, i_rs2_raddr,
                             i_rd_wen, i_rd_waddr, i_rd_wdata);
                    $display("       rs1=%h expected=%h", o_rs1_rdata, exp_rs1);
                    $display("       rs2=%h expected=%h", o_rs2_rdata, exp_rs2);
                end

                // Writes and synchronous reset take effect on the clock edge
                // after the vector has been observed.
                clock_edge;
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
