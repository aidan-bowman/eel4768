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
    parameter TAG_WIDTH = 32 - OFFSET_WIDTH - SETIND_WIDTH,
    parameter WAY_WIDTH = `CLOG2(NUM_WAYS),
    parameter NUM_SETS = (CACHE_SIZE*1024) / (BLOCK_SIZE*NUM_WAYS)
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
       output wire                    o_ready,
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

       // Internal connections between the cache modules.
    wire                  refill;
    wire                  update;
    wire [WAY_WIDTH-1:0]  way;
    wire                  controller_stall;
    wire                  store_miss_write;

    wire                  mem_rd;
    wire                  mem_wr;
    wire [31:0]           mem_wr_addr;
    wire [BLOCK_SIZE-1:0] mem_wr_be;
    wire [31:0]           data_rdata;
    wire [BLOCK_SIZE*8-1:0] data_mem_wr_data;
        
    // Connect the cache controller.
    cache_controller controller (
        .i_clk(i_clk),
        .i_rst(i_rst),
        .i_ren(i_ren),
        .i_wen(i_wen),
        .o_stall(controller_stall),
        .o_store_miss(store_miss_write),
        .i_addr_setind(i_addr_setind),
        .i_addr_tag(i_addr_tag),
        .i_addr_offset(i_addr_offset),
        .i_mask(i_mask),
        .i_wdata(i_wdata),
        .o_way(way),
        .o_refill(refill),
        .o_update(update),
        .o_mem_rd(o_mem_rd),
        .o_mem_rd_addr(o_mem_rd_addr),
        .i_mem_valid(i_mem_valid),
        .o_mem_wr(o_mem_wr),
        .o_mem_wr_addr(o_mem_wr_addr),
        .o_mem_wr_be(o_mem_wr_be)
    );

    // Connect the cache data array.
    data_array data_storage (
        .i_clk(i_clk),
        .i_rst(i_rst),
        .i_mask(i_mask),
        .i_wdata(i_wdata),
        .o_rdata(data_rdata),
        .i_addr_offset(i_addr_offset),
        .i_refill(refill),
        .i_update(update),
        .i_mem_rd_data(i_mem_rd_data),
        .o_mem_wr_data(data_mem_wr_data),
        .i_addr_setind(i_addr_setind),
        .i_way(way)
    );

    // Return data from the selected cache line.
    assign o_rdata = data_rdata;

   // Forward the selected cache line for memory writeback.
   reg [BLOCK_SIZE*8-1:0] store_miss_data;
   integer store_byte_index;

   always @(*) begin
       store_miss_data = {BLOCK_SIZE*8{1'b0}};

       for (store_byte_index = 0;
            store_byte_index < 4;
            store_byte_index = store_byte_index + 1) begin

           if (i_mask[store_byte_index] &&
               (i_addr_offset + store_byte_index) < BLOCK_SIZE) begin

               store_miss_data[(i_addr_offset + store_byte_index)*8 +: 8] =
                   i_wdata[store_byte_index*8 +: 8];
           end
       end
   end

   assign o_mem_wr_data =
       store_miss_write ? store_miss_data : data_mem_wr_data;
       assign o_ready = !controller_stall;

endmodule // cache
// TODO: make sure parameters are passed down
module cache_controller
  #(
    ) (
       input wire                    i_clk,
       input wire                    i_rst,
       // CPU
       input wire                    i_ren,
       input wire                    i_wen,
       output wire                   o_stall,
       output wire                   o_store_miss,
       // cache
       input wire [SETIND_WIDTH-1:0] i_addr_setind,
       input wire [TAG_WIDTH-1:0]   i_addr_tag,
       input wire [OFFSET_WIDTH-1:0] i_addr_offset,
       input wire [3:0]              i_mask,
       input wire [31:0]             i_wdata,
       output wire [WAY_WIDTH-1:0]   o_way,
       // data array
       output wire                   o_refill,
       output wire                   o_update,
       // main memory
       output wire                   o_mem_rd,
       output wire [31:0]            o_mem_rd_addr,
       input wire                    i_mem_valid,
       output wire                   o_mem_wr,
       output wire [31:0]            o_mem_wr_addr,
       output wire [BLOCK_SIZE-1:0]  o_mem_wr_be
       );

    reg [31:0] miss_addr;
    reg [BLOCK_SIZE-1:0] store_miss_be;

    integer byte_index;
    integer meta_index;

    // Keep the CPU stalled until a read miss has been refilled.
    // A store miss completes after its write-through cycle.
    assign o_stall =
        (state != IDLE && state != STORE_DONE) ||
        (state == IDLE && (i_ren || i_wen) && !hit);

    assign o_store_miss = (state == STORE_MISS);

    assign o_mem_rd = (state == READ_REQ);

    assign o_mem_rd_addr = {
        miss_addr[31:OFFSET_WIDTH],
        {OFFSET_WIDTH{1'b0}}
    };

    assign o_mem_wr = (state == WRITEBACK) ||
                      (state == STORE_MISS);

    assign o_mem_wr_addr =
        (state == WRITEBACK)
        ? {victim_tag, miss_addr[OFFSET_WIDTH+SETIND_WIDTH-1:OFFSET_WIDTH],
           {OFFSET_WIDTH{1'b0}}}
        : {miss_addr[31:OFFSET_WIDTH], {OFFSET_WIDTH{1'b0}}};

    assign o_mem_wr_be =
        (state == WRITEBACK) ? {BLOCK_SIZE{1'b1}} :
        (state == STORE_MISS) ? store_miss_be :
        {BLOCK_SIZE{1'b0}};

    assign o_refill = (state == WAIT_MEM) && i_mem_valid;

    assign o_update = (state == IDLE) && i_wen && hit;

    assign o_way =
        (state == IDLE) ? (hit ? hit_way : victim_way) : miss_way;

    // Generate byte enables for a store miss.
    always @(*) begin
        store_miss_be = {BLOCK_SIZE{1'b0}};

        for (byte_index = 0; byte_index < 4;
             byte_index = byte_index + 1) begin
            if (i_mask[byte_index] &&
                (i_addr_offset + byte_index) < BLOCK_SIZE) begin
                store_miss_be[i_addr_offset + byte_index] = 1'b1;
            end
        end
    end

    // Controller state and cache metadata.
    always @(posedge i_clk) begin
        if (i_rst) begin
            state <= IDLE;
            miss_addr <= 32'b0;
            miss_way <= {WAY_WIDTH{1'b0}};
            victim_tag <= {TAG_WIDTH{1'b0}};
            victim_dirty <= 1'b0;

            for (meta_index = 0;
                 meta_index < CACHE_SIZE*1024/BLOCK_SIZE;
                 meta_index = meta_index + 1) begin
                tag[meta_index] <= {TAG_WIDTH{1'b0}};
                valid[meta_index] <= 1'b0;
                dirty[meta_index] <= 1'b0;
            end
        end else begin
            // A store hit updates the cache line and marks it dirty.
            if (state == IDLE && i_wen && hit) begin
                dirty[i_addr_setind * NUM_WAYS + hit_way] <= 1'b1;
            end

            case (state)
                IDLE: begin
                    if ((i_ren || i_wen) && !hit) begin
                        miss_addr <= i_addr_tag;
                        miss_addr <= {
                            i_addr_tag,
                            i_addr_setind,
                            i_addr_offset
                        };

                        if (i_wen) begin
                            // Store miss: write through, no allocation.
                            state <= STORE_MISS;
                        end else begin
                            // Read miss: select a victim and refill.
                            miss_way <= victim_way;

                            meta_index =
                                i_addr_setind * NUM_WAYS + victim_way;

                            victim_tag <= tag[meta_index];
                            victim_dirty <= valid[meta_index] &&
                                            dirty[meta_index];

                            if (valid[meta_index] &&
                                dirty[meta_index]) begin
                                state <= WRITEBACK;
                            end else begin
                                state <= READ_REQ;
                            end
                        end
                    end
                end

                WRITEBACK: begin
                    // Memory accepts the write on this clock edge.
                    state <= READ_REQ;
                end

                READ_REQ: begin
                    // Issue exactly one read request.
                    state <= WAIT_MEM;
                end

                WAIT_MEM: begin
                    if (i_mem_valid) begin
                        meta_index =
                            miss_addr[OFFSET_WIDTH + SETIND_WIDTH - 1:
                                      OFFSET_WIDTH] * NUM_WAYS + miss_way;

                        tag[meta_index] <=
                            miss_addr[31:OFFSET_WIDTH + SETIND_WIDTH];
                        valid[meta_index] <= 1'b1;
                        dirty[meta_index] <= 1'b0;

                        state <= IDLE;
                    end
                end

                STORE_MISS: begin
                    // Memory accepts the write on this clock edge.
                    state <= STORE_DONE;
                end

                STORE_DONE: begin
                    // Release the stalled CPU without allocating the line.
                    state <= IDLE;
                end

                default: begin
                    state <= IDLE;
                end
            endcase
        end
    end
    
    reg [TAG_WIDTH-1:0] tag[(CACHE_SIZE*1024/BLOCK_SIZE)-1:0];
    reg                 dirty[(CACHE_SIZE*1024/BLOCK_SIZE)-1:0];
    reg                 valid[(CACHE_SIZE*1024/BLOCK_SIZE)-1:0];

    // Controller state.
    localparam IDLE       = 3'd0;
    localparam WRITEBACK  = 3'd1;
    localparam READ_REQ   = 3'd2;
    localparam WAIT_MEM   = 3'd3;
    localparam STORE_MISS = 3'd4;
    localparam STORE_DONE = 3'd5

    reg [2:0] state;

    reg [WAY_WIDTH-1:0] hit_way;
    reg [WAY_WIDTH-1:0] victim_way;
    reg [WAY_WIDTH-1:0] miss_way;

    reg [SETIND_WIDTH-1:0] miss_setind;
    reg [TAG_WIDTH-1:0] miss_tag;
    reg [TAG_WIDTH-1:0] victim_tag;
    reg victim_dirty;

    reg victim_invalid;

    integer way_index;
    integer line_index;
    integer select_index;
    integer select_line_index;

    integer way_index;
    integer line_index;

    // Find a matching valid cache line in the requested set.
    always @(*) begin
        hit = 1'b0;
        hit_way = {WAY_WIDTH{1'b0}};

        for (way_index = 0; way_index < NUM_WAYS;
             way_index = way_index + 1) begin
            line_index = i_addr_setind * NUM_WAYS + way_index;

            if (valid[line_index] && tag[line_index] == i_addr_tag) begin
                hit = 1'b1;
                hit_way = way_index;
            end
        end
    end

    // Prefer an invalid way before evicting a valid line.
    always @(*) begin
        victim_way = {WAY_WIDTH{1'b0}};
        victim_invalid = 1'b0;

        for (select_index = 0;
             select_index < NUM_WAYS;
             select_index = select_index + 1) begin

            select_line_index =
                i_addr_setind * NUM_WAYS + select_index;

            if (!victim_invalid && !valid[select_line_index]) begin
                victim_way = select_index;
                victim_invalid = 1'b1;
            end
        end
    end
    
endmodule // cache_controller

// when activated (i.e when the cachecontroller gets this set address),
// this module searches and finds which specific address has the tag.
// it ALSO finds which way to evict when replacing
// and whether that way was dirty and needs to be WB-ed
module setinfo
  #(
    // TODO: fill in
    ) (
       input wire                  i_clk,
       input wire                  i_rst,
       // CPU
       input wire                  i_ren,
       input wire                  i_wen,
       // cache
       input wire [TAG_WIDTH-1:0]  i_addr_tag,
       // if true, we've found the way
       // if false, we need to refill
       output wire                 o_found,
       output wire [WAY_WIDTH-1:0] o_way,
       // are we evicting AND writing back the old data here?
       output wire                 o_evicting_wb
       );

    reg [TAG_WIDTH-1:0] tag[NUM_WAYS-1:0];
    reg                 valid[NUM_WAYS-1:0];
    reg                 dirty[NUM_WAYS-1:0];

    // Check whether the requested tag is present in a valid way.
    wire [NUM_WAYS-1:0] hit_vec;
    wire [WAY_WIDTH-1:0] hit_way_terms [0:NUM_WAYS-1];
    wire [WAY_WIDTH-1:0] hit_way_or [0:NUM_WAYS];

    assign hit_way_or[0] = {WAY_WIDTH{1'b0}};

    genvar hit_index;
    generate
        for (hit_index = 0; hit_index < NUM_WAYS;
             hit_index = hit_index + 1) begin : gen_hit_detection

            assign hit_vec[hit_index] =
                valid[hit_index] &&
                (tag[hit_index] == i_addr_tag);

            assign hit_way_terms[hit_index] =
                hit_vec[hit_index] ?
                hit_index : {WAY_WIDTH{1'b0}};

            assign hit_way_or[hit_index+1] =
                hit_way_or[hit_index] |
                hit_way_terms[hit_index];
        end
    endgenerate

    assign o_found = |hit_vec;
    assign o_way = hit_way_or[NUM_WAYS];
   
    // replacement policy
    generate
        if (EVICT_POLICY) begin : PLRU
            // assume power of 2 ways
            // we're doing this kind of like a heap
            reg [NUM_WAYS-1:1] ptrs;
        end else begin : LRU
            reg [WAY_WIDTH-1:0] age[NUM_WAYS-1:0];
            // when we use/replace a way, set its age to 0
            // other ages have to shift to maintain order 0->1->2->3->...
        end
    endgenerate

    genvar              i; 
    generate
        for (i = 0; i < NUM_WAYS; i = i + 1) begin : gen_setinfo
            // reading (asynchronous)
            
            // writing (synchronous)
            always @(posedge i_clk) begin
                if (i_rst) begin
                    tag[i]   <= 32'b0;
                    dirty[i] <= 0;
                    valid[i] <= 0;
                end else if (/*we need to write here*/) begin
                    if (valid[i]) begin // evicting
                        // TODO
                    end else begin // replacing
                        valid[i] <= 1;
                        dirty[i] <= 0;
                        tag[i]   <= i_addr_tag;
                    end
                end
            end
        end
    endgenerate
endmodule // setinfo

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
