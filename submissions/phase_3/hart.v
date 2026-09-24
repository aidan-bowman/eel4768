`default_nettype none

// A hart ("hardware thread") is one complete RISC-V CPU: it fetches an
// instruction, decodes it, executes it, and writes the result back. This one
// is single-cycle, so all four of those happen in the same clock cycle and
// exactly one instruction retires every cycle -- there are no bubbles and no
// pipeline stages.
//
// You do not write the datapath blocks again here. Instantiate the four
// modules from phase 2 (`alu`, `rf`, `decoder`, which itself contains `imm`)
// and wire them together, then add the parts phase 2 did not have: the
// program counter, the branch/jump target logic, and the memory interfaces.
//
// Remember the two small changes phase 3 needs from your phase 2 modules:
// `rf` is instantiated with BYPASS_EN = 0 (a single-cycle design writes back
// on the same edge the next read samples, so there is nothing to bypass),
// and `rf` no longer has a write enable -- gate a write by driving its write
// address to 5'd0 instead. Do not instantiate a second copy of `imm`; your
// `decoder` already contains one.

module hart #(
    // The address the program counter is initialized to on reset. The first
    // instruction to retire after `i_rst` deasserts must be the one fetched
    // from this address.
    parameter RESET_ADDR = 32'h00000000
) (
    // Global clock.
    input wire i_clk,

    // Synchronous active-high reset.
    input wire i_rst,

    // ---- Instruction memory ------------------------------------------

    // The instruction memory is external to your design, read-only, and
    // combinational: the word at `o_imem_raddr` appears on `i_imem_rdata`
    // in the same cycle, with no clock edge and no latency.

    // Address of the instruction to fetch. One instruction per cycle,
    // always 4-byte aligned.
    output wire [31:0] o_imem_raddr,

    // The instruction word stored at `o_imem_raddr`.
    input wire [31:0] i_imem_rdata,

    // ---- Data memory -------------------------------------------------

    // The data memory is also external and combinational: reads need no
    // clock edge, and writes commit on the next clock edge.

    // Data address. This is **always word-aligned** -- the low two bits of
    // the computed byte address never reach memory. Which bytes inside that
    // word are touched is `o_dmem_mask`'s job, not the address's.
    output wire [31:0] o_dmem_addr,

    // Read enable. Must never be high in the same cycle as `o_dmem_wen`.
    output wire o_dmem_ren,

    // Write enable.
    output wire o_dmem_wen,

    // Store data. Only the byte lanes selected by `o_dmem_mask` are used;
    // the rest are ignored, so they may hold anything. For a sub-word store
    // (`sb`, `sh`), the byte(s) must be positioned in the lane(s) they are
    // being written to, not left at the bottom of the word.
    output wire [31:0] o_dmem_wdata,

    // Which of the four byte lanes of the word at `o_dmem_addr` are read or
    // written. A byte access asserts one lane, a half-word two adjacent
    // lanes, and a word all four.
    output wire [3:0] o_dmem_mask,

    // The full 32-bit word at `o_dmem_addr`, regardless of the mask.
    // Extracting the requested bytes and sign- or zero-extending them
    // (`lb`/`lh` vs `lbu`/`lhu`) is this module's job.
    input wire [31:0] i_dmem_rdata,

    // ---- Retire interface --------------------------------------------

    output wire o_retire_valid,
    output wire [31:0] o_retire_inst,
    output wire o_retire_trap,
    output wire o_retire_halt,

    output wire [4:0] o_retire_rs1_raddr,
    output wire [31:0] o_retire_rs1_rdata,

    output wire [4:0] o_retire_rs2_raddr,
    output wire [31:0] o_retire_rs2_rdata,

    output wire [4:0] o_retire_rd_waddr,
    output wire [31:0] o_retire_rd_wdata,

    output wire [31:0] o_retire_pc,
    output wire [31:0] o_retire_next_pc
);

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

    wire op1_pc_sel;
    wire op2_imm_sel;

    wire [2:0] alu_opsel;
    wire alu_sub;
    wire alu_unsigned;
    wire alu_arith;

    wire inst_branch;
    wire inst_jump;

    wire branch_equal;
    wire branch_unsigned;
    wire branch_invert;

    wire memread;
    wire memwrite;

    wire [1:0] memalign;
    wire memb;
    wire memh;
    wire memw;
    wire memu;

    wire [3:0] rd_sel;

    wire pc_alu_sel;


    // These are kept separate from the external memory outputs so that
    // illegal and misaligned instructions can be prevented from causing
    // side effects.
    wire decoder_dmem_ren;
    wire decoder_dmem_wen;


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
    wire [4:0] rf_rd_waddr =
        (legal && !halt && !o_retire_trap) ? rd : 5'd0;


    rf #(
        .BYPASS_EN(0)
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
    wire alu_eq;
    wire alu_slt;

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
        (legal && !o_retire_trap && jump_taken) ?
            jump_target :
        (legal && !o_retire_trap && branch_taken) ?
            branch_target :
            pc_plus_4;


    // ================================================================
    // RETIRE INTERFACE
    // ================================================================

    assign o_retire_valid = !i_rst;

    assign o_retire_inst = i_imem_rdata;

    assign o_retire_trap =
        !legal |
        dmem_misaligned;

    assign o_retire_halt =
        halt && legal;


    assign o_retire_pc = pc;

    assign o_retire_next_pc = next_pc;


    // ------------------------------------------------
    // Retire rs1
    // ------------------------------------------------
    //
    // rs1 is read by:
    //   R-type
    //   I-type arithmetic
    //   loads
    //   stores
    //   branches
    //   JALR
    //
    // It is not read by:
    //   LUI
    //   AUIPC
    //   JAL
    //   EBREAK
    //   illegal instructions

    wire uses_rs1;

    assign uses_rs1 =
        legal &&
        !halt &&
        (
            (i_imem_rdata[6:0] == 7'b0110011) ||
            (i_imem_rdata[6:0] == 7'b0010011) ||
            (i_imem_rdata[6:0] == 7'b0000011) ||
            (i_imem_rdata[6:0] == 7'b0100011) ||
            (i_imem_rdata[6:0] == 7'b1100011) ||
            (i_imem_rdata[6:0] == 7'b1100111)
        );


    assign o_retire_rs1_raddr =
        uses_rs1 ? rs1 : 5'd0;

    assign o_retire_rs1_rdata =
        uses_rs1 ? rs1_data : 32'd0;


    // ------------------------------------------------
    // Retire rs2
    // ------------------------------------------------
    //
    // rs2 is read by:
    //   R-type
    //   stores
    //   branches

    wire uses_rs2;

    assign uses_rs2 =
        legal &&
        !halt &&
        (
            (i_imem_rdata[6:0] == 7'b0110011) ||
            (i_imem_rdata[6:0] == 7'b0100011) ||
            (i_imem_rdata[6:0] == 7'b1100011)
        );


    assign o_retire_rs2_raddr =
        uses_rs2 ? rs2 : 5'd0;

    assign o_retire_rs2_rdata =
        uses_rs2 ? rs2_data : 32'd0;


    // ------------------------------------------------
    // Retire rd
    // ------------------------------------------------

    assign o_retire_rd_waddr =
        (legal && !o_retire_trap && !halt) ? rd : 5'd0;

    assign o_retire_rd_wdata =
        writeback_data;


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
