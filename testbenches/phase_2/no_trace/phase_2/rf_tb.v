`timescale 1ns / 1ps
`default_nettype none

module rf_tb;

    reg         clk;
    reg         rst;
    reg  [4:0]  rs1_addr;
    reg  [4:0]  rs2_addr;
    reg         rd_wen;
    reg  [4:0]  rd_waddr;
    reg  [31:0] rd_wdata;

    wire [31:0] no_bp_rs1;
    wire [31:0] no_bp_rs2;
    wire [31:0] bp_rs1;
    wire [31:0] bp_rs2;

    integer passed;
    integer failed;

    rf #(.BYPASS_EN(0)) dut_no_bypass (
        .i_clk       (clk),
        .i_rst       (rst),
        .i_rs1_raddr (rs1_addr),
        .o_rs1_rdata (no_bp_rs1),
        .i_rs2_raddr (rs2_addr),
        .o_rs2_rdata (no_bp_rs2),
        .i_rd_wen    (rd_wen),
        .i_rd_waddr  (rd_waddr),
        .i_rd_wdata  (rd_wdata)
    );

    rf #(.BYPASS_EN(1)) dut_bypass (
        .i_clk       (clk),
        .i_rst       (rst),
        .i_rs1_raddr (rs1_addr),
        .o_rs1_rdata (bp_rs1),
        .i_rs2_raddr (rs2_addr),
        .o_rs2_rdata (bp_rs2),
        .i_rd_wen    (rd_wen),
        .i_rd_waddr  (rd_waddr),
        .i_rd_wdata  (rd_wdata)
    );

    task check_reads;
        input [511:0] label;
        input [31:0] expected1;
        input [31:0] expected2;
        begin
            #1;
            if (no_bp_rs1 === expected1 && no_bp_rs2 === expected2 &&
                bp_rs1    === expected1 && bp_rs2    === expected2) begin
                passed = passed + 1;
                $display("[PASS] %0s", label);
            end else begin
                failed = failed + 1;
                $display("[FAIL] %0s", label);
                $display("       no-bypass: rs1=%h rs2=%h", no_bp_rs1, no_bp_rs2);
                $display("       bypass:    rs1=%h rs2=%h", bp_rs1, bp_rs2);
                $display("       expected:  rs1=%h rs2=%h", expected1, expected2);
            end
        end
    endtask

    task clock_write;
        input [4:0] addr;
        input [31:0] data;
        begin
            rd_wen   = 1'b1;
            rd_waddr = addr;
            rd_wdata = data;
            #1;
            clk = 1'b1;
            #1;
            clk = 1'b0;
            #1;
            rd_wen = 1'b0;
        end
    endtask

    initial begin
        $dumpfile("rf_tb.vcd");
        $dumpvars(0, rf_tb);

        passed = 0;
        failed = 0;
        clk = 0;
        rst = 0;
        rs1_addr = 0;
        rs2_addr = 0;
        rd_wen = 0;
        rd_waddr = 0;
        rd_wdata = 0;

        $display("========== RF testbench ==========");

        // Synchronous reset.
        rst = 1'b1;
        #1;
        clk = 1'b1;
        #1;
        clk = 1'b0;
        #1;
        rst = 1'b0;

        rs1_addr = 0;
        rs2_addr = 0;
        check_reads("reset clears x0", 0, 0);

        // Normal writes and asynchronous reads.
        clock_write(5'd5, 32'h1234_5678);
        rs1_addr = 5'd5;
        rs2_addr = 5'd5;
        check_reads("write/read x5", 32'h1234_5678, 32'h1234_5678);

        // Independent read ports.
        clock_write(5'd6, 32'hdead_beef);
        rs1_addr = 5'd5;
        rs2_addr = 5'd6;
        check_reads("independent read ports", 32'h1234_5678, 32'hdead_beef);

        // x0 must remain zero even when a write is attempted.
        clock_write(5'd0, 32'hffff_ffff);
        rs1_addr = 0;
        rs2_addr = 5'd5;
        check_reads("x0 ignores writes", 0, 32'h1234_5678);

        // Write enable low must preserve the old value.
        rd_wen = 1'b0;
        rd_waddr = 5'd5;
        rd_wdata = 32'h0000_0000;
        #1;
        clk = 1'b1;
        #1;
        clk = 1'b0;
        #1;
        rs1_addr = 5'd5;
        rs2_addr = 5'd6;
        check_reads("write disabled preserves data", 32'h1234_5678, 32'hdead_beef);

        // Bypass mode: data must appear immediately before the clock edge.
        rs1_addr = 5'd5;
        rs2_addr = 5'd6;
        rd_wen = 1'b1;
        rd_waddr = 5'd5;
        rd_wdata = 32'haaaa_5555;
        #1;

        if (bp_rs1 === 32'haaaa_5555 &&
            no_bp_rs1 === 32'h1234_5678) begin
            passed = passed + 1;
            $display("[PASS] bypass forwards pending write");
        end else begin
            failed = failed + 1;
            $display("[FAIL] bypass forwards pending write");
            $display("       bypass=%h expected=%h", bp_rs1, 32'haaaa_5555);
            $display("       no-bypass=%h expected old=%h", no_bp_rs1, 32'h1234_5678);
        end

        // After the clock, both modes must contain the new value.
        clk = 1'b1;
        #1;
        clk = 1'b0;
        #1;
        rd_wen = 1'b0;
        check_reads("write commits to both modes", 32'haaaa_5555, 32'hdead_beef);

        // Bypass must not forward a write to x0.
        rs1_addr = 0;
        rd_wen = 1'b1;
        rd_waddr = 0;
        rd_wdata = 32'hcafebabe;
        #1;
        if (bp_rs1 === 0 && no_bp_rs1 === 0) begin
            passed = passed + 1;
            $display("[PASS] bypass does not forward x0");
        end else begin
            failed = failed + 1;
            $display("[FAIL] bypass does not forward x0");
        end

        $display("==================================");
        $display("%0d passed, %0d failed", passed, failed);
        if (failed == 0) $display("ALL TESTS PASSED");
        else             $display("TEST FAILED");
        $finish;
    end

endmodule

`default_nettype wire
