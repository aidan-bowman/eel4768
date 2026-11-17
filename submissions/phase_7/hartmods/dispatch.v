`default_nettype none

/* DISPATCH
 *
 * In-order decode stage plus the ID/EX pipeline register.
 *
 * Inputs:  PC, instruction, and bubble flag from fetch; stall from hazard
 *          control; register-file write from commit.
 * Outputs: decoded control, register addresses, immediates, and the values
 *          read from the register file, captured for the reorder buffer.
 *          o_stall is tied low; this stage has nothing of its own to wait on.
 *
 * i_stall holds the pipeline register. i_nop (a fetch bubble) clears it, so
 * the bubble is neither legal nor a trap. A real `addi x0, x0, 0` in the
 * program has i_nop low and is decoded normally.
 *
 * Limitations: branch and jump targets are not computed here. Integer writes
 * are suppressed by the caller driving i_rd_waddr to 5'd0; FP writes are
 * suppressed with i_frd_wen low. The phase 6 legal/halt/trap write gate is
 * not repeated. Commit must still write while this stage is stalled.
 */
module dispatch
  #(
    parameter BYPASS_EN = 1
    )
    (
     input wire        i_clk,
     input wire        i_rst,

     // CPU
     // hazard control
     input wire        i_stall, // high when hazardctrl needs us to stall
     output wire       o_stall, // output high when WE need to stall

     // from fetch
     input wire [31:0] i_pc,
     input wire [31:0] i_instr,
     input wire        i_nop,

     // register file write, from commit
     input wire [4:0]  i_rd_waddr,
     input wire [31:0] i_rd_wdata,
     input wire        i_frd_wen,
     input wire [4:0]  i_frd_waddr,
     input wire [31:0] i_frd_wdata,

     // to reorder buffer (ID/EX)
     output reg [31:0] o_pc,
     output reg [31:0] o_instr,
     output reg        o_nop,

     output reg [31:0] o_rs1_data,
     output reg [31:0] o_rs2_data,
     output reg [4:0]  o_rs1,
     output reg [4:0]  o_rs2,
     output reg [31:0] o_imm,

     output reg [4:0]  o_rd,
     output reg [2:0]  o_alu_opsel,
     output reg        o_alu_sub,
     output reg        o_alu_unsigned,
     output reg        o_alu_arith,
     output reg        o_mext,

     output reg        o_op1_pc_sel,
     output reg        o_op2_imm_sel,

     output reg        o_branch,
     output reg        o_branch_equal,
     output reg        o_branch_unsigned,
     output reg        o_branch_invert,

     output reg        o_jump,
     output reg        o_pc_alu_sel,

     output reg        o_memread,
     output reg        o_memwrite,
     output reg [1:0]  o_memalign,
     output reg        o_memb,
     output reg        o_memh,
     output reg        o_memw,
     output reg        o_memu,

     output reg [4:0]  o_rd_sel,

     output reg        o_legal,
     output reg        o_halt,
     output reg        o_trap,

     output reg [31:0] o_frs1_data,
     output reg [31:0] o_frs2_data,
     output reg [31:0] o_frs3_data,

     output reg [4:0]  o_frs1,
     output reg [4:0]  o_frs2,
     output reg [4:0]  o_frs3,

     output reg        o_frs1_en,
     output reg        o_frs2_en,
     output reg        o_frs3_en,

     output reg        o_fpu_en,

     output reg        o_frd_en,
     output reg [4:0]  o_frd
     );

    // =============================================================
    // Main logic
    // =============================================================

    wire        legal;
    wire        halt;

    wire [4:0]  rs1;
    wire [4:0]  rs2;
    wire [4:0]  rd;
    wire [31:0] imm;

    wire        op1_pc_sel;
    wire        op2_imm_sel;

    wire [2:0]  alu_opsel;
    wire        alu_sub;
    wire        alu_unsigned;
    wire        alu_arith;

    wire        inst_branch;
    wire        inst_jump;

    wire        branch_equal;
    wire        branch_unsigned;
    wire        branch_invert;

    wire        memread;
    wire        memwrite;
    wire [1:0]  memalign;
    wire        memb;
    wire        memh;
    wire        memw;
    wire        memu;

    wire [4:0]  rd_sel;
    wire        pc_alu_sel;
    wire        mext;

    wire        fpu_en;
    wire        frs1_en;
    wire        frs2_en;
    wire        frs3_en;
    wire [4:0]  rs3;
    wire        frd_en;

    wire [31:0] rs1_data;
    wire [31:0] rs2_data;
    wire [31:0] frs1_data;
    wire [31:0] frs2_data;
    wire [31:0] frs3_data;

    decoder decoder (
                     .i_inst(i_instr),

                     .o_legal(legal),
                     .o_halt(halt),

                     .o_rs1(rs1),
                     .o_rs2(rs2),
                     .o_rd(rd),

                     .o_immediate(imm),

                     .o_op1_sel(op1_pc_sel),
                     .o_op2_sel(op2_imm_sel),

                     .o_alu_opsel(alu_opsel),
                     .o_alu_sub(alu_sub),
                     .o_alu_unsigned(alu_unsigned),
                     .o_alu_arith(alu_arith),

                     .o_branch(inst_branch),
                     .o_jump(inst_jump),

                     .o_branch_equal(branch_equal),
                     .o_branch_unsigned(branch_unsigned),
                     .o_branch_invert(branch_invert),

                     .o_dmem_ren(memread),
                     .o_dmem_wen(memwrite),

                     .o_dmem_memb(memb),
                     .o_dmem_memh(memh),
                     .o_dmem_memw(memw),
                     .o_dmem_memu(memu),

                     .o_dmem_align(memalign),

                     .o_rd_sel(rd_sel),

                     .o_pc_sel(pc_alu_sel),

                     .o_mext(mext),
                     .o_fpu(fpu_en),

                     .o_frs1_en(frs1_en),
                     .o_frs2_en(frs2_en),
                     .o_frs3_en(frs3_en),

                     .o_rs3(rs3),
                     .o_frd_en(frd_en)
                     );

    // FP addresses come from the instruction fields. decoder o_rs1/o_rs2 are
    // the integer ports and are 0 for most floating-point ops. Phase 6 read
    // the FP file from these same fields.
    rf #(
         .BYPASS_EN(BYPASS_EN)
         ) rf (
               .i_clk(i_clk),
               .i_rst(i_rst),

               .i_rs1_raddr(rs1),
               .o_rs1_rdata(rs1_data),

               .i_rs2_raddr(rs2),
               .o_rs2_rdata(rs2_data),

               .i_frs1_raddr(i_instr[19:15]),
               .o_frs1_rdata(frs1_data),

               .i_frs2_raddr(i_instr[24:20]),
               .o_frs2_rdata(frs2_data),

               .i_frs3_raddr(rs3),
               .o_frs3_rdata(frs3_data),

               .i_frd_wen(i_frd_wen),
               .i_frd_waddr(i_frd_waddr),
               .i_frd_wdata(i_frd_wdata),

               .i_rd_waddr(i_rd_waddr),
               .i_rd_wdata(i_rd_wdata)
               );

    assign o_stall = 1'b0;

    // =============================================================
    // ID/EX reg
    // =============================================================

    always @(posedge i_clk) begin
        if (i_rst || (!i_stall && i_nop)) begin
            o_pc              <= 32'b0;
            o_instr           <= 32'b0;
            o_nop             <= 1'b1;
            o_rs1_data        <= 32'b0;
            o_rs2_data        <= 32'b0;
            o_rs1             <= 5'd0;
            o_rs2             <= 5'd0;
            o_imm             <= 32'b0;
            o_rd              <= 5'd0;
            o_alu_opsel       <= 3'b0;
            o_alu_sub         <= 1'b0;
            o_alu_unsigned    <= 1'b0;
            o_alu_arith       <= 1'b0;
            o_mext            <= 1'b0;
            o_op1_pc_sel      <= 1'b0;
            o_op2_imm_sel     <= 1'b0;
            o_branch          <= 1'b0;
            o_branch_equal    <= 1'b0;
            o_branch_unsigned <= 1'b0;
            o_branch_invert   <= 1'b0;
            o_jump            <= 1'b0;
            o_pc_alu_sel      <= 1'b0;
            o_memread         <= 1'b0;
            o_memwrite        <= 1'b0;
            o_memalign        <= 2'b0;
            o_memb            <= 1'b0;
            o_memh            <= 1'b0;
            o_memw            <= 1'b0;
            o_memu            <= 1'b0;
            o_rd_sel          <= 5'b0;
            o_legal           <= 1'b0;
            o_halt            <= 1'b0;
            o_trap            <= 1'b0;

            o_frs1_data       <= 32'b0;
            o_frs2_data       <= 32'b0;
            o_frs3_data       <= 32'b0;

            o_frs1            <= 5'b0;
            o_frs2            <= 5'b0;
            o_frs3            <= 5'b0;

            o_frs1_en         <= 1'b0;
            o_frs2_en         <= 1'b0;
            o_frs3_en         <= 1'b0;

            o_fpu_en          <= 1'b0;

            o_frd_en          <= 1'b0;
            o_frd             <= 5'b0;
        end else if (!i_stall) begin
            o_pc              <= i_pc;
            o_instr           <= i_instr;
            o_nop             <= 1'b0;
            o_rs1_data        <= rs1_data;
            o_rs2_data        <= rs2_data;
            o_rs1             <= rs1;
            o_rs2             <= rs2;
            o_imm             <= imm;
            o_rd              <= rd;
            o_alu_opsel       <= alu_opsel;
            o_alu_sub         <= alu_sub;
            o_alu_unsigned    <= alu_unsigned;
            o_alu_arith       <= alu_arith;
            o_mext            <= mext;
            o_op1_pc_sel      <= op1_pc_sel;
            o_op2_imm_sel     <= op2_imm_sel;
            o_branch          <= inst_branch;
            o_branch_equal    <= branch_equal;
            o_branch_unsigned <= branch_unsigned;
            o_branch_invert   <= branch_invert;
            o_jump            <= inst_jump;
            o_pc_alu_sel      <= pc_alu_sel;
            o_memread         <= memread;
            o_memwrite        <= memwrite;
            o_memalign        <= memalign;
            o_memb            <= memb;
            o_memh            <= memh;
            o_memw            <= memw;
            o_memu            <= memu;
            o_rd_sel          <= rd_sel;
            o_legal           <= legal;
            o_halt            <= halt;
            o_trap            <= !legal;

            o_frs1_data       <= frs1_data;
            o_frs2_data       <= frs2_data;
            o_frs3_data       <= frs3_data;

            // Match the addresses the FP file was actually read with.
            o_frs1            <= frs1_en ? i_instr[19:15] : 5'd0;
            o_frs2            <= frs2_en ? i_instr[24:20] : 5'd0;
            o_frs3            <= frs3_en ? rs3 : 5'd0;

            o_frs1_en         <= frs1_en;
            o_frs2_en         <= frs2_en;
            o_frs3_en         <= frs3_en;

            o_fpu_en          <= fpu_en;

            o_frd_en          <= frd_en;
            o_frd             <= frd_en ? i_instr[11:7] : 5'd0;
        end
    end

endmodule // dispatch
