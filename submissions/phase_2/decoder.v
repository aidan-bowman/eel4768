`default_nettype none

module decoder (
    // Input instruction word.
    input  wire [31:0] i_inst,
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
    // [0] = ALU result
    // [1] = immediate
    // [2] = PC + 4
    // [3] = memory
    output wire [ 3:0] o_rd_sel,
    // If asserted, the PC jumps to the target address calculated by the ALU
    // rather than directly to the PC + immediate. This is used for JALR.
    output wire        o_pc_sel
);

   // Opcode Decoding
   wire is_arr     = (i_inst[6:0] == 7'b0110011);
   wire is_arr_imm = (i_inst[6:0] == 7'b0010011);
   wire is_load    = (i_inst[6:0] == 7'b0000011);
   wire is_lui     = (i_inst[6:0] == 7'b0110111);
   wire is_auipc   = (i_inst[6:0] == 7'b0010111);
   wire is_store   = (i_inst[6:0] == 7'b0100011);
   wire is_branch  = (i_inst[6:0] == 7'b1100011);
   wire is_jal     = (i_inst[6:0] == 7'b1101111);
   wire is_jalr    = (i_inst[6:0] == 7'b1100111);
   wire is_system  = (i_inst[6:0] == 7'b1110011);

   wire format   = (is_arr | is_system)             ? 6'b000001 :
                   (is_arr_imm | is_load | is_jalr) ? 6'b000010 :
                   (is_store)                       ? 6'b000100 :
                   (is_branch)                      ? 6'b001000 :
                   (is_lui | is_auipc)              ? 6'b010000 :
                   (is_jal)                         ? 6'b100000;

   assign o_halt  = (i_inst = 32'h00100073);
   assign o_legal = is_system & ~o_halt;

   // rs1, rs2, and rd are always in the same place (unless they don't exist, in which case don't care)
   assign rd  = i_inst[11: 7];
   assign rs1 = i_inst[19:15];
   assign rs2 = i_inst[24:20];
   
   imm imm (.i_inst      (i_inst),
            .i_format    (format),
            .o_immediate (o_immediate)
            );

   assign o_op1_sel      = is_auipc | is_jal;
   assign o_op2_sel      = ~(is_arr | is_branch);
   assign o_alu_opsel    = (is_arr | is_arr_imm | is_branch) ? i_inst[14:12] : 3'b000; // funct3 if we're arithmetic or branch, or addition for other ops
   assign o_alu_sub      = is_arr & i_inst[   30]; // second digit of funct7 (if we're doing arithmetic)
   assign o_alu_unsigned = i_inst[   30]; // ditto (imm goes around this bit)
   assign o_alu_arith    = i_inst[   30]; // ditto

   assign o_branch = is_branch;
   assign o_jump   = is_jal | is_jalr;
    
   assign o_branch_equal    = ~i_inst[14];
   assign o_branch_unsigned = i_inst[13];
   assign o_branch_inver    = i_inst[12];
    
   assign o_dmem_ren   = is_load;
   assign o_dmem_wen   = is_store;
   assign o_dmem_memb  = ~(i_inst[13] | i_inst[12]);
   assign o_dmem_memh  = i_inst[12];
   assign o_dmem_memw  = i_inst[13];
   assign o_dmem_align = {o_dmem_memh, ~o_dmem_memw};
   assign o_dmem_memu  = i_inst[14];
   
   assign o_rd_sel = (is_arr | is_arr_imm | is_auipc) ? 2'b00 :
                     (is_lui)                         ? 2'b01 :
                     (is_jal | is_jalr)               ? 2'b10 :
                     (is_load)                        ? 2'b11;
   
   assign o_pc_sel = is_jalr;

endmodule

`default_nettype wire
