`timescale 1ns/1ps
`default_nettype none

// Self-checking unit testbench for the phase 6 floating-point unit.
// Tests use raw IEEE-754 single-precision encodings so expected values are
// independent of simulator real-number support.
module fpu_tb;
    reg clk;
    reg rst;
    reg [31:0] inst;
    reg valid;
    reg advance;
    reg [31:0] frs1;
    reg [31:0] frs2;
    reg [31:0] frs3;
    reg [31:0] xrs1;
    wire [31:0] fp_result;
    wire [31:0] int_result;
    wire [4:0] fflags;
    wire busy;
    wire rm_trap;

    integer passed;
    integer failed;

    fpu dut (
        .i_clk(clk), .i_rst(rst), .i_inst(inst), .i_valid(valid),
        .i_advance(advance), .i_frs1(frs1), .i_frs2(frs2), .i_frs3(frs3),
        .i_xrs1(xrs1), .o_fp_result(fp_result), .o_int_result(int_result),
        .o_fflags(fflags), .o_busy(busy), .o_rm_trap(rm_trap)
    );

    always #5 clk = ~clk;

    task check32;
        input [8*40-1:0] label;
        input [31:0] actual;
        input [31:0] expected;
        begin
            if (actual === expected) begin
                $display("PASS %0s: %08x", label, actual);
                passed = passed + 1;
            end else begin
                $display("FAIL %0s: got %08x expected %08x", label, actual, expected);
                failed = failed + 1;
            end
        end
    endtask

    task check1;
        input [8*40-1:0] label;
        input actual;
        input expected;
        begin
            if (actual === expected) begin
                $display("PASS %0s: %b", label, actual);
                passed = passed + 1;
            end else begin
                $display("FAIL %0s: got %b expected %b", label, actual, expected);
                failed = failed + 1;
            end
        end
    endtask

    // Build an OP-FP instruction from its funct fields.
    task opfp;
        input [6:0] funct7;
        input [4:0] rs2;
        input [2:0] funct3;
        begin
            inst = {funct7, rs2, 5'd1, funct3, 5'd3, 7'h53};
            valid = 1'b1;
            #1;
        end
    endtask

    // Build an R4-format fused instruction (rs3 is an FP register address;
    // the data operand itself is supplied through frs3).
    task fused;
        input [6:0] opcode;
        begin
            inst = {5'd3, 2'b00, 5'd2, 5'd1, 3'b000, 5'd3, opcode};
            valid = 1'b1;
            #1;
        end
    endtask

    task clear_fflags;
        begin
            inst = {12'h001, 5'd0, 3'b001, 5'd0, 7'h73};
            valid = 1'b1;
            xrs1 = 32'b0;
            retire_current();
        end
    endtask

    task retire_current;
        begin
            @(negedge clk);
            advance = 1'b1;
            @(posedge clk);
            #1;
            @(negedge clk);
            advance = 1'b0;
            #1;
        end
    endtask

    task wait_multi;
        integer cycles;
        begin
            cycles = 0;
            while (busy && cycles < 60) begin
                @(negedge clk);
                cycles = cycles + 1;
            end
            if (busy) begin
                $display("FAIL multi-cycle operation did not complete");
                failed = failed + 1;
            end
        end
    endtask

    initial begin
        clk = 1'b0;
        rst = 1'b1;
        inst = 32'b0;
        valid = 1'b0;
        advance = 1'b0;
        frs1 = 32'b0;
        frs2 = 32'b0;
        frs3 = 32'b0;
        xrs1 = 32'b0;
        passed = 0;
        failed = 0;

        repeat (2) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;
        #1;

        // Sign injection: fsgnj.s, fsgnjn.s and fsgnjx.s.
        frs1 = 32'hbf800000; // -1.0
        frs2 = 32'h40000000; // +2.0
        opfp(7'b0010000, 5'd2, 3'b000);
        check32("fsgnj.s", fp_result, 32'hc0000000);
        opfp(7'b0010000, 5'd2, 3'b001);
        check32("fsgnjn.s", fp_result, 32'h40000000);
        opfp(7'b0010000, 5'd2, 3'b010);
        check32("fsgnjx.s", fp_result, 32'hc0000000);

        // Min/max, including signed zero and one-NaN cases.
        frs1 = 32'hc0000000; // -2.0
        frs2 = 32'h40000000; // +2.0
        opfp(7'b0010100, 5'd2, 3'b000);
        check32("fmin.s", fp_result, 32'hc0000000);
        opfp(7'b0010100, 5'd2, 3'b001);
        check32("fmax.s", fp_result, 32'h40000000);
        frs1 = 32'h7fc00000;
        frs2 = 32'h3f800000;
        opfp(7'b0010100, 5'd2, 3'b000);
        check32("fmin.s qNaN", fp_result, 32'h3f800000);

        // FEQ/FLT/FLE and their invalid flag behavior.
        frs1 = 32'h3f800000;
        frs2 = 32'h40000000;
        opfp(7'b1010000, 5'd2, 3'b010);
        check32("feq.s false", int_result, 32'd0);
        opfp(7'b1010000, 5'd2, 3'b001);
        check32("flt.s true", int_result, 32'd1);
        opfp(7'b1010000, 5'd2, 3'b000);
        check32("fle.s true", int_result, 32'd1);
        frs1 = 32'h7fc00000;
        opfp(7'b1010000, 5'd2, 3'b010);
        check32("feq.s qNaN result", int_result, 32'd0);
        check32("feq.s qNaN flag", {27'b0, fflags}, 32'h00000000);
        opfp(7'b1010000, 5'd2, 3'b001);
        check32("flt.s qNaN flag", {27'b0, fflags}, 32'h00000010);
        retire_current();
        check32("accrued NV flag", {27'b0, fflags}, 32'h00000010);

        // FCLASS.S classes and bitwise moves.
        frs1 = 32'hff800000; // -infinity -> class bit 0
        opfp(7'b1110000, 5'd0, 3'b001);
        check32("fclass.s -inf", int_result, 32'h00000001);
        frs1 = 32'h7f800001; // signaling NaN -> class bit 8
        opfp(7'b1110000, 5'd0, 3'b001);
        check32("fclass.s sNaN", int_result, 32'h00000100);
        frs1 = 32'hdeadbeef;
        opfp(7'b1110000, 5'd0, 3'b000);
        check32("fmv.x.w", int_result, 32'hdeadbeef);
        xrs1 = 32'hcafebabe;
        opfp(7'b1111000, 5'd0, 3'b000);
        check32("fmv.w.x", fp_result, 32'hcafebabe);

        // Arithmetic, fused arithmetic, conversions, divide and sqrt are
        // checked explicitly so unimplemented or incorrect datapaths fail.
        frs1 = 32'h3f800000; // 1.0
        frs2 = 32'h40000000; // 2.0
        frs3 = 32'h40400000; // 3.0
        opfp(7'b0000000, 5'd2, 3'b000);
        wait_multi();
        check32("fadd.s 1+2", fp_result, 32'h40400000);
        retire_current();
        opfp(7'b0000100, 5'd2, 3'b000);
        wait_multi();
        check32("fsub.s 1-2", fp_result, 32'hbf800000);
        retire_current();
        opfp(7'b0001000, 5'd2, 3'b000);
        wait_multi();
        check32("fmul.s 1*2", fp_result, 32'h40000000);
        retire_current();
        opfp(7'b0001100, 5'd2, 3'b000);
        wait_multi();
        check32("fdiv.s 1/2", fp_result, 32'h3f000000);
        retire_current();
        opfp(7'b0101100, 5'd0, 3'b000);
        wait_multi();
        check32("fsqrt.s sqrt(1)", fp_result, 32'h3f800000);
        retire_current();

        frs1 = 32'h40c00000; // 6.0
        frs2 = 32'h40000000; // 2.0
        opfp(7'b0001100, 5'd2, 3'b000);
        wait_multi();
        check32("fdiv.s 6/2", fp_result, 32'h40400000);
        retire_current();
        frs1 = 32'h40800000; // 4.0
        opfp(7'b0101100, 5'd0, 3'b000);
        wait_multi();
        check32("fsqrt.s sqrt(4)", fp_result, 32'h40000000);
        retire_current();
        frs1 = 32'h00000001; // minimum positive subnormal
        frs2 = 32'h40000000; // 2.0
        opfp(7'b0001000, 5'd2, 3'b000);
        wait_multi();
        check32("fmul.s minsub*2", fp_result, 32'h00000002);
        retire_current();
        frs2 = 32'h3f800000; // 1.0
        opfp(7'b0000000, 5'd2, 3'b000);
        wait_multi();
        check32("fadd.s minsub+1", fp_result, 32'h3f800000);
        retire_current();
        frs1 = 32'h00000001;
        frs2 = 32'h40000000;
        opfp(7'b0001100, 5'd2, 3'b000);
        wait_multi();
        check32("fdiv.s minsub/2 RNE", fp_result, 32'h00000000);
        check32("fdiv.s underflow flags", {27'b0, fflags}, 32'h00000013);
        retire_current();

        frs1 = 32'h3f800000;
        frs2 = 32'h40000000;
        frs3 = 32'h40400000;
        fused(7'b1000011); // fmadd.s = 1*2+3
        wait_multi();
        check32("fmadd.s", fp_result, 32'h40a00000);
        retire_current();
        fused(7'b1000111); // fmsub.s = 1*2-3
        wait_multi();
        check32("fmsub.s", fp_result, 32'hbf800000);
        retire_current();
        fused(7'b1001011); // fnmsub.s = -(1*2)+3
        wait_multi();
        check32("fnmsub.s", fp_result, 32'h3f800000);
        retire_current();
        fused(7'b1001111); // fnmadd.s = -(1*2)-3
        wait_multi();
        check32("fnmadd.s", fp_result, 32'hc0a00000);
        retire_current();

        // Integer/float conversions (ties use the current RNE rounding mode).
        opfp(7'b1100000, 5'd0, 3'b000); // fcvt.w.s, 1.0 -> 1
        check32("fcvt.w.s 1.0", int_result, 32'd1);
        opfp(7'b1100000, 5'd1, 3'b000); // fcvt.wu.s, 1.0 -> 1
        check32("fcvt.wu.s 1.0", int_result, 32'd1);
        xrs1 = 32'd2;
        opfp(7'b1101000, 5'd0, 3'b000); // fcvt.s.w, 2 -> 2.0
        check32("fcvt.s.w 2", fp_result, 32'h40000000);
        opfp(7'b1101000, 5'd1, 3'b000); // fcvt.s.wu, 2 -> 2.0
        check32("fcvt.s.wu 2", fp_result, 32'h40000000);

        // Rounding mode validation: dynamic rm uses frm; reset initializes
        // frm to RNE, while a reserved frm value must trap.
        opfp(7'b0000000, 5'd2, 3'b111);
        check1("dynamic RNE accepted", rm_trap, 1'b0);
        // CSR write frm = 5 (reserved), then request a dynamic rounding op.
        inst = {12'h002, 5'd5, 3'b001, 5'd0, 7'h73};
        valid = 1'b1;
        xrs1 = 32'd5;
        retire_current();
        opfp(7'b0000000, 5'd2, 3'b111);
        check1("reserved dynamic frm traps", rm_trap, 1'b1);

        // CSR read of frm returns its old value.
        inst = {12'h002, 5'd0, 3'b010, 5'd4, 7'h73};
        valid = 1'b1;
        #1;
        check32("read frm", int_result, 32'd5);

        // Directed IEEE special cases and accrued exception flags.
        clear_fflags();
        frs1 = 32'h3f800000;
        frs2 = 32'h00000000;
        opfp(7'b0001100, 5'd2, 3'b000);
        check32("fdiv.s finite/zero", fp_result, 32'h7f800000);
        check32("fdiv.s DZ", {27'b0, fflags}, 32'h00000008);
        clear_fflags();
        frs1 = 32'h00000000;
        frs2 = 32'h00000000;
        opfp(7'b0001100, 5'd2, 3'b000);
        check32("fdiv.s zero/zero", fp_result, 32'h7fc00000);
        check32("fdiv.s invalid", {27'b0, fflags}, 32'h00000010);
        clear_fflags();
        frs1 = 32'hbf800000;
        opfp(7'b0101100, 5'd0, 3'b000);
        check32("fsqrt.s negative", fp_result, 32'h7fc00000);
        check32("fsqrt.s invalid", {27'b0, fflags}, 32'h00000010);
        clear_fflags();
        frs1 = 32'h00000000;
        frs2 = 32'h7f800000;
        opfp(7'b0001000, 5'd2, 3'b000);
        check32("fmul.s zero*infinity", fp_result, 32'h7fc00000);
        check32("fmul.s invalid", {27'b0, fflags}, 32'h00000010);

        // Signed and unsigned conversion boundaries and rounding.
        frs1 = 32'h3fc00000; // 1.5
        opfp(7'b1100000, 5'd0, 3'b000);
        check32("fcvt.w.s 1.5 RNE", int_result, 32'd2);
        opfp(7'b1100000, 5'd0, 3'b001);
        check32("fcvt.w.s 1.5 RTZ", int_result, 32'd1);
        frs1 = 32'hbf800000;
        opfp(7'b1100000, 5'd1, 3'b000);
        check32("fcvt.wu.s negative", int_result, 32'b0);
        check32("fcvt.wu.s invalid", {27'b0, fflags}, 32'h00000010);
        xrs1 = 32'hffffffff;
        opfp(7'b1101000, 5'd1, 3'b000);
        check32("fcvt.s.wu UINT_MAX", fp_result, 32'h4f800000);

        $display("\nFPU tests: %0d passed, %0d failed", passed, failed);
        if (failed != 0)
            $fatal(1, "FPU testbench failed");
        $display("All FPU tests passed");
        $finish;
    end
endmodule

`default_nettype wire
