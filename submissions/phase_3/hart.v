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
    input  wire        i_clk,
    // Synchronous active-high reset.
    input  wire        i_rst,

    // ---- Instruction memory ------------------------------------------
    // The instruction memory is external to your design, read-only, and
    // combinational: the word at `o_imem_raddr` appears on `i_imem_rdata`
    // in the same cycle, with no clock edge and no latency.
    //
    // Address of the instruction to fetch. One instruction per cycle,
    // always 4-byte aligned.
    output wire [31:0] o_imem_raddr,
    // The instruction word stored at `o_imem_raddr`.
    input  wire [31:0] i_imem_rdata,

    // ---- Data memory -------------------------------------------------
    // The data memory is also external and combinational: reads need no
    // clock edge, and writes commit on the next clock edge.
    //
    // Data address. This is **always word-aligned** -- the low two bits of
    // the computed byte address never reach memory. Which bytes inside that
    // word are touched is `o_dmem_mask`'s job, not the address's.
    output wire [31:0] o_dmem_addr,
    // Read enable. Must never be high in the same cycle as `o_dmem_wen`.
    output wire        o_dmem_ren,
    // Write enable.
    output wire        o_dmem_wen,
    // Store data. Only the byte lanes selected by `o_dmem_mask` are used;
    // the rest are ignored, so they may hold anything. For a sub-word store
    // (`sb`, `sh`), the byte(s) must be positioned in the lane(s) they are
    // being written to, not left at the bottom of the word.
    output wire [31:0] o_dmem_wdata,
    // Which of the four byte lanes of the word at `o_dmem_addr` are read or
    // written. A byte access asserts one lane, a half-word two adjacent
    // lanes, and a word all four.
    output wire [ 3:0] o_dmem_mask,
    // The full 32-bit word at `o_dmem_addr`, regardless of the mask.
    // Extracting the requested bytes and sign- or zero-extending them
    // (`lb`/`lh` vs `lbu`/`lhu`) is this module's job.
    input  wire [31:0] i_dmem_rdata,

    // ---- Retire interface --------------------------------------------
    // These outputs are not part of RV32I. They exist so a testbench can see
    // what your design actually did each cycle. Drive every one of them
    // appropriately on every cycle; all of them are checked on every
    // retiring instruction.
    //
    // An instruction retired this cycle. Because the design is
    // single-cycle, this is high every cycle after `i_rst` deasserts,
    // through the cycle `o_retire_halt` fires.
    output wire        o_retire_valid,
    // The raw instruction word that was fetched and retired this cycle.
    output wire [31:0] o_retire_inst,
    // The instruction was an illegal encoding, or a misaligned data access
    // (a half-word access at an odd address, or a word access at an address
    // that is not a multiple of four -- a byte access is never misaligned).
    // A trapping instruction has no side effects: no memory access happens,
    // `o_retire_rd_waddr` is 5'd0, and control flow is not redirected
    // (there is no trap vector in this interface, so `o_retire_next_pc` is
    // still the pc plus four).
    output wire        o_retire_trap,
    // The instruction is `ebreak`, and execution should halt. Like a trap,
    // it reads nothing, writes nothing, and touches no memory.
    output wire        o_retire_halt,
    // First source register address, and the value read from it.
    // Instructions that do not read a first source register (`lui`,
    // `auipc`, `jal`, and illegal encodings) must report 5'd0 here.
    output wire [ 4:0] o_retire_rs1_raddr,
    output wire [31:0] o_retire_rs1_rdata,
    // Second source register address, and the value read from it. Only
    // R-type, store and branch instructions read a second source register;
    // everything else must report 5'd0 here.
    output wire [ 4:0] o_retire_rs2_raddr,
    output wire [31:0] o_retire_rs2_rdata,
    // Destination register address, and the value written to it. When the
    // instruction writes no register, this address must be 5'd0 -- the same
    // convention the decoder used in phase 2, and what discards the write
    // in the register file. The address is checked on every instruction,
    // including trapping ones; the data only matters when the address is
    // nonzero.
    output wire [ 4:0] o_retire_rd_waddr,
    output wire [31:0] o_retire_rd_wdata,
    // The address this instruction was fetched from.
    output wire [31:0] o_retire_pc,
    // The address the next instruction will be fetched from: the pc plus
    // four, or the branch or jump target when a branch is taken or a jump
    // is executed. This is what proves your branch targets, `jal`/`jalr`
    // targets, and `jalr`'s cleared low bit are right.
    output wire [31:0] o_retire_next_pc
);
    // STAGE 1: FETCH INSTR
    reg [31:0] pc;
    assign o_imem_raddr = pc;
    // i_imem_rdata holds instruction
    
    
    // STAGE 2: DECODE
    wire        legal;
    wire        halt;
    wire [ 4:0] rs1;
    wire [ 4:0] rs2;
    wire [ 4:0] rd;
    wire [31:0] imm;
    wire        op1_pc_sel;
    wire        op2_imm_sel;
    wire [ 2:0] alu_opsel;
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
    wire [ 1:0] memalign;
    wire        memb;
    wire        memh;
    wire        memw;
    wire        memu;
    wire [ 3:0] rd_sel; // what gets written to register (0: ALU, 1: imm, 2: PC+4, 3: mem)
    wire        pc_alu_sel;

    decoder decoder (.i_inst            (i_imem_rdata),
                     .o_legal           (legal)
                     .o_halt            (halt),
                     .o_rs1             (rs1),
                     .o_rs2             (rs2),
                     .o_rd              (rd),
                     .o_immediate       (imm),
                     .o_op1_sel         (op1_pc_sel),
                     .o_op2_sel         (op2_imm_sel),
                     .o_alu_opsel       (alu_opsel),
                     .o_alu_sub         (alu_sub),
                     .o_alu_unsigned    (alu_unsigned),
                     .o_alu_arith       (alu_arith),
                     .o_branch          (inst_branch),
                     .o_jump            (inst_jump),
                     .o_branch_equal    (branch_equal),
                     .o_branch_unsigned (branch_unsigned),
                     .o_branch_invert   (branch_invert),
                     .o_dmem_ren        (o_dmem_ren), // we can pipe this directly to memory
                     .o_dmem_wen        (o_dmem_wen), // ditto
                     .o_dmem_memb       (memb),
                     .o_dmem_memh       (memh),
                     .o_dmem_memw       (memw),
                     .o_dmem_memu       (memu),
                     .o_rd_sel          (rd_sel),
                     .o_pc_sel          (pc_alu_sel));

    // STAGE 2.5: REGISTERS
    // TODO: fill in
    rf rf ();

    // STAGE 3: EXECUTE
    // TODO: fill in
    alu alu();

    // STAGE 4: MEMORY
    // o_dmem_ren and o_dmem_wen already taken care of in STAGE 2
    // TODO:
    // o_dmem_addr
    // o_dmem_wdata
    // o_dmem_mask
    // i_dmem_rdata
    

    // STAGE 5: WRITEBACK
    assign wire pc_plus_4 = pc + 4;

    // SEQUENTIAL LOGIC
    always @(posedge i_clk) begin
        if (i_rst) begin
            pc <= RESET_ADDR;
        end else begin
            // TODO: change this!
            pc <= pc_plus_4;
        end
    end
    
    assign wire o_imem_raddr = pc
endmodule

`default_nettype wire
