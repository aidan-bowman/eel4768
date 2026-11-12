`timescale 1ns/1ps
`default_nettype none

module rf_tb;
    reg clk, rst;
    reg [4:0] rs1, rs2, frs1, frs2, frs3;
    reg [4:0] rd_addr, frd_addr;
    reg [31:0] rd_data, frd_data;
    reg frd_wen;
    wire [31:0] bp_rs1, bp_rs2, nbp_rs1, nbp_rs2;
    wire [31:0] bp_frs1, bp_frs2, bp_frs3, nbp_frs1, nbp_frs2, nbp_frs3;
    integer passed, failed;
    always #5 clk = ~clk;

    rf #(.BYPASS_EN(1)) bypass_rf (
        .i_clk(clk), .i_rst(rst), .i_rs1_raddr(rs1), .o_rs1_rdata(bp_rs1),
        .i_rs2_raddr(rs2), .o_rs2_rdata(bp_rs2),
        .i_rd_waddr(rd_addr), .i_rd_wdata(rd_data),
        .i_frs1_raddr(frs1), .o_frs1_rdata(bp_frs1),
        .i_frs2_raddr(frs2), .o_frs2_rdata(bp_frs2),
        .i_frs3_raddr(frs3), .o_frs3_rdata(bp_frs3),
        .i_frd_wen(frd_wen), .i_frd_waddr(frd_addr), .i_frd_wdata(frd_data)
    );
    rf #(.BYPASS_EN(0)) no_bypass_rf (
        .i_clk(clk), .i_rst(rst), .i_rs1_raddr(rs1), .o_rs1_rdata(nbp_rs1),
        .i_rs2_raddr(rs2), .o_rs2_rdata(nbp_rs2),
        .i_rd_waddr(rd_addr), .i_rd_wdata(rd_data),
        .i_frs1_raddr(frs1), .o_frs1_rdata(nbp_frs1),
        .i_frs2_raddr(frs2), .o_frs2_rdata(nbp_frs2),
        .i_frs3_raddr(frs3), .o_frs3_rdata(nbp_frs3),
        .i_frd_wen(frd_wen), .i_frd_waddr(frd_addr), .i_frd_wdata(frd_data)
    );

    task check;
        input [8*36-1:0] label;
        input [31:0] expected;
        input [31:0] a, b, c;
        begin
            #1;
            if (a === expected && b === expected && c === expected) begin
                passed = passed + 1;
                $display("PASS %0s", label);
            end else begin
                failed = failed + 1;
                $display("FAIL %0s: got %08x %08x %08x expected %08x", label, a, b, c, expected);
            end
        end
    endtask

    task tick;
        begin @(posedge clk); #1; end
    endtask

    initial begin
        clk=0; rst=0; rs1=0; rs2=0; frs1=0; frs2=0; frs3=0;
        rd_addr=0; rd_data=0; frd_addr=0; frd_data=0; frd_wen=0;
        passed=0; failed=0;
        rst=1; tick(); rst=0;

        rs1=0; rs2=0;
        check("x0 hardwired", 32'b0, bp_rs1, nbp_rs1, bp_rs2);
        rd_addr=5; rd_data=32'h12345678; tick(); rd_addr=0;
        rs1=5; rs2=5; #1;
        check("integer write and async read", 32'h12345678, bp_rs1, nbp_rs1, bp_rs2);
        rd_addr=0; rd_data=32'hffffffff; tick();
        rs1=0; rs2=0; #1; check("integer x0 ignores writes", 32'b0, bp_rs1, nbp_rs1, bp_rs2);

        frd_wen=1; frd_addr=0; frd_data=32'h3f800000; tick();
        frd_addr=4; frd_data=32'h40000000; tick();
        frd_wen=0; frs1=0; frs2=4; frs3=0;
        check("FP f0 is writable", 32'h3f800000, bp_frs1, nbp_frs1, bp_frs3);
        check("independent FP read ports", 32'h40000000, bp_frs2, nbp_frs2, bp_frs2);

        // Floating-point write bypass is immediate, but the no-bypass instance
        // continues to expose the stored value until the clock edge.
        frd_wen=1; frd_addr=4; frd_data=32'h40400000; #1;
        check("FP write bypass", 32'h40400000, bp_frs2, bp_frs2, bp_frs2);
        check("no-bypass keeps old FP data", 32'h40000000, nbp_frs2, nbp_frs2, nbp_frs2);
        tick(); frd_wen=0;
        check("FP write commit", 32'h40400000, bp_frs2, nbp_frs2, bp_frs2);

        $display("RF tests: %0d passed, %0d failed", passed, failed);
        if (failed != 0) $fatal(1, "RF tests failed");
        $finish;
    end
endmodule

`default_nettype wire
