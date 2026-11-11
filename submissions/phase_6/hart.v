`default_nettype none

module hart
  #(// After reset, the program counter (PC) should be initialized to this
    // address and start executing instructions from there.
    parameter RESET_ADDR = 32'h00400000,
    // When set, pipeline forwarding optimizations are enabled.
    parameter FWD_EN = 1,
    // When set, register file bypassing is enabled.              
    parameter BYPASS_EN = 1,
    // Cache configuration. Pass these down unchanged to the instruction
    // cache and the data cache (see cache.v). The testbench sets all five,
    // so these defaults are never used for grading.
    parameter EVICT_POLICY = 0,
    parameter NUM_WAYS = 1,
    parameter CACHE_SIZE = 16,
    parameter BLOCK_SIZE = 128,
    parameter PREFETCH_EN = 0
       ) (
          // Global clock.
          input wire                     i_clk,
          // Synchronous active-high reset.
          input wire                     i_rst,
          // Phase 4's combinational instruction and data memory ports are now
          // internal: they connect the pipeline to two `cache` instances inside
          // the hart, one for instructions and one for data. What leaves the hart
          // is the caches' memory side, one block (BLOCK_SIZE bytes) per transfer,
          // against a main memory with a fixed delay:
          //  * o_*mem_rd is a one-cycle request for the line at o_*mem_rd_addr
          //    (line aligned); i_*mem_valid is high for one cycle when that line
          //    is on i_*mem_rd_data. Requests are answered in order.
          //  * o_dmem_wr is a one-cycle line write; o_dmem_wr_be has one bit per
          //    byte (all ones for a dirty write-back, only the stored bytes for a
          //    write-through). Instructions are read only, so there is no
          //    instruction-side write port.
          output wire                    o_imem_rd,
          output wire [31:0]             o_imem_rd_addr,
          input wire                     i_imem_valid,
          input wire [BLOCK_SIZE*8-1:0]  i_imem_rd_data,
          output wire                    o_dmem_rd,
          output wire [31:0]             o_dmem_rd_addr,
          input wire                     i_dmem_valid,
          input wire [BLOCK_SIZE*8-1:0]  i_dmem_rd_data,
          output wire                    o_dmem_wr,
          output wire [31:0]             o_dmem_wr_addr,
          output wire [BLOCK_SIZE*8-1:0] o_dmem_wr_data,
          output wire [BLOCK_SIZE-1:0]   o_dmem_wr_be,
  
          // The output `retire` interface is used to signal to the testbench that
          // the CPU has completed and retired an instruction. A single cycle
          // implementation will assert this every cycle; however, a pipelined
          // implementation that needs to stall (due to internal hazards or waiting
          // on memory accesses) will not assert the signal on cycles where the
          // instruction in the writeback stage is not retiring.
          //
          // Asserted when an instruction is being retired this cycle. If this is
          // not asserted, the other retire signals are ignored and may be left invalid.
          output wire                    o_retire_valid,
          // The 32 bit instruction word of the instrution being retired. This
          // should be the unmodified instruction word fetched from instruction
          // memory.
          output wire [31:0]             o_retire_inst,
          // Asserted if the instruction produced a trap, due to an illegal
          // instruction, unaligned data memory access, or unaligned instruction
          // address on a taken branch or jump.
          output wire                    o_retire_trap,
          // Asserted if the instruction is an `ebreak` instruction used to halt the
          // processor. This is used for debugging and testing purposes to end
          // a program.
          output wire                    o_retire_halt,
          // The first register address read by the instruction being retired. If
          // the instruction does not read from a register (like `lui`), this
          // should be 5'd0.
          output wire [ 4:0]             o_retire_rs1_raddr,
          // The second register address read by the instruction being retired. If
          // the instruction does not read from a second register (like `addi`), this
          // should be 5'd0.
          output wire [ 4:0]             o_retire_rs2_raddr,
          // The first source register data read from the register file (in the
          // decode stage) for the instruction being retired. If rs1 is 5'd0, this
          // should also be 32'd0.
          output wire [31:0]             o_retire_rs1_rdata,
          // The second source register data read from the register file (in the
          // decode stage) for the instruction being retired. If rs2 is 5'd0, this
          // should also be 32'd0.
          output wire [31:0]             o_retire_rs2_rdata,
          // The destination register address written by the instruction being
          // retired. If the instruction does not write to a register (like `sw`),
          // this should be 5'd0.
          output wire [ 4:0]             o_retire_rd_waddr,
          // The destination register data written to the register file in the
          // writeback stage by this instruction. If rd is 5'd0, this field is
          // ignored and can be treated as a don't care.
          output wire [31:0]             o_retire_rd_wdata,
          output wire [31:0]             o_retire_dmem_addr,
          output wire [ 3:0]             o_retire_dmem_mask,
          output wire                    o_retire_dmem_ren,
          output wire                    o_retire_dmem_wen,
          output wire [31:0]             o_retire_dmem_rdata,
          output wire [31:0]             o_retire_dmem_wdata,
          // The current program counter of the instruction being retired - i.e.
          // the instruction memory address that the instruction was fetched from.
          output wire [31:0]             o_retire_pc,
          // the next program counter after the instruction is retired. For most
          // instructions, this is `o_retire_pc + 4`, but must be the branch or jump
          // target for *taken* branches and jumps.
          output wire [31:0]             o_retire_next_pc,
          // F extension retire fields. The floating-point source registers read
          // by the instruction being retired (addresses are the instruction's rs1,
          // rs2 and rs3 fields) and their values as read in the decode stage; they
          // are only meaningful for instructions that read them.
          output wire [ 4:0]             o_retire_frs1_raddr,
          output wire [31:0]             o_retire_frs1_rdata,
          output wire [ 4:0]             o_retire_frs2_raddr,
          output wire [31:0]             o_retire_frs2_rdata,
          output wire [ 4:0]             o_retire_frs3_raddr,
          output wire [31:0]             o_retire_frs3_rdata,
          // Asserted when the instruction being retired writes floating-point
          // register `o_retire_frd_waddr` with `o_retire_frd_wdata`. (f0 is an
          // ordinary register, so an enable is needed.)
          output wire                    o_retire_frd_wen,
          output wire [ 4:0]             o_retire_frd_waddr,
          output wire [31:0]             o_retire_frd_wdata,
          // The accrued floating-point exception flags (fflags) after the
          // instruction being retired.
          output wire [ 4:0]             o_retire_fflags
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

    
    wire        icache_stall;
    wire [31:0] icache_rdata;
	wire        cache_hold;

    cache #(
        .EVICT_POLICY(EVICT_POLICY),
        .NUM_WAYS(NUM_WAYS),
        .CACHE_SIZE(CACHE_SIZE),
        .BLOCK_SIZE(BLOCK_SIZE),
        .PREFETCH_EN(PREFETCH_EN)
    ) icache (
        .i_clk(i_clk),
        .i_rst(i_rst),

        // CPU-side instruction request
        .i_ren(1'b1),
        .i_wen(1'b0),
        .i_addr(pc),
        .i_mask(4'b1111),
        .i_wdata(32'b0),
        .o_stall(icache_stall),
        .o_rdata(icache_rdata),

        // External memory-side interface
        .o_mem_rd(o_imem_rd),
        .o_mem_rd_addr(o_imem_rd_addr),
        .i_mem_valid(i_imem_valid),
        .i_mem_rd_data(i_imem_rd_data),
        .o_mem_wr(),
        .o_mem_wr_addr(),
        .o_mem_wr_data(),
        .o_mem_wr_be()
    );

    
    assign pc_plus_4 = pc + 32'd4;
    
    assign next_pc = if_hold ? pc :
                     jump_taken ? jump_target :
                     ex_branchtaken ? ex_branchtarget :
                     pc_plus_4;
    
    // =============================================================
    // REGISTER IF/ID
    // =============================================================

    reg [31:0] if_id_pc;
    reg [31:0] if_id_nextpc; // for retire interface
    reg [31:0] if_id_inst;

    always @(posedge i_clk) begin
        if (i_rst) begin
            pc         <= RESET_ADDR;
            if_id_pc   <= 32'b0;
            if_id_inst <= 32'b0;
            if_id_nextpc <= 32'b0;
        end else if (if_hold || cache_hold) begin
            // don't update anything
        end else begin
            if_id_pc   <= pc;
            if_id_inst <= icache_rdata;
            pc         <= next_pc;
            if_id_nextpc <= next_pc;
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

    wire        mext;
    wire        fpu_en;

    wire        frs1_en;
    wire        frs2_en;
    wire        frs3_en;

    wire [4:0]  rs3;
    wire        frd_en;

    wire [4:0]  rd_sel;

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

                     .o_pc_sel(pc_alu_sel),

                     .o_mext(mext),
                     .o_fpu(fpu_en),

                     .o_frs1_en(frs1_en),
                     .o_frs2_en(frs2_en),
                     .o_frs3_en(frs3_en),

                     .o_rs3(rs3),
                     .o_frd_en(frd_en)
                     );

    // ================================================================
    // STAGE 2.5: REGISTERS
    // ================================================================

    wire [31:0] rs1_data;
    wire [31:0] rs2_data;
    
    wire [31:0] frs1_data;
    wire [31:0] frs2_data;
    wire [31:0] frs3_data;

    wire [31:0] writeback_data;

    // A misaligned or illegal instruction must not write a register.
    // Driving x0 to the write address is how Phase 3 disables writes.
    wire [4:0] rf_rd_waddr =
    (mem_wb_legal & !mem_wb_halt & !mem_wb_trap && !cache_hold)
    ? mem_wb_rd : 5'd0;

    rf #(
         .BYPASS_EN(BYPASS_EN)
         ) rf (
               .i_clk(i_clk),
               .i_rst(i_rst),
               
               .i_rs1_raddr(rs1),
               .o_rs1_rdata(rs1_data),

               .i_rs2_raddr(rs2),
               .o_rs2_rdata(rs2_data),

               .i_frs1_raddr(if_id_inst[19:15]),
               .o_frs1_rdata(frs1_data),

               .i_frs2_raddr(if_id_inst[24:20]),
               .o_frs2_rdata(frs2_data),

               .i_frs3_raddr(rs3),
               .o_frs3_rdata(frs3_data),

               .i_frd_wen(mem_wb_frd_en),
               .i_frd_waddr(mem_wb_frd),
               .i_frd_wdata(mem_wb_fp_rdata),

               .i_rd_waddr(rf_rd_waddr),
               .i_rd_wdata(mem_wb_writeback_data)
               );

    
    // ================================================================
    // REGISTER ID/EX
    // ================================================================

    reg [31:0] id_ex_pc;
    reg [31:0] id_ex_nextpc; // for retire interface
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

    reg [4:0]  id_ex_rd_sel;

    reg        id_ex_legal;
    reg        id_ex_halt;
    reg        id_ex_trap;

    reg [31:0] id_ex_frs1_data;
    reg [31:0] id_ex_frs2_data;
    reg [31:0] id_ex_frs3_data;

    reg [4:0]  id_ex_frs1;
    reg [4:0]  id_ex_frs2;
    reg [4:0]  id_ex_frs3;

    reg        id_ex_frs1_en;
    reg        id_ex_frs2_en;
    reg        id_ex_frs3_en;

    reg        id_ex_fpu_en;

    reg        id_ex_frd_en;
    reg [4:0]  id_ex_frd;
    
    always @(posedge i_clk) begin
        if (i_rst) begin
            id_ex_pc              <= 32'b0;
            id_ex_nextpc          <= 32'b0;
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
            id_ex_rd_sel          <= 5'b0;
            id_ex_legal           <= 1'b0;
            id_ex_halt            <= 1'b0;
            id_ex_trap            <= 1'b0;
            
            id_ex_frs1_data       <= 32'b0;
            id_ex_frs2_data       <= 32'b0;
            id_ex_frs3_data       <= 32'b0;

            id_ex_frs1            <= 5'b0;
            id_ex_frs2            <= 5'b0;
            id_ex_frs3            <= 5'b0;
                              

            id_ex_frs1_en         <= 1'b0;
            id_ex_frs2_en         <= 1'b0;
            id_ex_frs3_en         <= 1'b0;

            id_ex_fpu_en          <= 1'b0;

            id_ex_frd_en          <= 1'b0;
            id_ex_frd             <= 5'b0;
        end else if (cache_hold) begin
            // Hold all ID/EX registers while the cache is waiting.
        end else if (id_nop) begin
            id_ex_pc              <= 32'b0;
            id_ex_nextpc          <= 32'b0;
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
            id_ex_rd_sel          <= 5'b0;
            id_ex_legal           <= 1'b0;
            id_ex_halt            <= 1'b0;
            id_ex_trap            <= 1'b0;
            
            id_ex_frs1_data       <= 32'b0;
            id_ex_frs2_data       <= 32'b0;
            id_ex_frs3_data       <= 32'b0;

            id_ex_frs1            <= 5'b0;
            id_ex_frs2            <= 5'b0;
            id_ex_frs3            <= 5'b0;
                              

            id_ex_frs1_en         <= 1'b0;
            id_ex_frs2_en         <= 1'b0;
            id_ex_frs3_en         <= 1'b0;

            id_ex_fpu_en          <= 1'b0;

            id_ex_frd_en          <= 1'b0;
            id_ex_frd             <= 5'b0;
        end else begin
            id_ex_pc              <= if_id_pc;
            id_ex_nextpc          <= if_id_nextpc;
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
            
            id_ex_frs1_data       <= frs1_data;
            id_ex_frs2_data       <= frs2_data;
            id_ex_frs3_data       <= frs3_data;

            id_ex_frs1            <= rs1;
            id_ex_frs2            <= rs2;
            id_ex_frs3            <= rs3;

            id_ex_frs1_en         <= frs1_en;
            id_ex_frs2_en         <= frs2_en;
            id_ex_frs3_en         <= frs3_en;

            id_ex_fpu_en          <= fpu_en;

            id_ex_frd_en          <= frd_en;
            id_ex_frd             <= frd_en ? if_id_inst[11:7] : 5'd0;
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


	// EX->EX forwarding

	assign forward_ex_rs1 = FWD_EN &&
    		                (ex_mem_rd != 5'd0) &&
    		                ex_mem_legal &&
    		                !ex_mem_halt &&
    		                !ex_mem_memread &&
    		                (ex_mem_rd == id_ex_rs1);

	assign forward_ex_rs2 = FWD_EN &&
    		                (ex_mem_rd != 5'd0) &&
    		                ex_mem_legal &&
    		                !ex_mem_halt &&
    		                !ex_mem_memread &&
    		                (ex_mem_rd == id_ex_rs2);


	// MEM->EX forwarding

	assign forward_wb_rs1 = FWD_EN &&
    		                (mem_wb_rd != 5'd0) &&
    		                mem_wb_legal &&
    		                !mem_wb_halt &&
    		                (mem_wb_rd == id_ex_rs1);

	assign forward_wb_rs2 = FWD_EN &&
    		                (mem_wb_rd != 5'd0) &&
    		                mem_wb_legal &&
    		                !mem_wb_halt &&
    		                (mem_wb_rd == id_ex_rs2);


	// Forwarding multiplexers

	assign forward_rs1_data = forward_ex_rs1 ? ex_mem_alu_result :
    		                  forward_wb_rs1 ? mem_wb_writeback_data :
        		              id_ex_rs1_data;

	assign forward_rs2_data = forward_ex_rs2 ? ex_mem_alu_result :
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
    // FPU
    // ================================================================

    wire        fpu_busy; // used for cache_hold
    wire [31:0] fpu_fp_res;
    wire [31:0] fpu_int_res;
    wire [ 4:0] fpu_fflags;
    wire        fpu_rm_trap;

    fpu fpu (
             .i_clk(i_clk),
             .i_rst(i_rst),
             .i_inst(id_ex_inst),
             .i_valid(id_ex_legal & id_ex_fpu_en),
             .i_advance(~cache_hold), // we advance when the cache is not held
             .i_frs1(id_ex_frs1_data),
             .i_frs2(id_ex_frs2_data),
             .i_frs3(id_ex_frs3_data),
             .i_xrs1(id_ex_rs1_data),
             .o_fp_result(fpu_fp_res),
             .o_int_result(fpu_int_res),
             .o_fflags(fpu_fflags),
             .o_busy(fpu_busy),
             .o_rm_trap(fpu_rm_trap)
             );

    // ================================================================
    // REGISTER EX/MEM
    // ================================================================

    reg [31:0] ex_mem_alu_result;
	reg [31:0] ex_mem_rs2_data;
	reg [31:0] ex_mem_rs1_data;
	reg [31:0] ex_mem_pc;
	reg [31:0] ex_mem_nextpc;
	reg        ex_mem_valid;
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

    reg [4:0]  ex_mem_rd_sel;

    reg        ex_mem_legal;
    reg        ex_mem_halt;
    reg        ex_mem_trap;

    reg [31:0] ex_mem_fp_rdata;
    reg [31:0] ex_mem_fpu_int_res;
    reg [ 4:0] ex_mem_fpu_fflags;
    reg        ex_mem_frd_en;
    reg [4:0]  ex_mem_frd;

    reg [4:0]  ex_mem_frs1;
    reg [31:0] ex_mem_frs1_data;
    reg [4:0]  ex_mem_frs2;
    reg [31:0] ex_mem_frs2_data;
    reg [4:0]  ex_mem_frs3;
    reg [31:0] ex_mem_frs3_data;
    reg        ex_mem_frs2_en;


    always @(posedge i_clk) begin
        if (i_rst) begin
            ex_mem_alu_result  <= 32'b0;
            ex_mem_rs2_data    <= 32'b0;
            ex_mem_pc          <= 32'b0;
			ex_mem_nextpc      <= 32'b0;
            ex_mem_imm         <= 32'b0;
			ex_mem_inst        <= 32'b0;
			ex_mem_rs1_data    <= 32'b0;
			ex_mem_rs1         <= 5'd0;
			ex_mem_rs2         <= 5'd0;
            ex_mem_rd          <= 5'd0;
            ex_mem_memread     <= 1'b0;
            ex_mem_memwrite    <= 1'b0;
            ex_mem_memalign    <= 2'b0;
            ex_mem_memb        <= 1'b0;
            ex_mem_memh        <= 1'b0;
            ex_mem_memw        <= 1'b0;
            ex_mem_memu        <= 1'b0;
            ex_mem_rd_sel      <= 5'b0;
            ex_mem_legal       <= 1'b0;
            ex_mem_halt        <= 1'b0;
            ex_mem_trap        <= 1'b0;
            
            ex_mem_fp_rdata  <= 32'b0;
            ex_mem_fpu_int_res <= 32'b0;
            ex_mem_fpu_fflags  <= 5'b0;
            
            ex_mem_frd_en      <= 1'b0;
            ex_mem_frd         <= 5'b0;
            
            ex_mem_frs1        <= 5'b0;
            ex_mem_frs1_data   <= 32'b0;
            ex_mem_frs2        <= 5'b0;
            ex_mem_frs2_data   <= 32'b0;
            ex_mem_frs3        <= 5'b0;
            ex_mem_frs3_data   <= 32'b0;
            ex_mem_frs2_en     <= 1'b0;
		end else if (cache_hold) begin
        	// Hold all EX/MEM registers while the cache is waiting.
        end else begin
            ex_mem_alu_result  <= alu_result;
            ex_mem_rs2_data    <= id_ex_rs2_data;
            ex_mem_pc          <= id_ex_pc;
			ex_mem_nextpc      <= id_ex_nextpc;
			ex_mem_inst        <= id_ex_inst;
			ex_mem_rs1_data    <= forward_rs1_data;
            ex_mem_rs2_data    <= forward_rs2_data;
			ex_mem_rs1         <= id_ex_rs1;
			ex_mem_rs2         <= id_ex_rs2;
            ex_mem_imm         <= id_ex_imm;
            ex_mem_rd          <= id_ex_rd;
            ex_mem_memread     <= id_ex_memread;
            ex_mem_memwrite    <= id_ex_memwrite;
            ex_mem_memalign    <= id_ex_memalign;
            ex_mem_memb        <= id_ex_memb;
            ex_mem_memh        <= id_ex_memh;
            ex_mem_memw        <= id_ex_memw;
            ex_mem_memu        <= id_ex_memu;
            ex_mem_rd_sel      <= id_ex_rd_sel;
            ex_mem_legal       <= id_ex_legal;
            ex_mem_halt        <= id_ex_halt;
            ex_mem_trap        <= id_ex_trap || fpu_rm_trap;
            
            ex_mem_fp_rdata    <= fpu_fp_res;
            ex_mem_fpu_int_res <= fpu_int_res;
            ex_mem_fpu_fflags  <= fpu_fflags;
            
            ex_mem_frd_en      <= id_ex_frd_en;
            ex_mem_frd         <= id_ex_frd;
            
            ex_mem_frs1        <= id_ex_frs1;
            ex_mem_frs1_data   <= id_ex_frs1_data;
            ex_mem_frs2        <= id_ex_frs2;
            ex_mem_frs2_data   <= id_ex_frs2_data;
            ex_mem_frs3        <= id_ex_frs3;
            ex_mem_frs3_data   <= id_ex_frs3_data;
            ex_mem_frs2_en     <= id_ex_frs2_en;
        end // else: !if(cache_hold)
    end // always @ (posedge i_clk)

    // ================================================================
    // STAGE 4: MEMORY
    // ================================================================

    // ------------------------------------------------
    // Alignment
    // ------------------------------------------------
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
    assign dmem_misaligned = (ex_mem_memread | ex_mem_memwrite) &&
                             (
                              (ex_mem_memalign[0] && dmem_byte_addr[0]) ||
                              (ex_mem_memalign[1] &&
                               (dmem_byte_addr[1] | dmem_byte_addr[0]))
                              );

    // TODO: flw

    // ------------------------------------------------
    // MEM->MEM forwarding
    // ------------------------------------------------
    wire [31:0] mem_forward_rs2_data;
    wire        mem_forward_wb_rs2;

    assign mem_forward_wb_rs2 = FWD_EN &&
                                (mem_wb_rd != 5'd0) &&
                                mem_wb_legal &&
                                !mem_wb_halt &&
                                (mem_wb_rd == ex_mem_rs2);

    assign mem_forward_rs2_data = mem_forward_wb_rs2 ? mem_wb_writeback_data :
                                  ex_mem_rs2_data;

    wire [31:0] mem_forward_frs2_data;
    wire        mem_forward_wb_frs2;
    
    assign mem_forward_wb_frs2 = FWD_EN &&
                                 mem_wb_legal &&
                                 !mem_wb_halt &&
                                 mem_wb_frd_en &&
                                 (mem_wb_frd == ex_mem_frs2);

    assign mem_forward_frs2_data = mem_forward_wb_frs2 ? mem_wb_fp_rdata :
                                   ex_mem_fp_rdata;

    // ------------------------------------------------
    // dcache
    // ------------------------------------------------
    wire [31:0] dmem_byte_addr;
    assign dmem_byte_addr = ex_mem_alu_result;
    
    wire        dcache_stall;
    wire [31:0] dcache_rdata;
    wire [31:0] dcache_addr;
    wire [3:0]  dcache_mask;
    wire        dcache_ren;
    wire        dcache_wen;
    wire [31:0] dcache_wdata;

    assign dcache_addr= {dmem_byte_addr[31:2], 2'b00};

    assign dcache_ren = ex_mem_memread &&
                        ex_mem_legal &&
                        !ex_mem_halt &&
                        !dmem_misaligned &&
                        !fpu_busy;

    assign dcache_wen = ex_mem_memwrite &&
                        ex_mem_legal &&
                        !ex_mem_halt &&
                        !dmem_misaligned &&
                        !fpu_busy;

	assign cache_hold = icache_stall ||
                    	((dcache_ren || dcache_wen) && dcache_stall) ||
                        fpu_busy; // this should probably be moved elsewhere

    assign dcache_mask = ex_mem_memw ? 4'b1111 :
                         ex_mem_memh ? half_mask :
                         byte_mask;

    assign dcache_wdata = ex_mem_frs2_en ? mem_forward_frs2_data :
                          ex_mem_memw ? mem_forward_rs2_data :
                          ex_mem_memh ?
                          (
                           (dmem_byte_addr[1:0] == 2'b00) ? {16'b0, mem_forward_rs2_data[15:0]} :
                           (dmem_byte_addr[1:0] == 2'b01) ? {8'b0, mem_forward_rs2_data[15:0], 8'b0} :
                           (dmem_byte_addr[1:0] == 2'b10) ? {mem_forward_rs2_data[15:0], 16'b0} :
                           32'b0
                           ) :
                          (
                           (dmem_byte_addr[1:0] == 2'b00) ? {24'b0, mem_forward_rs2_data[7:0]} :
                           (dmem_byte_addr[1:0] == 2'b01) ? {16'b0, mem_forward_rs2_data[7:0], 8'b0} :
                           (dmem_byte_addr[1:0] == 2'b10) ? {8'b0, mem_forward_rs2_data[7:0], 16'b0} :
                           {mem_forward_rs2_data[7:0], 24'b0}
                           );

    cache #(
        .EVICT_POLICY(EVICT_POLICY),
        .NUM_WAYS(NUM_WAYS),
        .CACHE_SIZE(CACHE_SIZE),
        .BLOCK_SIZE(BLOCK_SIZE),
        .PREFETCH_EN(PREFETCH_EN)
    ) dcache (
        .i_clk(i_clk),
        .i_rst(i_rst),

        .i_ren(dcache_ren),
        .i_wen(dcache_wen),
        .i_addr(dcache_addr),
        .i_mask(dcache_mask),
        .i_wdata(dcache_wdata),
        .o_stall(dcache_stall),
        .o_rdata(dcache_rdata),

        .o_mem_rd(o_dmem_rd),
        .o_mem_rd_addr(o_dmem_rd_addr),
        .i_mem_valid(i_dmem_valid),
        .i_mem_rd_data(i_dmem_rd_data),
        .o_mem_wr(o_dmem_wr),
        .o_mem_wr_addr(o_dmem_wr_addr),
        .o_mem_wr_data(o_dmem_wr_data),
        .o_mem_wr_be(o_dmem_wr_be)
    );

    // ------------------------------------------------
    // Memory mask
    // ------------------------------------------------

    wire [3:0] byte_mask;
    wire [3:0] half_mask;

    assign byte_mask = (dmem_byte_addr[1:0] == 2'b00) ? 4'b0001 :
                       (dmem_byte_addr[1:0] == 2'b01) ? 4'b0010 :
                       (dmem_byte_addr[1:0] == 2'b10) ? 4'b0100 :
                       4'b1000;

    assign half_mask = (dmem_byte_addr[1:0] == 2'b00) ? 4'b0011 :
                       (dmem_byte_addr[1:0] == 2'b01) ? 4'b0110 :
                       (dmem_byte_addr[1:0] == 2'b10) ? 4'b1100 :
                       4'b0000;

    // ------------------------------------------------
    // Store data
    // ------------------------------------------------
	
    // ------------------------------------------------
    // Load data
    // ------------------------------------------------

    wire [7:0] load_byte;
    wire [15:0] load_half;

    assign load_byte = (dmem_byte_addr[1:0] == 2'b00) ? dcache_rdata[7:0] :
                       (dmem_byte_addr[1:0] == 2'b01) ? dcache_rdata[15:8] :
                       (dmem_byte_addr[1:0] == 2'b10) ? dcache_rdata[23:16] :
                       dcache_rdata[31:24];

    assign load_half = (dmem_byte_addr[1:0] == 2'b00) ? dcache_rdata[15:0] :
                       (dmem_byte_addr[1:0] == 2'b01) ? dcache_rdata[23:8] :
                       (dmem_byte_addr[1:0] == 2'b10) ? dcache_rdata[31:16] :
                       16'b0;

    // TODO: move into WB phase
    assign writeback_data =
                           ex_mem_rd_sel[4] ? ex_mem_fpu_int_res :
                           ex_mem_rd_sel[3] ?
                           (
                            ex_mem_memw ? dcache_rdata :
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
	
	reg [4:0]  mem_wb_rs1;
	reg [4:0]  mem_wb_rs2;
	reg [31:0] mem_wb_rs1_data;
	reg [31:0] mem_wb_rs2_data;
	
	reg [4:0]  mem_wb_rd;
	reg [4:0]  mem_wb_rd_sel;
	
	reg [31:0] mem_wb_dmem_addr;
	reg [3:0]  mem_wb_dmem_mask;
	reg        mem_wb_dmem_ren;
	reg        mem_wb_dmem_wen;
	reg [31:0] mem_wb_dmem_rdata;
	reg [31:0] mem_wb_dmem_wdata;
	
	reg        mem_wb_legal;
	reg        mem_wb_halt;
	reg        mem_wb_trap;

    reg [ 4:0] mem_wb_fpu_fflags;
    reg [31:0] mem_wb_fp_rdata;
    reg        mem_wb_frd_en;
    reg [4:0]  mem_wb_frd;

    reg [4:0]  mem_wb_frs1;
    reg [31:0] mem_wb_frs1_data;
    reg [4:0]  mem_wb_frs2;
    reg [31:0] mem_wb_frs2_data;
    reg [4:0]  mem_wb_frs3;
    reg [31:0] mem_wb_frs3_data;
	
    always @(posedge i_clk) begin
        if (i_rst) begin
            mem_wb_writeback_data <= 32'b0;
            mem_wb_pc             <= 32'b0;
			mem_wb_next_pc        <= 32'b0;
			mem_wb_inst           <= 32'b0;
			mem_wb_rs1            <= 5'd0;
			mem_wb_rs2            <= 5'd0;
			mem_wb_rs1_data       <= 32'b0;
			mem_wb_rs2_data       <= 32'b0;
            mem_wb_rd             <= 5'd0;
            mem_wb_rd_sel         <= 5'b0;
			mem_wb_dmem_addr      <= 32'b0;
			mem_wb_dmem_mask      <= 4'b0;
			mem_wb_dmem_ren       <= 1'b0;
			mem_wb_dmem_wen       <= 1'b0;
			mem_wb_dmem_rdata     <= 32'b0;
			mem_wb_dmem_wdata     <= 32'b0;
            mem_wb_legal          <= 1'b0;
            mem_wb_halt           <= 1'b0;
            mem_wb_trap           <= 1'b0;
            
            mem_wb_fpu_fflags     <= 5'b0;
            mem_wb_fp_rdata       <= 32'b0;

            mem_wb_frs1           <= 5'b0;
            mem_wb_frs1_data      <= 32'b0;
            mem_wb_frs2           <= 5'b0;
            mem_wb_frs2_data      <= 32'b0;
            mem_wb_frs3           <= 5'b0;
            mem_wb_frs3_data      <= 32'b0;
		end else if (cache_hold) begin
            // Hold all MEM/WB registers while the cache is waiting.
        end else begin
            mem_wb_writeback_data <= writeback_data;
            mem_wb_pc             <= ex_mem_pc;
			mem_wb_next_pc        <= ex_mem_next_pc;
			mem_wb_inst           <= ex_mem_inst;
    		mem_wb_rs1            <= ex_mem_rs1;
    		mem_wb_rs2            <= ex_mem_rs2;
    		mem_wb_rs1_data       <= ex_mem_rs1_data;
   			mem_wb_rs2_data       <= mem_forward_rs2_data;
            mem_wb_rd             <= ex_mem_rd;
            mem_wb_rd_sel         <= ex_mem_rd_sel;
			mem_wb_dmem_addr      <= dcache_addr;
			mem_wb_dmem_mask      <= dcache_mask;
			mem_wb_dmem_ren       <= dcache_ren;
			mem_wb_dmem_wen       <= dcache_wen;
			mem_wb_dmem_rdata     <= dcache_rdata;
			mem_wb_dmem_wdata     <= dcache_wdata;
            mem_wb_legal          <= ex_mem_legal;
            mem_wb_halt           <= ex_mem_halt;
            mem_wb_trap           <= ex_mem_trap || dmem_misaligned;
            
            mem_wb_fpu_fflags     <= ex_mem_fpu_fflags;
            mem_wb_fp_rdata       <= ex_mem_memread ? ex_mem_fp_rdata : dcache_rdata;
            mem_wb_frd_en         <= ex_mem_frd_en;
            mem_wb_frd            <= ex_mem_frd;
            
            mem_wb_frs1           <= ex_mem_frs1;
            mem_wb_frs1_data      <= ex_mem_frs1_data;
            mem_wb_frs2           <= ex_mem_frs2;
            mem_wb_frs2_data      <= ex_mem_frs2_data;
            mem_wb_frs3           <= ex_mem_frs3;
            mem_wb_frs3_data      <= ex_mem_frs3_data;
        end // else: !if(cache_hold)
    end // always @ (posedge i_clk)

    // retire interface
    assign o_retire_valid = mem_wb_legal && !cache_hold;
      
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
    
    // fpu retires
    assign o_retire_frs1_raddr = mem_wb_frs1;
    assign o_retire_frs1_rdata = mem_wb_frs1_data;
    assign o_retire_frs2_raddr = mem_wb_frs2;
    assign o_retire_frs2_rdata = mem_wb_frs2_data;
    assign o_retire_frs3_raddr = mem_wb_frs3;
    assign o_retire_frs3_rdata = mem_wb_frs3_data;
    
    assign o_retire_frd_wen = mem_wb_frd_en;
    assign o_retire_frd_waddr = mem_wb_frd;
    assign o_retire_frd_wdata = mem_wb_fp_rdata;
    assign o_retire_fflags     = mem_wb_fpu_fflags;
    
endmodule // hart

`default_nettype none
