`timescale 1ns/1ps
`default_nettype none

module multiplier_tb;
    reg clk, rst, start, a_signed, b_signed;
    reg [31:0] a, b;
    wire [63:0] product;
    wire busy, ready;
    integer passed, failed;

    multiplier dut (
        .i_clk(clk), .i_rst(rst), .i_start(start), .i_mula(a), .i_mulb(b),
        .i_mula_signed(a_signed), .i_mulb_signed(b_signed),
        .o_prod(product), .o_busy(busy), .o_ready(ready)
    );
    always #5 clk = ~clk;

    task multiply_check;
        input [8*36-1:0] label;
        input [31:0] av, bv;
        input as, bs;
        reg signed [63:0] av_ext, bv_ext, expected;
        integer cycles;
        begin
            av_ext = as ? {{32{av[31]}}, av} : {32'b0, av};
            bv_ext = bs ? {{32{bv[31]}}, bv} : {32'b0, bv};
            expected = av_ext * bv_ext;
            @(negedge clk);
            a=av; b=bv; a_signed=as; b_signed=bs; start=1;
            @(posedge clk); #1; start=0;
            cycles=0;
            while (!ready && cycles < 12) begin
                @(negedge clk); cycles=cycles+1;
            end
            if (ready && product === expected) begin
                $display("PASS %0s: %016x", label, product);
                passed=passed+1;
            end else begin
                $display("FAIL %0s: got %016x expected %016x ready=%b", label, product, expected, ready);
                failed=failed+1;
            end
            @(posedge clk); #1;
        end
    endtask

    initial begin
        clk=0; rst=1; start=0; a_signed=0; b_signed=0;
        a=0; b=0; passed=0; failed=0;
        repeat (2) @(posedge clk);
        @(negedge clk); rst=0;
        multiply_check("unsigned zero", 0, 32'hffffffff, 0, 0);
        multiply_check("unsigned max times two", 32'hffffffff, 2, 0, 0);
        multiply_check("signed negative", 32'hfffffff9, 3, 1, 1);
        multiply_check("signed by unsigned", 32'hfffffff9, 3, 1, 0);
        multiply_check("both negative", 32'hfffffffe, 32'hfffffffd, 1, 1);
        $display("Multiplier tests: %0d passed, %0d failed", passed, failed);
        if (failed != 0) $fatal(1, "multiplier tests failed");
        $finish;
    end
endmodule

`default_nettype wire
