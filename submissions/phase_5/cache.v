`default_nettype none

`define CLOG2(x) \
   (x <= 2) ? 1 : \
   (x <= 4) ? 2 : \
   (x <= 8) ? 3 : \
   (x <= 16) ? 4 : \
   (x <= 32) ? 5 : \
   (x <= 64) ? 6 : \
   (x <= 128) ? 7 : \
   (x <= 256) ? 8 : \
   (x <= 512) ? 9 : \
   (x <= 1024) ? 10 : \
   (x <= 2048) ? 11 : \
   (x <= 4096) ? 12 : \
   (x <= 8192) ? 13 : \
   (x <= 16384) ? 14 : \
   (x <= 32768) ? 15 : \
   (x <= 65536) ? 16 : \
   (x <= 131072) ? 17 : \
   (x <= 262144) ? 18 : \
   (x <= 524288) ? 19 : \
   (x <= 1048576) ? 20 : \
   (x <= 2097152) ? 21 : \
   (x <= 4194304) ? 22 : \
   (x <= 8388608) ? 23 : \
   (x <= 16777216) ? 24 : \
   (x <= 33554432) ? 25 : \
   (x <= 67108864) ? 26 : \
   (x <= 134217728) ? 27 : \
   (x <= 268435456) ? 28 : \
   (x <= 536870912) ? 29 : \
   (x <= 1073741824) ? 30 : \
   (x <= 2147483648) ? 31 : \
   (x <= 4294967296) ? 32 : \
   -1

// A set associative cache. `hart` instantiates two of them, one as the
// instruction cache and one as the data cache, and passes the same five
// parameters to both. The replacement, write, and prefetch rules are in
// `documentation/phase_5.pdf`.
module cache
  #(
    // Replacement policy: 0 = LRU, 1 = PLRU.
    parameter EVICT_POLICY = 0,
    // Lines per set: 1    = direct mapped, the number of lines = fully associative.
    parameter NUM_WAYS = 1,
    // Data capacity in KB. Tags, valid bits and dirty bits are not counted.
    parameter CACHE_SIZE = 16,
    // Bytes per line.
    parameter BLOCK_SIZE = 128,
    // Next-line prefetch on a load miss: 1 = on, 0 = off.
    parameter PREFETCH_EN = 0,
    // these aren't part of the skeleton given to us
    // for address splitting.
    parameter OFFSET_WIDTH = `CLOG2(BLOCK_SIZE),
    parameter SETIND_WIDTH = `CLOG2((CACHE_SIZE*1024) / (BLOCK_SIZE*NUM_WAYS)),
    parameter TAG_WIDTH = 32 - OFFSET_WIDTH - SETIND_WIDTH
    ) (
       // Global clock.
       input wire                     i_clk,
       // Synchronous active-high reset.
       input wire                     i_rst,
       // CPU side: the phase 4 data memory port, plus `o_ready` to stall the
       // pipeline while the cache waits on main memory. How the cache tells the
       // pipeline to stall is up to you, so you can change these ports.
       input wire                     i_ren,
       input wire                     i_wen,
       input wire [31:0]              i_addr,
       input wire [ 3:0]              i_mask,
       input wire [31:0]              i_wdata,
       output wire                    o_stall,
       output wire [31:0]             o_rdata,
       // Memory side: one whole line (BLOCK_SIZE bytes) per transfer.
       //
       // Line read request, high for one cycle per request.
       output wire                    o_mem_rd,
       // Line-aligned address of the line to read.
       output wire [31:0]             o_mem_rd_addr,
       // High for one cycle when a requested line arrives. Memory answers
       // requests in order, after a delay set by the testbench: wait for this
       // signal instead of counting cycles.
       input wire                     i_mem_valid,
       // The whole line, valid while `i_mem_valid` is high.
       input wire [BLOCK_SIZE*8-1:0]  i_mem_rd_data,
       // Line write, high for one cycle per write. Memory applies it on that
       // clock edge.
       output wire                    o_mem_wr,
       // Line-aligned address of the write.
       output wire [31:0]             o_mem_wr_addr,
       // Write data, in place within the line.
       output wire [BLOCK_SIZE*8-1:0] o_mem_wr_data,
       // One bit per byte: all ones for a dirty write-back, only the stored
       // bytes for a write-through.
       output wire [BLOCK_SIZE-1:0]   o_mem_wr_be
       );
    
    wire [OFFSET_WIDTH-1:0] i_addr_offset;
    wire [SETIND_WIDTH-1:0] i_addr_setind;
    wire [ TAG_WIDTH-1:0]   i_addr_tag;

    assign i_addr_offset = i_addr[OFFSET_WIDTH-1 : 0];
    assign i_addr_setind = i_addr[OFFSET_WIDTH + SETIND_WIDTH-1 : OFFSET_WIDTH];
    assign i_addr_tag = i_addr[31 : SETIND_WIDTH+OFFSET_WIDTH];
    
    // TODO: connect cache_controller
    // TODO: connect data_array
    
endmodule // cache

// TODO: make sure parameters are passed down
module cache_controller
  #(
    ) (
       // Global clock.
       input wire                    i_clk,
       // Synchronous active-high reset.
       input wire                    i_rst,
       // CPU
       input wire                    i_ren,
       input wire                    i_wen,
       output wire                   o_stall,
       // cache
       input wire [SETIND_WIDTH-1:0] i_addr_setind,
       input wire [ TAG_WIDTH-1:0]   i_addr_tag,
       // data array
       output wire                   o_refill,
       output wire                   o_update,
       // main memory
       output wire                   o_mem_rd,
       input wire                    i_mem_valid,
       output wire                   o_mem_wr,
       output wire [31:0]            o_mem_wr_addr,
       output wire [BLOCK_SIZE-1:0]  o_mem_wr_be
       );

    // TODO: finish
    
    reg [TAG_WIDTH-1:0] tag[(CACHE_SIZE*1024/BLOCK_SIZE)-1:0];
    reg                 dirty[(CACHE_SIZE*1024/BLOCK_SIZE)-1:0];
    reg                 valid[(CACHE_SIZE*1024/BLOCK_SIZE)-1:0];

    genvar              i; 
    generate
        for (i = 0; i < 32; i = i + 1) begin : gen_registers
            always @(posedge i_clk) begin
                if (i_rst) begin
                    registers[i] <= 32'b0;
                end
            end
        end
    endgenerate
    
endmodule // cache_controller

// TODO: make sure parameters are passed down
module data_array
  #(
    ) (
       // global signals
      input wire                    i_clk,
      input wire                    i_rst,
      // CPU
      input wire [3:0]              i_mask,
      input wire [31:0]             i_wdata,
      output wire [31:0]            o_rdata,
      // cache
      input wire [OFFSET_WIDTH-1:0] i_addr_offset,
      // cache controller
      input wire                    i_refill,
      input wire                    i_update,
      // main memory
      input wire [BLOCK_SIZE*8-1:0] i_mem_rd_data,
      output wire [BLOCK_SIZE*8-1:0] o_mem_wr_data,
      input wire [SETIND_WIDTH-1:0] i_addr_setind,
      input wire [WAY_WIDTH-1:0]    i_way
      );

    
    // Store each cache line as an array of 32-bit words.
    reg [31:0] block [0:NUM_SETS-1]
                       [0:NUM_WAYS-1]
                       [0:(BLOCK_SIZE/4)-1];

    // Read the selected word from the selected cache line.
    assign o_rdata =
        block[i_addr_setind][i_way][i_addr_offset[OFFSET_WIDTH-1:2]];

    genvar word;
    generate
        for (word = 0; word < BLOCK_SIZE/4; word = word + 1) begin : gen_words

            // Expose the selected cache line for memory writeback.
            assign o_mem_wr_data[word*32 +: 32] =
                block[i_addr_setind][i_way][word];

            always @(posedge i_clk) begin
                // Refill the entire cache line, one word at a time.
                if (i_refill) begin
                    block[i_addr_setind][i_way][word] <=
                        i_mem_rd_data[word*32 +: 32];
                end

                // Update the selected word for a CPU store.
                else if (i_update &&
                         i_addr_offset[OFFSET_WIDTH-1:2] == word) begin

                    if (i_mask[0])
                        block[i_addr_setind][i_way][word][7:0]
                            <= i_wdata[7:0];

                    if (i_mask[1])
                        block[i_addr_setind][i_way][word][15:8]
                            <= i_wdata[15:8];

                    if (i_mask[2])
                        block[i_addr_setind][i_way][word][23:16]
                            <= i_wdata[23:16];

                    if (i_mask[3])
                        block[i_addr_setind][i_way][word][31:24]
                            <= i_wdata[31:24];
                end
            end
        end
    endgenerate

endmodule // data_array

`default_nettype wire
