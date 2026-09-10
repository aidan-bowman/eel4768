`timescale 1ns / 1ps
`default_nettype none

module decoder_tb;

    reg  [31:0] inst;

    wire        legal;
    wire        halt;
    wire [4:0]  rs1;
    wire [4:0]  rs2;
    wire [4:0]  rd;
    wire [31:0] immediate;
    wire        op1_sel;
    wire        op2_sel;
    wire [2:0]  alu_opsel;
    wire        alu_sub;
    wire        alu_unsigned;
    wire        alu_arith;
    wire        branch;
    wire        jump;
    wire        branch_equal;
    wire        branch_unsigned;
    wire        branch_invert;
    wire        dmem_ren;
    wire        dmem_wen;
    wire [1:0]  dmem_align;
    wire        dmem_memb;
    wire        dmem_memh;
    wire        dmem_memw;
    wire        dmem_memu;
    wire [3:0]  rd_sel;
    wire        pc_sel;

    integer passed;
    integer failed;

    decoder dut (
        .i_inst            (inst),
        .o_legal           (legal),
        .o_halt            (halt),
        .o_rs1             (rs1),
        .o_rs2             (rs2),
        .o_rd              (rd),
        .o_immediate       (immediate),
        .o_op1_sel         (op1_sel),
        .o_op2_sel         (op2_sel),
        .o_alu_opsel       (alu_opsel),
        .o_alu_sub         (alu_sub),
        .o_alu_unsigned    (alu_unsigned),
        .o_alu_arith       (alu_arith),
        .o_branch          (branch),
        .o_jump            (jump),
        .o_branch_equal    (branch_equal),
        .o_branch_unsigned (branch_unsigned),
        .o_branch_invert   (branch_invert),
        .o_dmem_ren        (dmem_ren),
        .o_dmem_wen        (dmem_wen),
        .o_dmem_align      (dmem_align),
        .o_dmem_memb       (dmem_memb),
        .o_dmem_memh       (dmem_memh),
        .o_dmem_memw       (dmem_memw),
        .o_dmem_memu       (dmem_memu),
        .o_rd_sel          (rd_sel),
        .o_pc_sel          (pc_sel)
    );

    task check;
        input [511:0] label;
        input         e_legal;
        input         e_halt;
        input [4:0]   e_rs1;
        input [4:0]   e_rs2;
        input [4:0]   e_rd;
        input [31:0]  e_imm;
        input         e_op1_sel;
        input         e_op2_sel;
        input [2:0]   e_alu_opsel;
        input         e_alu_sub;
        input         e_branch;
        input         e_jump;
        input         e_ren;
        input         e_wen;
        input [3:0]   e_rd_sel;
        input         e_pc_sel;
        begin
            #1;
            if (legal === e_legal &&
                halt === e_halt &&
                rs1 === e_rs1 &&
                rs2 === e_rs2 &&
                rd === e_rd &&
                immediate === e_imm &&
                op1_sel === e_op1_sel &&
                op2_sel === e_op2_sel &&
                alu_opsel === e_alu_opsel &&
                alu_sub === e_alu_sub &&
                branch === e_branch &&
                jump === e_jump &&
                dmem_ren === e_ren &&
                dmem_wen === e_wen &&
                rd_sel === e_rd_sel &&
                pc_sel === e_pc_sel) begin
                passed = passed + 1;
                $display("[PASS] %0s", label);
            end else begin
                failed = failed + 1;
                $display("[FAIL] %0s", label);
                $display("       inst=%h", inst);
                $display("       legal=%b/%b halt=%b/%b rs1=%0d/%0d rs2=%0d/%0d rd=%0d/%0d",
                         legal,e_legal,halt,e_halt,rs1,e_rs1,rs2,e_rs2,rd,e_rd);
                $display("       imm=%h/%h op1_sel=%b/%b op2_sel=%b/%b alu=%b/%b sub=%b/%b",
                         immediate,e_imm,op1_sel,e_op1_sel,op2_sel,e_op2_sel,
                         alu_opsel,e_alu_opsel,alu_sub,e_alu_sub);
                $display("       branch=%b/%b jump=%b/%b ren=%b/%b wen=%b/%b rd_sel=%b/%b pc_sel=%b/%b",
                         branch,e_branch,jump,e_jump,dmem_ren,e_ren,dmem_wen,e_wen,
                         rd_sel,e_rd_sel,pc_sel,e_pc_sel);
            end
        end
    endtask

    initial begin
        $dumpfile("decoder_tb.vcd");
        $dumpvars(0, decoder_tb);

        passed = 0;
        failed = 0;

        $display("========== DECODER testbench ==========");

        // add x5,x6,x7
        inst = 32'h007302b3;
        check("R-type ADD", 1,0,6,7,5,0,0,0,3'b000,0,0,0,0,0,4'b0001,0);

        // sub x5,x6,x7
        inst = 32'h407302b3;
        check("R-type SUB", 1,0,6,7,5,0,0,0,3'b000,1,0,0,0,0,4'b0001,0);

        // xori x5,x5,-1
        inst = 32'hfff2c293;
        check("I-type XORI", 1,0,5,0,5,32'hffff_ffff,0,1,3'b100,0,0,0,0,0,4'b0001,0);

        // lui x5,0x12345
        inst = 32'h123452b7;
        check("LUI", 1,0,0,0,5,32'h1234_5000,0,1,3'b000,0,0,0,0,0,4'b0010,0);

        // auipc x5,0x12345
        inst = 32'h12345297;
        check("AUIPC", 1,0,0,0,5,32'h1234_5000,1,1,3'b000,0,0,0,0,0,4'b0001,0);

        // lw x5,8(x6)
        inst = 32'h00832283;
        check("LW", 1,0,6,0,5,32'd8,0,1,3'b000,0,0,0,1,0,4'b1000,0);

        // sw x5,8(x6)
        inst = 32'h00532423;
        check("SW", 1,0,6,5,0,32'd8,0,1,3'b000,0,0,0,0,1,4'b0000,0);

        // beq x5,x6,+16
        inst = 32'h00628863;
        check("BEQ", 1,0,5,6,0,32'd16,0,0,3'b000,0,1,0,0,0,4'b0000,0);

        // jal x5,+16
        inst = 32'h010002ef;
        check("JAL", 1,0,0,0,5,32'd16,1,1,3'b000,0,0,1,0,0,4'b0100,0);

        // jalr x5,12(x6)
        inst = 32'h00c302e7;
        check("JALR", 1,0,6,0,5,32'd12,0,1,3'b000,0,0,1,0,0,4'b0100,1);

        // ebreak
        inst = 32'h00100073;
        check("EBREAK", 0,1,0,0,0,0,0,1,3'b000,0,0,0,0,0,4'b0000,0);

        $display("=======================================");
        $display("%0d passed, %0d failed", passed, failed);
        if (failed == 0) $display("ALL TESTS PASSED");
        else             $display("TEST FAILED");
        $finish;
    end

endmodule

`default_nettype wire
