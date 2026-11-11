`default_nettype none

module decoder (
                // Input instruction word.
                input wire [31:0]  i_inst,
                // Asserted if the instruction was decoded as a legal instruction. It is
                // important that the decoder not accept any illegal instruction
                // encodings as this could lead to undefined behavior in the processor
                // which is a safety hazard.
                output wire        o_legal,
                // Indicates that the instruction is an ebreak and should halt execution.
                output wire        o_halt,
                // First source register address.
                // For instructions that do not use a source register, this is effectively
                // a don't care because reading unused registers does not have any side
                // effects (and we don't care about power usage, really).
                output wire [ 4:0] o_rs1,
                // Second source register address.
                // Similarly to o_rs1, this is a don't care for instructions that do not
                // read a (second) source register.
                output wire [ 4:0] o_rs2,
                // Destination register address.
                // For instructions that do not write to a register, this must be set to
                // x0 so the value is discarded. This avoids the need for a separate write
                // enable since discard behavior must be present anyway.
                output wire [ 4:0] o_rd,
                // 32-bit immediate value, decoded from the instruction word. For R-type
                // instructions that do not use an immediate, this is a don't care.
                output wire [31:0] o_immediate,
                // Selects whether the first operand for the ALU is fed by the first
                // register source (rs1) or the current pc.
                // When asserted, the second operand is the immediate.
                output wire        o_op1_sel,
                // Selects whether the second operand for the ALU is fed by the second
                // register source (rs2) or the immediate.
                // When asserted, the second operand is the immediate.
                output wire        o_op2_sel,
                // Major opsel for the ALU. See ALU documentation for the encoding.
                output wire [ 2:0] o_alu_opsel,
                // Minor opsel flags for the ALU. See ALU documentation for the encoding.
                output wire        o_alu_sub,
                output wire        o_alu_unsigned,
                output wire        o_alu_arith,
                // If asserted, the instruction is a branch instruction and the PC should
                // be updated to the target address if the branch condition is met.
                output wire        o_branch,
                // If asserted, the instruction is a jump instruction and the PC should
                // be updated to the target address unconditionally.
                output wire        o_jump,
                // When asserted, the branch comparator checks for equality. When not
                // asserted, it checks for less than [unsigned].
                output wire        o_branch_equal,
                // When asserted, the branch comparator treats the less than comparison
                // operands as unsigned. This is only used when `!o_branch_equal`.
                output wire        o_branch_unsigned,
                // When asserted, the branch condition is inverted.
                // Equality -> inequality, less than -> greater than or equal.
                output wire        o_branch_invert,
                // When asserted, the instruction will load from memory.
                output wire        o_dmem_ren,
                // When asserted, the instruction will store to memory.
                output wire        o_dmem_wen,
                // This 2-bit mask selects which LSBs of the memory address should be
                // checked for alignment. This is because byte and half-word accesses need
                // only be 1-byte and 2-byte aligned, respectively.
                output wire [ 1:0] o_dmem_align,
                // These 3 bits select the size of the memory access.
                // They are effectively one-hot encoded.
                output wire        o_dmem_memb,
                output wire        o_dmem_memh,
                output wire        o_dmem_memw,
                // If asserted, the (byte or half-word) memory access is unsigned and the
                // load should be zero-extended to 32 bits instead of sign-extended.
                output wire        o_dmem_memu,
                // Selects the data to write to the destination register, one-hot.
                // [0] = ALU result (including the RV32M multiply/divide result)
                // [1] = immediate
                // [2] = PC + 4
                // [3] = memory
                // [4] = floating-point unit integer result (F extension): fmv.x.w,
                //       fclass.s, feq/flt/fle.s, fcvt.w[u].s, and the old CSR value
                //       for the CSR instructions.
                output wire [ 4:0] o_rd_sel,
                // Asserted for the RV32M instructions (OP opcode, func7 = 0000001).
                // The ALU then performs the multiply/divide operation selected by
                // `o_alu_opsel` (the instruction's func3).
                output wire        o_mext,
                // F extension. The floating-point unit decodes the details of its own
                // instructions (func7, rs2, rm) from the instruction word; the decoder
                // only reports legality and which register file each operand uses.
                //
                // Asserted for instructions executed by the floating-point unit: every
                // OP-FP and fused multiply-add instruction, and the CSR instructions on
                // fflags/frm/fcsr. flw/fsw are ordinary memory accesses and are not
                // included.
                output wire        o_fpu,
                // Asserted when the instruction reads floating-point rs1/rs2/rs3. The
                // register addresses are the usual `o_rs1`/`o_rs2` fields, plus `o_rs3`
                // (bits [31:27]) for the fused multiply-add instructions.
                output wire        o_frs1_en,
                output wire        o_frs2_en,
                output wire        o_frs3_en,
                output wire [ 4:0] o_rs3,
                // Asserted when the instruction writes floating-point register rd
                // (bits [11:7]). For these instructions `o_rd` is 5'd0, since they do
                // not write the integer register file.
                output wire        o_frd_en,
                // If asserted, the PC jumps to the target address calculated by the ALU
                // rather than directly to the PC + immediate. This is used for JALR.
                output wire        o_pc_sel
                );

    wire [7:0] opcode = i_inst[6:0];
    wire [2:0] func3 = i_inst[14:12];
    wire [6:0] func7 = i_inst[31:25];
    wire [4:0] rs2_field = i_inst[24:20];

    // Opcode Decoding
    wire is_arr       = (opcode == 7'b0110011);
    wire is_arr_imm   = (opcode == 7'b0010011);
    wire is_load      = (opcode == 7'b0000011);
    wire is_lui       = (opcode == 7'b0110111);
    wire is_auipc     = (opcode == 7'b0010111);
    wire is_store     = (opcode == 7'b0100011);
    wire is_branch    = (opcode == 7'b1100011);
    wire is_jal       = (opcode == 7'b1101111);
    wire is_jalr      = (opcode == 7'b1100111);
    wire is_system    = (opcode == 7'b1110011);

    wire is_load_fp   = (opcode == 7'b0000111);
    wire is_store_fp  = (opcode == 7'b0100111);
    wire is_op_fp     = (opcode == 7'b1010011);

    wire is_madd      = (opcode == 7'b1000011);
    wire is_msub      = (opcode == 7'b1000111);
    wire is_nmsub     = (opcode == 7'b1001011);
    wire is_nmadd     = (opcode == 7'b1001111);

    wire is_fused     = is_madd | is_msub | is_nmsub | is_nmadd;

    wire is_mext      = is_arr && (func7 == 7'b0000001);
    assign o_mext = is_mext;
    
    wire [5:0] format =
               (is_arr | is_system)              ? 6'b000001 :
               (is_arr_imm | is_load | is_jalr |
                is_load_fp)                      ? 6'b000010 :
               (is_store | is_store_fp)          ? 6'b000100 :
               (is_branch)                       ? 6'b001000 :
               (is_lui | is_auipc)               ? 6'b010000 :
               (is_jal)                          ? 6'b100000 : 6'b000000;

    wire       valid_arr = 
               (func7 == 7'b0000000) |
               (((func3 == 3'b000) |
                 (func3 == 3'b101)) &&
                (func7 == 7'b0100000)) |
               (func7 == 7'b0000001);
    
    wire       valid_arr_imm    = (func3 == 3'b001) ? (func7 == 7'b0000000) :
               (func3 == 3'b101) ? (~i_inst[31] && (i_inst[29:25] == 5'b00000)) :
               1;    
    wire       valid_load      = ~((func3 == 3'b011) | (func3 == 3'b110) | (func3 == 3'b111));
    wire       valid_store     = (func3 == 3'b000) | (func3 == 3'b001) | (func3 == 3'b010);
    wire       valid_branch    = ~((func3 == 3'b010) | (func3 == 3'b011));


    wire       valid_rm        = (func3 != 3'b101) &&
               (func3 != 3'b110);
    
    wire       valid_op_fp     = 
                              // fadd.s, fsub.s, fmul.s, fdiv.s
               (((func7 == 7'b0000000) ||
                 (func7 == 7'b0000100) ||
                 (func7 == 7'b0001000) ||
                 (func7 == 7'b0001100)) && valid_rm) |
                              // fsqrt.s
               ((func7 == 7'b0101100) &&
                (rs2_field == 5'b00000) && valid_rm) |
                              // fsgnj.s, fsgnjn.s, fsgnjx.s
               ((func7 == 7'b0010000) &&
                (func3 <= 3'b010)) |
                              // fmin.s, fmax.s
               ((func7 == 7'b0010100) &&
                (func3 <= 3'b001)) |
                              // fle.s, flt.s, feq.s
               ((func7 == 7'b1010000) &&
                (func3 <= 3'b010)) |
                              // fclass.s
               ((func7 == 7'b1110000) &&
                (func3 == 3'b001) &&
                (rs2_field == 5'b00000)) |
                              // fmv.x.w
               ((func7 == 7'b1110000) &&
                (func3 == 3'b000) &&
                (rs2_field == 5'b00000)) |
                              // fcvt.w.s, fcvt.wu.s
               ((func7 == 7'b1100000) &&
                ((rs2_field == 5'b00000) ||
                 (rs2_field == 5'b00001)) && valid_rm) |
                              // fcvt.s.w, fcvt.s.wu
               ((func7 == 7'b1101000) &&
                ((rs2_field == 5'b00000) ||
                 (rs2_field == 5'b00001)) && valid_rm) |
                              // fmv.w.x
               ((func7 == 7'b1111000) &&
                (rs2_field == 5'b00000) &&
                (func3 == 3'b000));
    
    wire       valid_fused     = (i_inst[26:25] == 2'b00);
    wire       valid_load_fp   = (func3 == 3'b010);
    wire       valid_store_fp  = (func3 == 3'b010);

    wire       is_csr          = is_system &&
               (func3 != 3'b000) &&
               (func3 != 3'b100);

    wire       valid_csr       = 
               (i_inst[31:20] == 12'h001) ||
               (i_inst[31:20] == 12'h002) ||
               (i_inst[31:20] == 12'h003);

    wire       valid_system    = is_csr && valid_csr;
    

    assign o_halt  = (i_inst == 32'h00100073);
    
    assign o_legal = (is_arr & valid_arr) |
                     (is_arr_imm & valid_arr_imm) |
                     (is_load & valid_load) |
                     is_lui |
                     is_auipc |
                     (is_store & valid_store) |
                     (is_branch & valid_branch) |
                     is_jal |
                     (is_jalr & (func3 == 3'b000)) |
                     (is_load_fp & valid_load_fp) |
                     (is_store_fp & valid_store_fp) |
                     (is_op_fp & valid_op_fp) |
                     (is_fused & valid_fused) |
                     valid_system |
                     o_halt;
    
    
    

    // rs1, rs2, and rd are always in the same place
    assign o_rd = (is_arr | is_arr_imm | is_load |
                  is_lui | is_auipc | is_jal | is_jalr |
                  is_csr | int_fp_result)
      ? i_inst[11:7] : 5'd0;

    assign o_rs1 = (is_arr | is_arr_imm | is_load |
                   is_store | is_branch | is_load_fp |
                   is_store_fp)
      ? i_inst[19:15] :
                  (is_op_fp &&
                   ((func7 == 7'b1101000) ||
                    (func7 == 7'b1111000)))
        ? i_inst[19:15] :
                  (is_csr && !i_inst[14])
          ? i_inst[19:15] :
                  5'd0;

    assign o_rs2 = (is_arr | is_store | is_branch)
      ? i_inst[24:20] :
                  (is_store_fp)
        ? i_inst[24:20] :
                  5'd0;
    
    imm imm (.i_inst      (i_inst),
             .i_format    (format),
             .o_immediate (o_immediate)
             );

    assign o_op1_sel      = is_auipc | is_jal;
    assign o_op2_sel      = ~(is_arr | is_branch);
    assign o_alu_opsel    = (is_arr | is_arr_imm | is_branch) ? func3 : 3'b000; // func3 if we're arithmetic or branch, or addition for other ops
    assign o_alu_sub      = is_arr & (func3 == 3'b000) & i_inst[30];
    assign o_alu_unsigned = ((is_arr | is_arr_imm) & (func3 == 3'b011)) | (is_branch & i_inst[13]);
    assign o_alu_arith    = (is_arr | is_arr_imm) & (func3 == 3'b101) & i_inst[30]; // ditto

    assign o_branch = is_branch;
    assign o_jump   = is_jal | is_jalr;
    
    assign o_branch_equal    = ~i_inst[14];
    assign o_branch_unsigned = i_inst[13];
    assign o_branch_invert   = i_inst[12];
    
    assign o_dmem_ren = is_load | is_load_fp;
    assign o_dmem_wen = is_store | is_store_fp;
    assign o_dmem_memb  = ~(i_inst[13] | i_inst[12]);
    assign o_dmem_memh  = i_inst[12];
    assign o_dmem_memw  = i_inst[13];
    assign o_dmem_align = {o_dmem_memw, ~o_dmem_memb};
    assign o_dmem_memu  = i_inst[14];
    
    assign o_rd_sel =
                     (is_arr | is_arr_imm | is_auipc) ? 5'b00001 :
                     (is_lui)                         ? 5'b00010 :
                     (is_jal | is_jalr)               ? 5'b00100 :
                     (is_load)                        ? 5'b01000 :
                     (is_csr | int_fp_result)         ? 5'b10000 :
                     5'b00000;
    
    assign o_pc_sel = is_jalr;

    // F extension stuff
    // FP register source classification
    wire fp_rs1_used =
         is_op_fp &&
         (func7 != 7'b1101000) &&
         (func7 != 7'b1111000);

    wire fp_rs2_used =
         is_op_fp &&
         ((func7 == 7'b0000000) ||
          (func7 == 7'b0000100) ||
          (func7 == 7'b0001000) ||
          (func7 == 7'b0001100) ||
          (func7 == 7'b0010000) ||
          (func7 == 7'b0010100) ||
          (func7 == 7'b1010000));

    wire fp_rd_used =
         is_load_fp ||
         (is_op_fp &&
          (func7 != 7'b1010000) &&
          (func7 != 7'b1110000) &&
          (func7 != 7'b1100000));

    wire int_fp_result =
         is_op_fp &&
         (((func7 == 7'b1010000)) ||
          ((func7 == 7'b1110000)) ||
          ((func7 == 7'b1100000)));

    assign o_fpu = is_op_fp | is_fused | valid_system;

    assign o_frs1_en = fp_rs1_used | is_fused;
    
    assign o_frs2_en = fp_rs2_used |
                       is_fused |
                       is_store_fp;

    assign o_frs3_en = is_fused;

    assign o_rs3 = i_inst[31:27];

    assign o_frd_en = fp_rd_used |
                      is_fused;

endmodule

`default_nettype wire
