`timescale 1ns / 1ps
`default_nettype none

module decoder_tb;

    parameter TRACE_FILE = "../../course_files/phase_2/traces/decoder.trace";

    reg [31:0] i_inst;

    wire        o_legal;
    wire        o_halt;
    wire [4:0]  o_rs1;
    wire [4:0]  o_rs2;
    wire [4:0]  o_rd;
    wire [31:0] o_immediate;
    wire        o_op1_sel;
    wire        o_op2_sel;
    wire [2:0]  o_alu_opsel;
    wire        o_alu_sub;
    wire        o_alu_unsigned;
    wire        o_alu_arith;
    wire        o_branch;
    wire        o_jump;
    wire        o_branch_equal;
    wire        o_branch_unsigned;
    wire        o_branch_invert;
    wire        o_dmem_ren;
    wire        o_dmem_wen;
    wire [1:0]  o_dmem_align;
    wire        o_dmem_memb;
    wire        o_dmem_memh;
    wire        o_dmem_memw;
    wire        o_dmem_memu;
    wire [3:0]  o_rd_sel;
    wire        o_pc_sel;

    integer fd;
    integer rc;
    integer passed;
    integer failed;
    integer data_count;

    reg        e_legal;
    reg        e_halt;
    reg [4:0]  e_rs1;
    reg [4:0]  e_rs2;
    reg [4:0]  e_rd;
    reg [31:0] e_immediate;
    reg        e_op1_sel;
    reg        e_op2_sel;
    reg [2:0]  e_alu_opsel;
    reg        e_alu_sub;
    reg        e_alu_unsigned;
    reg        e_alu_arith;
    reg        e_branch;
    reg        e_jump;
    reg        e_branch_equal;
    reg        e_branch_unsigned;
    reg        e_branch_invert;
    reg        e_dmem_ren;
    reg        e_dmem_wen;
    reg [1:0]  e_dmem_align;
    reg        e_dmem_memb;
    reg        e_dmem_memh;
    reg        e_dmem_memw;
    reg        e_dmem_memu;
    reg [3:0]  e_rd_sel;
    reg        e_pc_sel;

    // The decoder trace uses 'x' for don't-care outputs. A trace field
    // containing any X is therefore ignored for that field.
    function automatic match32;
        input [31:0] actual;
        input [31:0] expected;
        begin
            if (^expected === 1'bx)
                match32 = 1'b1;
            else
                match32 = (actual === expected);
        end
    endfunction

    function automatic match5;
        input [4:0] actual;
        input [4:0] expected;
        begin
            if (^expected === 1'bx)
                match5 = 1'b1;
            else
                match5 = (actual === expected);
        end
    endfunction

    function automatic match4;
        input [3:0] actual;
        input [3:0] expected;
        begin
            if (^expected === 1'bx)
                match4 = 1'b1;
            else
                match4 = (actual === expected);
        end
    endfunction

    function automatic match3;
        input [2:0] actual;
        input [2:0] expected;
        begin
            if (^expected === 1'bx)
                match3 = 1'b1;
            else
                match3 = (actual === expected);
        end
    endfunction

    function automatic match2;
        input [1:0] actual;
        input [1:0] expected;
        begin
            if (^expected === 1'bx)
                match2 = 1'b1;
            else
                match2 = (actual === expected);
        end
    endfunction

    function automatic match1;
        input actual;
        input expected;
        begin
            if (expected === 1'bx)
                match1 = 1'b1;
            else
                match1 = (actual === expected);
        end
    endfunction

    decoder dut (
        .i_inst            (i_inst),
        .o_legal           (o_legal),
        .o_halt            (o_halt),
        .o_rs1             (o_rs1),
        .o_rs2             (o_rs2),
        .o_rd              (o_rd),
        .o_immediate       (o_immediate),
        .o_op1_sel         (o_op1_sel),
        .o_op2_sel         (o_op2_sel),
        .o_alu_opsel       (o_alu_opsel),
        .o_alu_sub         (o_alu_sub),
        .o_alu_unsigned    (o_alu_unsigned),
        .o_alu_arith       (o_alu_arith),
        .o_branch          (o_branch),
        .o_jump            (o_jump),
        .o_branch_equal    (o_branch_equal),
        .o_branch_unsigned (o_branch_unsigned),
        .o_branch_invert   (o_branch_invert),
        .o_dmem_ren        (o_dmem_ren),
        .o_dmem_wen        (o_dmem_wen),
        .o_dmem_align      (o_dmem_align),
        .o_dmem_memb       (o_dmem_memb),
        .o_dmem_memh       (o_dmem_memh),
        .o_dmem_memw       (o_dmem_memw),
        .o_dmem_memu       (o_dmem_memu),
        .o_rd_sel          (o_rd_sel),
        .o_pc_sel          (o_pc_sel)
    );

    initial begin
        $dumpfile("decoder_trace_tb.vcd");
        $dumpvars(0, decoder_tb);

        passed = 0;
        failed = 0;
        data_count = 0;

        fd = $fopen(TRACE_FILE, "r");
        if (fd == 0) begin
            $display("ERROR: Could not open %0s", TRACE_FILE);
            $finish;
        end

        $display("========== DECODER trace testbench ==========");
        $display("Trace: %0s", TRACE_FILE);

        while (!$feof(fd)) begin
            rc = $fscanf(fd,
                "%h %b %b %h %h %h %h %b %b %b %b %b %b %b %b %b %b %b %b %b %h %b %b %b %b %b %h %b\n",
                i_inst,
                e_legal,
                e_halt,
                e_rs1,
                e_rs2,
                e_rd,
                e_immediate,
                e_op1_sel,
                e_op2_sel,
                e_alu_opsel,
                e_alu_sub,
                e_alu_unsigned,
                e_alu_arith,
                e_branch,
                e_jump,
                e_branch_equal,
                e_branch_unsigned,
                e_branch_invert,
                e_dmem_ren,
                e_dmem_wen,
                e_dmem_align,
                e_dmem_memb,
                e_dmem_memh,
                e_dmem_memw,
                e_dmem_memu,
                e_rd_sel,
                e_pc_sel
            );

            if (rc == 27) begin
                data_count = data_count + 1;
                #1;

                if (match1(o_legal,e_legal) &&
                    match1(o_halt,e_halt) &&
                    match5(o_rs1,e_rs1) &&
                    match5(o_rs2,e_rs2) &&
                    match5(o_rd,e_rd) &&
                    match32(o_immediate,e_immediate) &&
                    match1(o_op1_sel,e_op1_sel) &&
                    match1(o_op2_sel,e_op2_sel) &&
                    match3(o_alu_opsel,e_alu_opsel) &&
                    match1(o_alu_sub,e_alu_sub) &&
                    match1(o_alu_unsigned,e_alu_unsigned) &&
                    match1(o_alu_arith,e_alu_arith) &&
                    match1(o_branch,e_branch) &&
                    match1(o_jump,e_jump) &&
                    match1(o_branch_equal,e_branch_equal) &&
                    match1(o_branch_unsigned,e_branch_unsigned) &&
                    match1(o_branch_invert,e_branch_invert) &&
                    match1(o_dmem_ren,e_dmem_ren) &&
                    match1(o_dmem_wen,e_dmem_wen) &&
                    match2(o_dmem_align,e_dmem_align) &&
                    match1(o_dmem_memb,e_dmem_memb) &&
                    match1(o_dmem_memh,e_dmem_memh) &&
                    match1(o_dmem_memw,e_dmem_memw) &&
                    match1(o_dmem_memu,e_dmem_memu) &&
                    match4(o_rd_sel,e_rd_sel) &&
                    match1(o_pc_sel,e_pc_sel)) begin
                    passed = passed + 1;
                end else begin
                    failed = failed + 1;
                    $display("[FAIL] vector %0d inst=%h", data_count, i_inst);
                    $display("       legal=%b exp=%b halt=%b exp=%b",
                             o_legal,e_legal,o_halt,e_halt);
                    $display("       rs1=%h exp=%h rs2=%h exp=%h rd=%h exp=%h",
                             o_rs1,e_rs1,o_rs2,e_rs2,o_rd,e_rd);
                    $display("       immediate=%h exp=%h",
                             o_immediate,e_immediate);
                    $display("       op1=%b/%b op2=%b/%b alu=%b/%b sub=%b/%b unsigned=%b/%b arith=%b/%b",
                             o_op1_sel,e_op1_sel,o_op2_sel,e_op2_sel,
                             o_alu_opsel,e_alu_opsel,o_alu_sub,e_alu_sub,
                             o_alu_unsigned,e_alu_unsigned,o_alu_arith,e_alu_arith);
                    $display("       branch=%b/%b jump=%b/%b beq=%b/%b bu=%b/%b inv=%b/%b",
                             o_branch,e_branch,o_jump,e_jump,
                             o_branch_equal,e_branch_equal,
                             o_branch_unsigned,e_branch_unsigned,
                             o_branch_invert,e_branch_invert);
                    $display("       ren=%b/%b wen=%b/%b align=%b/%b",
                             o_dmem_ren,e_dmem_ren,o_dmem_wen,e_dmem_wen,
                             o_dmem_align,e_dmem_align);
                    $display("       memb=%b/%b memh=%b/%b memw=%b/%b memu=%b/%b",
                             o_dmem_memb,e_dmem_memb,o_dmem_memh,e_dmem_memh,
                             o_dmem_memw,e_dmem_memw,o_dmem_memu,e_dmem_memu);
                    $display("       rd_sel=%h/%h pc_sel=%b/%b",
                             o_rd_sel,e_rd_sel,o_pc_sel,e_pc_sel);
                end
            end
        end

        $fclose(fd);

        $display("---------------------------------------------");
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
