`default_nettype none

module hart
  #(// After reset, the program counter (PC) should be initialized to this
    // address and start executing instructions from there.
    parameter RESET_ADDR = 32'h00400000,
    // When set, pipeline forwarding optimizations are enabled.
    parameter FWD_EN = 1,
    // When set, register file bypassing is enabled.              
    parameter BYPASS_EN = 1
    ) (
       // Global clock.
       input wire         i_clk,

       // Synchronous active-high reset.
       input wire         i_rst,

       /********** INSTRUCTION MEMORY **********/
       // idealized as combinational
       // 32-bit read address for the instruction memory. This is expected to be
       // 4 byte aligned - that is, the two LSBs should be zero.
       output wire [31:0] o_imem_raddr,
       // Instruction word fetched from memory, available on the same cycle.
       input wire [31:0]  i_imem_rdata,

       /********** DATA MEMORY **********/
       // reads combinational
       // writes occur on clock edge
       // Read/write address for the data memory. This should be 32-bit aligned
       // (i.e. the two LSB should be zero). See `o_dmem_mask` for how to perform
       // half-word and byte accesses at unaligned addresses.
       output wire [31:0] o_dmem_addr,
       // When asserted, the memory will perform a read at the aligned address
       // specified by `i_addr` and return the 32-bit word at that address
       // immediately (i.e. combinationally). It is illegal to assert this and
       // `o_dmem_wen` on the same cycle.
       output wire        o_dmem_ren,
       // When asserted, the memory will perform a write to the aligned address
       // `o_dmem_addr`. When asserted, the memory will write the bytes in
       // `o_dmem_wdata` (specified by the mask) to memory at the specified
       // address on the next rising clock edge. It is illegal to assert this and
       // `o_dmem_ren` on the same cycle.
       output wire        o_dmem_wen,
       // The 32-bit word to write to memory when `o_dmem_wen` is asserted. When
       // write enable is asserted, the byte lanes specified by the mask will be
       // written to the memory word at the aligned address at the next rising
       // clock edge. The other byte lanes of the word will be unaffected.
       output wire [31:0] o_dmem_wdata,
       // The dmem interface expects word (32 bit) aligned addresses. However,
       // WISC-25 supports byte and half-word loads and stores at unaligned and
       // 16-bit aligned addresses, respectively. To support this, the access
       // mask specifies which bytes within the 32-bit word are actually read
       // from or written to memory.
       //
       // To perform a half-word read at address 0x00001002, align `o_dmem_addr`
       // to 0x00001000, assert `o_dmem_ren`, and set the mask to 0b1100 to
       // indicate that only the upper two bytes should be read. Only the upper
       // two bytes of `i_dmem_rdata` can be assumed to have valid data; to
       // calculate the final value of the `lh[u]` instruction, shift the rdata
       // word right by 16 bits and sign/zero extend as appropriate.
       //
       // To perform a byte write at address 0x00002003, align `o_dmem_addr` to
       // `0x00002003`, assert `o_dmem_wen`, and set the mask to 0b1000 to
       // indicate that only the upper byte should be written. On the next clock
       // cycle, the upper byte of `o_dmem_wdata` will be written to memory, with
       // the other three bytes of the aligned word unaffected. Remember to shift
       // the value of the `sb` instruction left by 24 bits to place it in the
       // appropriate byte lane.
       output wire [ 3:0] o_dmem_mask,
       // The 32-bit word read from data memory. When `o_dmem_ren` is asserted,
       // this will immediately reflect the contents of memory at the specified
       // address, for the bytes enabled by the mask. When read enable is not
       // asserted, or for bytes not set in the mask, the value is undefined.
       input wire [31:0]  i_dmem_rdata,
       // The output `retire` interface is used to signal to the testbench that
       // the CPU has completed and retired an instruction. A single cycle
       // implementation will assert this every cycle; however, a pipelined
       // implementation that needs to stall (due to internal hazards or waiting
       // on memory accesses) will not assert the signal on cycles where the
       // instruction in the writeback stage is not retiring.

       /********** RETIRE INTERFACE **********/
       // Asserted when an instruction is being retired this cycle. If this is
       // not asserted, the other retire signals are ignored and may be left invalid.
       output wire        o_retire_valid,
       // The 32 bit instruction word of the instrution being retired. This
       // should be the unmodified instruction word fetched from instruction
       // memory.
       output wire [31:0] o_retire_inst,
       // Asserted if the instruction produced a trap, due to an illegal
       // instruction, unaligned data memory access, or unaligned instruction
       // address on a taken branch or jump.
       output wire        o_retire_trap,
       // Asserted if the instruction is an `ebreak` instruction used to halt the
       // processor. This is used for debugging and testing purposes to end
       // a program.
       output wire        o_retire_halt,
       // The first register address read by the instruction being retired. If
       // the instruction does not read from a register (like `lui`), this
       // should be 5'd0.
       output wire [ 4:0] o_retire_rs1_raddr,
       // The second register address read by the instruction being retired. If
       // the instruction does not read from a second register (like `addi`), this
       // should be 5'd0.
       output wire [ 4:0] o_retire_rs2_raddr,
       // The first source register data read from the register file (in the
       // decode stage) for the instruction being retired. If rs1 is 5'd0, this
       // should also be 32'd0.
       output wire [31:0] o_retire_rs1_rdata,
       // The second source register data read from the register file (in the
       // decode stage) for the instruction being retired. If rs2 is 5'd0, this
       // should also be 32'd0.
       output wire [31:0] o_retire_rs2_rdata,
       // The destination register address written by the instruction being
       // retired. If the instruction does not write to a register (like `sw`),
       // this should be 5'd0.
       output wire [ 4:0] o_retire_rd_waddr,
       // The destination register data written to the register file in the
       // writeback stage by this instruction. If rd is 5'd0, this field is
       // ignored and can be treated as a don't care.
       output wire [31:0] o_retire_rd_wdata,
       output wire [31:0] o_retire_dmem_addr,
       output wire [ 3:0] o_retire_dmem_mask,
       output wire        o_retire_dmem_ren,
       output wire        o_retire_dmem_wen,
       output wire [31:0] o_retire_dmem_rdata,
       output wire [31:0] o_retire_dmem_wdata,
       // The current program counter of the instruction being retired - i.e.
       // the instruction memory address that the instruction was fetched from.
       output wire [31:0] o_retire_pc,
       // the next program counter after the instruction is retired. For most
       // instructions, this is `o_retire_pc + 4`, but must be the branch or jump
       // target for *taken* branches and jumps.
       output wire [31:0] o_retire_next_pc
`ifdef RISCV_FORMAL
       , RVFI_OUTPUTS,
`endif
       );

    // TODO:
    // rewrite to match 5 stages: IF, ID, EX, MEM, WB
    // add registers between stages
    // design to detect data hazards
    // design to stall/forward data
    // design to detect control hazards
    // design to flush incorrect instructions
    
    // ================================================================
    // STAGE 1: FETCH INSTR
    // ================================================================

    reg [31:0] pc;

    assign o_imem_raddr = pc;


    // ================================================================
    // STAGE 2: DECODE
    // ================================================================

    wire legal;
    wire halt;

    wire [4:0] rs1;
    wire [4:0] rs2;
    wire [4:0] rd;

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

    wire [3:0]  rd_sel;

    wire        pc_alu_sel;


    // These are kept separate from the external memory outputs so that
    // illegal and misaligned instructions can be prevented from causing
    // side effects.
    wire        decoder_dmem_ren;
    wire        decoder_dmem_wen;


    decoder decoder (
                     .i_inst(i_imem_rdata),

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

                     .o_dmem_ren(decoder_dmem_ren),
                     .o_dmem_wen(decoder_dmem_wen),

                     .o_dmem_memb(memb),
                     .o_dmem_memh(memh),
                     .o_dmem_memw(memw),
                     .o_dmem_memu(memu),

                     .o_dmem_align(memalign),

                     .o_rd_sel(rd_sel),

                     .o_pc_sel(pc_alu_sel)
                     );


    // ================================================================
    // STAGE 2.5: REGISTERS
    // ================================================================

    wire [31:0] rs1_data;
    wire [31:0] rs2_data;

    wire [31:0] writeback_data;

    // A misaligned or illegal instruction must not write a register.
    // Driving x0 to the write address is how Phase 3 disables writes.
    wire [4:0]  rf_rd_waddr =
                (legal && !halt) ? rd : 5'd0;


    rf #(
         .BYPASS_EN(BYPASS_EN)
         ) rf (
               .i_clk(i_clk),
               .i_rst(i_rst),
               
               .i_rs1_raddr(rs1),
               .o_rs1_rdata(rs1_data),

               .i_rs2_raddr(rs2),
               .o_rs2_rdata(rs2_data),

               .i_rd_waddr(rf_rd_waddr),
               .i_rd_wdata(writeback_data)
               );

    // ================================================================
    // STAGE 3: EXECUTE
    // ================================================================

    wire [31:0] alu_op1;
    wire [31:0] alu_op2;

    wire [31:0] alu_result;
    wire        alu_eq;
    wire        alu_slt;

    assign alu_op1 = op1_pc_sel ? pc : rs1_data;

    assign alu_op2 = op2_imm_sel ? imm : rs2_data;


    alu alu (
             .i_opsel(alu_opsel),
             .i_sub(alu_sub),
             .i_unsigned(alu_unsigned),
             .i_arith(alu_arith),

             .i_op1(alu_op1),
             .i_op2(alu_op2),

             .o_result(alu_result),
             .o_eq(alu_eq),
             .o_slt(alu_slt)
             );


    // ================================================================
    // STAGE 4: MEMORY
    // ================================================================

    // The ALU calculates the byte address.
    wire [31:0] dmem_byte_addr;

    assign dmem_byte_addr = alu_result;

    // External memory always receives a word-aligned address.
    assign o_dmem_addr = {dmem_byte_addr[31:2], 2'b00};


    // ------------------------------------------------
    // Alignment
    // ------------------------------------------------
    //
    // decoder's o_dmem_align:
    //
    //   00 = byte
    //   01 = half-word
    //   10 = word
    //
    // For a byte, no alignment bits matter.
    // For a half-word, bit 0 must be zero.
    // For a word, bits 1:0 must both be zero.

    wire dmem_misaligned;

    assign dmem_misaligned =
                            (decoder_dmem_ren | decoder_dmem_wen) &&
                            (
                             (memalign[0] && dmem_byte_addr[0]) ||
                             (memalign[1] &&
                              (dmem_byte_addr[1] | dmem_byte_addr[0]))
                             );


    // Illegal instructions and misaligned accesses have no memory side
    // effects.
    assign o_dmem_ren =
                       decoder_dmem_ren &&
                       legal &&
                       !halt &&
                       !dmem_misaligned;

    assign o_dmem_wen =
                       decoder_dmem_wen &&
                       legal &&
                       !halt &&
                       !dmem_misaligned;


    // ------------------------------------------------
    // Memory mask
    // ------------------------------------------------

    wire [3:0] byte_mask;
    wire [3:0] half_mask;

    assign byte_mask =
                      (dmem_byte_addr[1:0] == 2'b00) ? 4'b0001 :
                      (dmem_byte_addr[1:0] == 2'b01) ? 4'b0010 :
                      (dmem_byte_addr[1:0] == 2'b10) ? 4'b0100 :
                      4'b1000;

    assign half_mask =
                      (dmem_byte_addr[1:0] == 2'b00) ? 4'b0011 :
                      (dmem_byte_addr[1:0] == 2'b01) ? 4'b0110 :
                      (dmem_byte_addr[1:0] == 2'b10) ? 4'b1100 :
                      4'b0000;

    assign o_dmem_mask =
                        memw ? 4'b1111 :
                        memh ? half_mask :
                        byte_mask;


    // ------------------------------------------------
    // Store data
    // ------------------------------------------------

    assign o_dmem_wdata =
                         memw ? rs2_data :
                         memh ?
                         (
                          (dmem_byte_addr[1:0] == 2'b00) ? {16'b0, rs2_data[15:0]} :
                          (dmem_byte_addr[1:0] == 2'b01) ? {8'b0, rs2_data[15:0], 8'b0} :
                          (dmem_byte_addr[1:0] == 2'b10) ? {rs2_data[15:0], 16'b0} :
                          32'b0
                          ) :
                         (
                          (dmem_byte_addr[1:0] == 2'b00) ? {24'b0, rs2_data[7:0]} :
                          (dmem_byte_addr[1:0] == 2'b01) ? {16'b0, rs2_data[7:0], 8'b0} :
                          (dmem_byte_addr[1:0] == 2'b10) ? {8'b0, rs2_data[7:0], 16'b0} :
                          {rs2_data[7:0], 24'b0}
                          );


    // ------------------------------------------------
    // Load data
    // ------------------------------------------------

    wire [7:0] load_byte;
    wire [15:0] load_half;

    assign load_byte =
                      (dmem_byte_addr[1:0] == 2'b00) ? i_dmem_rdata[7:0] :
                      (dmem_byte_addr[1:0] == 2'b01) ? i_dmem_rdata[15:8] :
                      (dmem_byte_addr[1:0] == 2'b10) ? i_dmem_rdata[23:16] :
                      i_dmem_rdata[31:24];

    assign load_half =
                      (dmem_byte_addr[1:0] == 2'b00) ? i_dmem_rdata[15:0] :
                      (dmem_byte_addr[1:0] == 2'b01) ? i_dmem_rdata[23:8] :
                      (dmem_byte_addr[1:0] == 2'b10) ? i_dmem_rdata[31:16] :
                      16'b0;


    assign writeback_data =
                           rd_sel[3] ?
                           (
                            memw ? i_dmem_rdata :
                            memh ?
                            (
                             memu ?
                             {16'b0, load_half} :
                             {{16{load_half[15]}}, load_half}
                             ) :
                            (
                             memu ?
                             {24'b0, load_byte} :
                             {{24{load_byte[7]}}, load_byte}
                             )
                            ) :
                           rd_sel[2] ? (pc + 32'd4) :
                           rd_sel[1] ? imm :
                           rd_sel[0] ? alu_result :
                           32'b0;


    // ================================================================
    // BRANCH / JUMP
    // ================================================================

    // For BEQ/BNE the ALU equality output is used.
    // For BLT/BGE/BLTU/BGEU the ALU less-than output is used.
    //
    // The decoder supplies i_unsigned to the ALU for unsigned branches.

    wire branch_condition;

    assign branch_condition =
                             branch_equal ? alu_eq : alu_slt;


    wire branch_taken;

    assign branch_taken =
                         legal &&
                         inst_branch &&
                         (branch_condition ^ branch_invert);


    // ------------------------------------------------
    // Branch target
    // ------------------------------------------------

    wire [31:0] branch_target;

    assign branch_target = pc + imm;


    // ------------------------------------------------
    // Jump target
    // ------------------------------------------------

    // JAL:
    //     PC + immediate
    //
    // JALR:
    //     rs1 + immediate, with bit 0 cleared.
    //
    // alu_result already contains rs1 + immediate for JALR because the
    // decoder selects rs1 and the immediate for the ALU.

    wire [31:0] jump_target;

    assign jump_target =
                        pc_alu_sel ?
                        {alu_result[31:1], 1'b0} :
                        (pc + imm);


    wire jump_taken;

    assign jump_taken =
                       legal &&
                       inst_jump &&
                       !halt;


    // ------------------------------------------------
    // Next PC
    // ------------------------------------------------

    wire [31:0] pc_plus_4;

    assign pc_plus_4 = pc + 32'd4;


    wire [31:0] next_pc;

    assign next_pc =
                    (legal && jump_taken) ?
                    jump_target :
                    (legal && branch_taken) ?
                    branch_target :
                    pc_plus_4;

    // ================================================================
    // SEQUENTIAL LOGIC
    // ================================================================

    always @(posedge i_clk) begin
        if (i_rst) begin
            pc <= RESET_ADDR;
        end else begin
            pc <= next_pc;
        end
    end

endmodule

`default_nettype wire
