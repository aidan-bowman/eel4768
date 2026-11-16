`default_nettype none

/* FETCH
 *
 * this module is responsible for fetching and storing the next instruction
 * it contains both the IF stage logic and the IF/ID register
 */
module fetch
  #(
    parameter RESET_ADDR = 32'h00400000,
    parameter NOP = 32'h00000013,
    // cache info
    parameter EVICT_POLICY = 0,
    parameter NUM_WAYS = 1,
    parameter CACHE_SIZE = 16,
    parameter BLOCK_SIZE = 128,
    parameter PREFETCH_EN = 0
    )
    (
     input wire                    i_clk,
     input wire                    i_rst,
     
     // CPU
     input wire                    i_stall,       // high when hazardctrl needs us to stall
     output wire                   o_icachestall, // output high when icache is stalling
     
     input wire                    i_jump,        // high when we jump or branch
     input wire [31:0]             i_jumpaddr,
     output reg [31:0]             o_pc,
     output reg [31:0]             o_instr,
     output reg                    o_nop,         // high when this instruction is just a nop
     
     // imem
     output wire                   o_imem_rd,
     output wire [31:0]            o_imem_rd_addr,
     input wire                    i_imem_valid,
     input wire [BLOCK_SIZE*8-1:0] i_imem_rd_data
     );

    // =============================================================
    // Main logic
    // =============================================================
    
    reg  [31:0] pc;
    wire [31:0] next_pc;
    wire        stalling;
    
    wire        icache_stall;
    wire [31:0] icache_rdata;

    assign stalling = icache_stall | i_stall;    

    assign next_pc = i_jump ? i_jumpaddr : pc + 4;

    always @(posedge i_clk) begin
        if (i_rst) begin
            pc <= RESET_ADDR;
        end else if (!stalling) begin
            pc <= next_pc;
        end
    end
    
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

    // =============================================================
    // IF/ID reg
    // =============================================================

    always @(posedge i_clk) begin
        if (i_rst) begin
            o_pc    <= 32'b0;
            o_instr <= NOP;
            o_nop <= 1'b1;
        end else if (!stalling) begin
            o_pc    <= pc;
            o_instr <= i_jump ? NOP : icache_rdata;
            o_nop   <= i_jump ? 1'b1 : 1'b0;
        end
    end

    assign o_icachestall = icache_stall;
    
endmodule
