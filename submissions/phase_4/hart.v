`default_nettype none

module hart
  #(// After reset, the program counter (PC) should be initialized to this
    // address and start executing instructions from there.
     parameter RESET_ADDR = 32'h00400000,
    // When set, pipeline forwarding optimizations are enabled.
     parameter FWD_EN = 1,
    // When set, register file bypassing is enabled.              
     parameter BYPASS_EN = 1
    // What instruction is used for NOPs
    //    parameter NOP_INST = 32'h00000013; // addi zero, zero, 0
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

    // ================================================================
    // HAZARD CONTROL
    // ================================================================
    // this module reads signals from throughout the CPU
    // and gens signals that (ideally) stop hazards from being genned
    
    hazardctrl #(
                 .FWD_EN(FWD_EN),
                 .BYPASS_EN(BYPASS_EN)
                 )
    hazardctrl (
                .i_id_rs1(rs1), // fill in our wires in parenthesis
                .i_id_rs2(rs2),
                .i_id_store(decoder_dmem_ren),
                .i_ex_rd(id_ex_rd),
                .i_ex_rs1(id_ex_rs1),
                .i_ex_rs2(id_ex_rs2),
                .i_ex_load(id_ex_memwrite),
                .i_ex_btaken(ex_branchtaken),
                .i_mem_rd(ex_mem_rd),
                .i_wb_rd(ex_mem_rd),
                //outputs
                .o_if_hold(if_hold),
                .o_id_nop(id_nop)
                );
    
    // ================================================================
    // STAGE 1: FETCH INSTRUCTION
    // ================================================================

    reg  [31:0] pc;
    wire        if_hold; // see hazardctrl
    wire [31:0] pc_plus_4;
    wire [31:0] next_pc;

    assign o_imem_raddr = pc;
    
    assign pc_plus_4 = pc + 32'd4;
    
    assign next_pc = if_hold ? pc :
                     jump_taken ? jump_target :
                     ex_branchtaken ? ex_branchtarget :
                     pc_plus_4;
    
    // =============================================================
    // REGISTER IF/ID
    // =============================================================

    reg [31:0] if_id_pc;
    reg [31:0] if_id_inst;
	reg if_id_valid;

    always @(posedge i_clk) begin
        if (i_rst) begin
            pc         <= RESET_ADDR;
            if_id_pc   <= 32'b0;
            if_id_inst <= 32'b0;
			      if_id_valid <= 1'b0;
        end else if (if_hold) begin
            // don't update anything
        end else begin
            if_id_pc   <= pc;
            if_id_inst <= i_imem_rdata;
            pc         <= next_pc;
        end
    end


    // ================================================================
    // STAGE 2: DECODE
    // ================================================================

    wire legal;
    wire halt;
    
    wire trap;
    assign trap = !legal;

    wire        id_nop; // see hazardctrl

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
                     .i_inst(if_id_inst),

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
                (mem_wb_legal && !mem_wb_halt) ? mem_wb_rd : 5'd0;


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
               .i_rd_wdata(mem_wb_writeback_data)
               );

    
    // ================================================================
    // REGISTER ID/EX
    // ================================================================

    reg [31:0] id_ex_pc;
	reg [31:0] id_ex_inst;
	reg id_ex_valid;
    reg [31:0] id_ex_rs1_data;
    reg [31:0] id_ex_rs2_data;
    reg [4:0]  id_ex_rs1;
    reg [4:0]  id_ex_rs2;
    reg [31:0] id_ex_imm;

    reg [4:0]  id_ex_rd;
    reg [2:0]  id_ex_alu_opsel;
    reg        id_ex_alu_sub;
    reg        id_ex_alu_unsigned;
    reg        id_ex_alu_arith;

    reg        id_ex_op1_pc_sel;
    reg        id_ex_op2_imm_sel;

    reg        id_ex_branch;
    reg        id_ex_branch_equal;
    reg        id_ex_branch_unsigned;
    reg        id_ex_branch_invert;

    reg        id_ex_jump;
    reg        id_ex_pc_alu_sel;

    reg        id_ex_memread;
    reg        id_ex_memwrite;
    reg [1:0]  id_ex_memalign;
    reg        id_ex_memb;
    reg        id_ex_memh;
    reg        id_ex_memw;
    reg        id_ex_memu;

    reg [3:0]  id_ex_rd_sel;

    reg        id_ex_legal;
    reg        id_ex_halt;
    reg        id_ex_trap;

    always @(posedge i_clk) begin
        if (i_rst | id_nop) begin
            id_ex_pc              <= 32'b0;
			id_ex_inst            <= 32'b0;
            id_ex_rs1_data        <= 32'b0;
            id_ex_rs2_data        <= 32'b0;
            id_ex_rs1             <= 5'd0;
            id_ex_rs2             <= 5'd0;
            id_ex_imm             <= 32'b0;
            id_ex_rd              <= 5'd0;
            id_ex_alu_opsel       <= 3'b0;
            id_ex_alu_sub         <= 1'b0;
            id_ex_alu_unsigned    <= 1'b0;
            id_ex_alu_arith       <= 1'b0;
            id_ex_op1_pc_sel      <= 1'b0;
            id_ex_op2_imm_sel     <= 1'b0;
            id_ex_branch          <= 1'b0;
            id_ex_branch_equal    <= 1'b0;
            id_ex_branch_unsigned <= 1'b0;
            id_ex_branch_invert   <= 1'b0;
            id_ex_jump            <= 1'b0;
            id_ex_pc_alu_sel      <= 1'b0;
            id_ex_memread         <= 1'b0;
            id_ex_memwrite        <= 1'b0;
            id_ex_memalign        <= 2'b0;
            id_ex_memb            <= 1'b0;
            id_ex_memh            <= 1'b0;
            id_ex_memw            <= 1'b0;
            id_ex_memu            <= 1'b0;
            id_ex_rd_sel          <= 4'b0;
            id_ex_legal           <= 1'b0;
            id_ex_halt            <= 1'b0;
            id_ex_trap            <= 1'b0;
        end else begin // if o_id_nop
            id_ex_pc              <= if_id_pc;
			id_ex_inst            <= if_id_inst;
            id_ex_rs1_data        <= rs1_data;
            id_ex_rs2_data        <= rs2_data;
            id_ex_rs1             <= rs1;
            id_ex_rs2             <= rs2;
            id_ex_imm             <= imm;
            id_ex_rd              <= rd;
            id_ex_alu_opsel       <= alu_opsel;
            id_ex_alu_sub         <= alu_sub;
            id_ex_alu_unsigned    <= alu_unsigned;
            id_ex_alu_arith       <= alu_arith;
            id_ex_op1_pc_sel      <= op1_pc_sel;
            id_ex_op2_imm_sel     <= op2_imm_sel;
            id_ex_branch          <= inst_branch;
            id_ex_branch_equal    <= branch_equal;
            id_ex_branch_unsigned <= branch_unsigned;
            id_ex_branch_invert   <= branch_invert;
            id_ex_jump            <= inst_jump;
            id_ex_pc_alu_sel      <= pc_alu_sel;
            id_ex_memread         <= decoder_dmem_ren;
            id_ex_memwrite        <= decoder_dmem_wen;
            id_ex_memalign        <= memalign;
            id_ex_memb            <= memb;
            id_ex_memh            <= memh;
            id_ex_memw            <= memw;
            id_ex_memu            <= memu;
            id_ex_rd_sel          <= rd_sel;
            id_ex_legal           <= legal;
            id_ex_halt            <= halt;
            id_ex_trap            <= trap;
        end
    end
    
    // ================================================================
	// STAGE 3: EXECUTE
	// ================================================================

	wire [31:0] forward_rs1_data;
	wire [31:0] forward_rs2_data;

	wire        forward_ex_rs1;
	wire        forward_ex_rs2;
	wire        forward_wb_rs1;
	wire        forward_wb_rs2;

	wire [31:0] alu_op1;
	wire [31:0] alu_op2;

	wire [31:0] alu_result;
	wire        alu_eq;
	wire        alu_slt;


	// EX/MEM forwarding

	assign forward_ex_rs1 =
    		               FWD_EN &&
    		               (ex_mem_rd != 5'd0) &&
    		               ex_mem_legal &&
    		               !ex_mem_halt &&
    		               !ex_mem_memread &&
    		               (ex_mem_rd == id_ex_rs1);

	assign forward_ex_rs2 =
    		               FWD_EN &&
    		               (ex_mem_rd != 5'd0) &&
    		               ex_mem_legal &&
    		               !ex_mem_halt &&
    		               !ex_mem_memread &&
    		               (ex_mem_rd == id_ex_rs2);


	// MEM/WB forwarding

	assign forward_wb_rs1 =
    		               FWD_EN &&
    		               (mem_wb_rd != 5'd0) &&
    		               mem_wb_legal &&
    		               !mem_wb_halt &&
    		               (mem_wb_rd == id_ex_rs1);

	assign forward_wb_rs2 =
    		               FWD_EN &&
    		               (mem_wb_rd != 5'd0) &&
    		               mem_wb_legal &&
    		               !mem_wb_halt &&
    		               (mem_wb_rd == id_ex_rs2);


	// Forwarding multiplexers

	assign forward_rs1_data =
    		                 forward_ex_rs1 ? ex_mem_alu_result :
    		                 forward_wb_rs1 ? mem_wb_writeback_data :
        		             id_ex_rs1_data;

	assign forward_rs2_data =
    		                 forward_ex_rs2 ? ex_mem_alu_result :
    		                 forward_wb_rs2 ? mem_wb_writeback_data :
    		                 id_ex_rs2_data;

    assign alu_op1 = id_ex_op1_pc_sel ? id_ex_pc : forward_rs1_data;

    assign alu_op2 = id_ex_op2_imm_sel ? id_ex_imm : forward_rs2_data;


    alu alu (
             .i_opsel(id_ex_alu_opsel),
             .i_sub(id_ex_alu_sub),
             .i_unsigned(id_ex_alu_unsigned),
             .i_arith(id_ex_alu_arith),

             .i_op1(alu_op1),
             .i_op2(alu_op2),

             .o_result(alu_result),
             .o_eq(alu_eq),
             .o_slt(alu_slt)
             );

    // ================================================================
    // BRANCH / JUMP
    // ================================================================

    // For BEQ/BNE the ALU equality output is used.
    // For BLT/BGE/BLTU/BGEU the ALU less-than output is used.
    //
    // The decoder supplies i_unsigned to the ALU for unsigned branches.

    wire ex_branchcondition;
    wire ex_branchtaken;
    wire [31:0] ex_branchtarget;
    
    assign ex_branchcondition = id_ex_branch_equal ? alu_eq : alu_slt;

    assign ex_branchtaken = id_ex_legal && id_ex_branch &&
                         (ex_branchcondition ^ id_ex_branch_invert);

    assign ex_branchtarget = id_ex_pc + id_ex_imm;




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
                        id_ex_pc_alu_sel ?
                        {alu_result[31:1], 1'b0} :
                        (id_ex_pc + id_ex_imm);


    wire jump_taken;

    assign jump_taken =
                       id_ex_legal &&
                       id_ex_jump &&
                       !id_ex_halt;


    // ================================================================
    // REGISTER EX/MEM
    // ================================================================

    reg [31:0] ex_mem_alu_result;
	reg [31:0] ex_mem_rs2_data;
	reg [31:0] ex_mem_rs1_data;
	reg [31:0] ex_mem_pc;
	reg ex_mem_valid;
	reg [31:0] ex_mem_next_pc;
	reg [31:0] ex_mem_inst;
	reg [31:0] ex_mem_imm;
	
	reg [4:0]  ex_mem_rs1;
	reg [4:0]  ex_mem_rs2;
	reg [4:0]  ex_mem_rd;

    reg        ex_mem_memread;
    reg        ex_mem_memwrite;
    reg [1:0]  ex_mem_memalign;
    reg        ex_mem_memb;
    reg        ex_mem_memh;
    reg        ex_mem_memw;
    reg        ex_mem_memu;

    reg [3:0]  ex_mem_rd_sel;

    reg        ex_mem_legal;
    reg        ex_mem_halt;
    reg        ex_mem_trap;

    always @(posedge i_clk) begin
        if (i_rst) begin
            ex_mem_alu_result <= 32'b0;
            ex_mem_rs2_data   <= 32'b0;
            ex_mem_pc         <= 32'b0;
			ex_mem_next_pc      <= 32'b0;
            ex_mem_imm        <= 32'b0;
			ex_mem_inst       <= 32'b0;
			ex_mem_rs1_data   <= 32'b0;
			ex_mem_rs1        <= 5'd0;
			ex_mem_rs2        <= 5'd0;
            ex_mem_rd         <= 5'd0;
            ex_mem_memread    <= 1'b0;
            ex_mem_memwrite   <= 1'b0;
            ex_mem_memalign   <= 2'b0;
            ex_mem_memb       <= 1'b0;
            ex_mem_memh       <= 1'b0;
            ex_mem_memw       <= 1'b0;
            ex_mem_memu       <= 1'b0;
            ex_mem_rd_sel     <= 4'b0;
            ex_mem_legal      <= 1'b0;
            ex_mem_halt       <= 1'b0;
            ex_mem_trap       <= 1'b0;
        end else begin
            ex_mem_alu_result <= alu_result;
            ex_mem_rs2_data   <= id_ex_rs2_data;
            ex_mem_pc         <= id_ex_pc;
			ex_mem_next_pc      <= ex_next_pc;
			ex_mem_inst       <= id_ex_inst;
			ex_mem_rs1_data   <= id_ex_rs1_data;
			ex_mem_rs1        <= id_ex_rs1;
			ex_mem_rs2        <= id_ex_rs2;
            ex_mem_imm        <= id_ex_imm;
            ex_mem_rd         <= id_ex_rd;
            ex_mem_memread    <= id_ex_memread;
            ex_mem_memwrite   <= id_ex_memwrite;
            ex_mem_memalign   <= id_ex_memalign;
            ex_mem_memb       <= id_ex_memb;
            ex_mem_memh       <= id_ex_memh;
            ex_mem_memw       <= id_ex_memw;
            ex_mem_memu       <= id_ex_memu;
            ex_mem_rd_sel     <= id_ex_rd_sel;
            ex_mem_legal      <= id_ex_legal;
            ex_mem_halt       <= id_ex_halt;
            ex_mem_trap       <= id_ex_trap;
        end
    end

    // ================================================================
    // STAGE 4: MEMORY
    // ================================================================

    // The ALU calculates the byte address.
    wire [31:0] dmem_byte_addr;

    assign dmem_byte_addr = ex_mem_alu_result;

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
                            (ex_mem_memread | ex_mem_memwrite) &&
                            (
                             (ex_mem_memalign[0] && dmem_byte_addr[0]) ||
                             (ex_mem_memalign[1] &&
                              (dmem_byte_addr[1] | dmem_byte_addr[0]))
                             );


    // Illegal instructions and misaligned accesses have no memory side
    // effects.
    assign o_dmem_ren =
                       ex_mem_memread &&
                       ex_mem_legal &&
                       !ex_mem_halt &&
                       !dmem_misaligned;

    assign o_dmem_wen =
                       ex_mem_memwrite &&
                       ex_mem_legal &&
                       !ex_mem_halt &&
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
                        ex_mem_memw ? 4'b1111 :
                        ex_mem_memh ? half_mask :
                        byte_mask;


    // ------------------------------------------------
    // Store data
    // ------------------------------------------------

    assign o_dmem_wdata =
                         ex_mem_memw ? ex_mem_rs2_data :
                         ex_mem_memh ?
                         (
                          (dmem_byte_addr[1:0] == 2'b00) ? {16'b0, ex_mem_rs2_data[15:0]} :
                          (dmem_byte_addr[1:0] == 2'b01) ? {8'b0, ex_mem_rs2_data[15:0], 8'b0} :
                          (dmem_byte_addr[1:0] == 2'b10) ? {ex_mem_rs2_data[15:0], 16'b0} :
                          32'b0
                          ) :
                         (
                          (dmem_byte_addr[1:0] == 2'b00) ? {24'b0, ex_mem_rs2_data[7:0]} :
                          (dmem_byte_addr[1:0] == 2'b01) ? {16'b0, ex_mem_rs2_data[7:0], 8'b0} :
                          (dmem_byte_addr[1:0] == 2'b10) ? {8'b0, ex_mem_rs2_data[7:0], 16'b0} :
                          {ex_mem_rs2_data[7:0], 24'b0}
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
                           ex_mem_rd_sel[3] ?
                           (
                            ex_mem_memw ? i_dmem_rdata :
                            ex_mem_memh ?
                            (
                             ex_mem_memu ?
                             {16'b0, load_half} :
                             {{16{load_half[15]}}, load_half}
                             ) :
                            (
                             ex_mem_memu ?
                             {24'b0, load_byte} :
                             {{24{load_byte[7]}}, load_byte}
                             )
                            ) :
                           ex_mem_rd_sel[2] ? (ex_mem_pc + 32'd4) :
                           ex_mem_rd_sel[1] ? ex_mem_imm :
                           ex_mem_rd_sel[0] ? ex_mem_alu_result :
                           32'b0;


    // ================================================================
    // REGISTER MEM/WB
    // ================================================================

    reg [31:0] mem_wb_writeback_data;
	reg [31:0] mem_wb_pc;
	reg [31:0] mem_wb_next_pc;
	reg [31:0] mem_wb_inst;
	reg mem_wb_valid;
	
	reg [4:0]  mem_wb_rs1;
	reg [4:0]  mem_wb_rs2;
	reg [31:0] mem_wb_rs1_data;
	reg [31:0] mem_wb_rs2_data;
	
	reg [4:0]  mem_wb_rd;
	reg [3:0]  mem_wb_rd_sel;
	
	reg [31:0] mem_wb_dmem_addr;
	reg [3:0]  mem_wb_dmem_mask;
	reg        mem_wb_dmem_ren;
	reg        mem_wb_dmem_wen;
	reg [31:0] mem_wb_dmem_rdata;
	reg [31:0] mem_wb_dmem_wdata;
	
	reg        mem_wb_legal;
	reg        mem_wb_halt;
	reg        mem_wb_trap;
	
    always @(posedge i_clk) begin
        if (i_rst) begin
            mem_wb_writeback_data <= 32'b0;
            mem_wb_pc             <= 32'b0;
			mem_wb_next_pc      <= 32'b0;
			mem_wb_inst         <= 32'b0;
			mem_wb_rs1          <= 5'd0;
			mem_wb_rs2          <= 5'd0;
			mem_wb_rs1_data     <= 32'b0;
			mem_wb_rs2_data     <= 32'b0;
            mem_wb_rd             <= 5'd0;
            mem_wb_rd_sel         <= 4'b0;
			mem_wb_dmem_addr    <= 32'b0;
			mem_wb_dmem_mask    <= 4'b0;
			mem_wb_dmem_ren     <= 1'b0;
			mem_wb_dmem_wen     <= 1'b0;
			mem_wb_dmem_rdata   <= 32'b0;
			mem_wb_dmem_wdata   <= 32'b0;
            mem_wb_legal          <= 1'b0;
            mem_wb_halt           <= 1'b0;
            mem_wb_trap           <= 1'b0;
        end else begin
            mem_wb_writeback_data <= writeback_data;
            mem_wb_pc             <= ex_mem_pc;
			mem_wb_next_pc        <= ex_mem_next_pc;
			mem_wb_inst           <= ex_mem_inst;
    		mem_wb_rs1            <= ex_mem_rs1;
    		mem_wb_rs2            <= ex_mem_rs2;
    		mem_wb_rs1_data       <= ex_mem_rs1_data;
   			mem_wb_rs2_data       <= ex_mem_rs2_data;
            mem_wb_rd             <= ex_mem_rd;
            mem_wb_rd_sel         <= ex_mem_rd_sel;
			mem_wb_dmem_addr      <= o_dmem_addr;
    		mem_wb_dmem_mask      <= o_dmem_mask;
    		mem_wb_dmem_ren       <= o_dmem_ren;
    		mem_wb_dmem_wen       <= o_dmem_wen;
    		mem_wb_dmem_rdata     <= i_dmem_rdata;
    		mem_wb_dmem_wdata     <= o_dmem_wdata;
            mem_wb_legal          <= ex_mem_legal;
            mem_wb_halt           <= ex_mem_halt;
            mem_wb_trap           <= ex_mem_trap;
        end
    end

    assign o_retire_trap = mem_wb_trap;
    assign o_retire_trap = mem_wb_trap;
	assign o_retire_next_pc = mem_wb_next_pc;
	
	assign o_retire_inst       = mem_wb_inst;
	assign o_retire_halt       = mem_wb_halt;

	assign o_retire_rs1_raddr  = mem_wb_rs1;
	assign o_retire_rs2_raddr  = mem_wb_rs2;
	assign o_retire_rs1_rdata  = mem_wb_rs1_data;
	assign o_retire_rs2_rdata  = mem_wb_rs2_data;

	assign o_retire_rd_waddr =
    	(mem_wb_legal && !mem_wb_halt && !mem_wb_trap)
    	? mem_wb_rd : 5'd0;

	assign o_retire_rd_wdata  = mem_wb_writeback_data;

	assign o_retire_dmem_addr  = mem_wb_dmem_addr;
	assign o_retire_dmem_mask  = mem_wb_dmem_mask;
	assign o_retire_dmem_ren   = mem_wb_dmem_ren;
	assign o_retire_dmem_wen   = mem_wb_dmem_wen;
	assign o_retire_dmem_rdata = mem_wb_dmem_rdata;
	assign o_retire_dmem_wdata = mem_wb_dmem_wdata;

	assign o_retire_pc         = mem_wb_pc;
    
endmodule

// ##################################
// HAZARD CONTROL
// our job is to DETECT HAZARDS (data AND control)
// and STALL/FLUSH IF NECESSARY
// we don't handle FORWARDING or BYPASSING...
module hazardctrl
  #(
     parameter FWD_EN = 1,   // we need to know if our machine will handle forwarding
     parameter BYPASS_EN = 1 // or bypassing, because if we can't, we need to stall
    )
    (
     // INPUTS:
     // ID
      input wire [4:0] i_id_rs1,    // potential RAW or Load-Use hazard
      input wire [4:0] i_id_rs2,    // potential RAW or Load-Store hazard
      input wire       i_id_store,  // necessary to see if load->store is happening
     // EX
      input wire [4:0] i_ex_rd,     // W part of RAW
      input wire [4:0] i_ex_rs1,    // destination for forwarding
      input wire [4:0] i_ex_rs2,    // destination for forwarding
      input wire       i_ex_load,   // necessary to see if load->store is happening
      input wire       i_ex_btaken, // true if we TAKE a branch in i_ex (later: implement better prediction)
     // MEM
      input wire [4:0] i_mem_rd,  // W part of RAW
     // WB
      input wire [4:0] i_wb_rd,   // W part of RAW
    
     // OUTPUTS:
     // IF
      output wire o_if_hold, // stall PC and disable IF/ID write
     // ID
      output wire o_id_nop // bubble/flush
     );

    // data hazards
    wire ex_match_rs1, ex_match_rs2;
    wire mem_match_rs1, mem_match_rs2;
    wire wb_match_rs1, wb_match_rs2;
    wire load_store_hazard;
    wire stall;

    // control hazards
    wire flush;

    assign ex_match_rs1 = (i_id_rs1 != 5'd0) &&
                          (i_ex_rd != 5'd0) &&
                          (i_id_rs1 == i_ex_rd);

    assign ex_match_rs2 = (i_id_rs2 != 5'd0) &&
                          (i_ex_rd != 5'd0) &&
                          (i_id_rs2 == i_ex_rd);
    
    assign mem_match_rs1 = (i_id_rs1 != 5'd0) &&
                           (i_mem_rd != 5'd0) &&
                           (i_id_rs1 == i_mem_rd);

    assign mem_match_rs2 = (i_id_rs2 != 5'd0) &&
                           (i_mem_rd != 5'd0) &&
                           (i_id_rs2 == i_mem_rd);
    
    assign wb_match_rs1 = (i_id_rs1 != 5'd0) &&
                          (i_wb_rd != 5'd0) &&
                          (i_id_rs1 == i_wb_rd);

    assign wb_match_rs2 = (i_id_rs2 != 5'd0) &&
                          (i_wb_rd != 5'd0) &&
                          (i_id_rs2 == i_wb_rd);

    assign flush = i_ex_btaken; // later: implement better prediction

    
    generate
        // see g_none first for baseline
        if (FWD_EN && BYPASS_EN) begin : g_bypass_forwarding
            // we can't forward from a load...
            // UNLESS we're doing load->store where store is storing loaded value
            // only reason we CAN'T forward is
            // load->store where store needs to use loaded value as offset
            // that is, load rd == store rs1
            // if load rd == store rs2, we can just mem->mem forward
            assign stall = i_ex_load & (ex_match_rs1 |
                                        (ex_match_rs2 & i_id_store));
        end else if (FWD_EN) begin : g_forwarding
            // this should honestly not be a case that happens
            // so let's just "throw an error"
            assign stall = 1'b1;
        end else if (BYPASS_EN) begin : g_bypass
            // baseline MINUS wb matches (since we can bypass)
            assign stall = ex_match_rs1 | ex_match_rs2 |
                           mem_match_rs1 | mem_match_rs2;
        end else begin : g_none
            // baseline: any matches are bad
            assign stall = ex_match_rs1 | ex_match_rs2 |
                           mem_match_rs1 | mem_match_rs2 |
                           wb_match_rs1 | wb_match_rs2;
        end
    endgenerate

    assign o_if_hold = stall & ~flush;
    assign o_id_nop  = stall | flush;
endmodule

`default_nettype wire
