`timescale 1ns/1ps
`default_nettype none

module cache_tb;

    parameter BLOCK_SIZE = 128;
    parameter CACHE_SIZE = 1;
    parameter NUM_WAYS = 2;
    parameter EVICT_POLICY = 0;
    parameter PREFETCH_EN = 0;
    parameter MEM_LATENCY = 4;
    parameter MEM_WORDS = 16384;

    localparam [31:0] DMEM_BASE = 32'h10010000;

    reg clk;
    reg rst;
    reg ren;
    reg wen;
    reg [31:0] addr;
    reg [3:0] mask;
    reg [31:0] wdata;
    wire ready;
    wire [31:0] rdata;

    wire mem_rd;
    wire [31:0] mem_rd_addr;
    reg mem_valid;
    reg [BLOCK_SIZE*8-1:0] mem_rd_data;
    wire mem_wr;
    wire [31:0] mem_wr_addr;
    wire [BLOCK_SIZE*8-1:0] mem_wr_data;
    wire [BLOCK_SIZE-1:0] mem_wr_be;

    reg [31:0] mem [0:MEM_WORDS-1];
    reg [MEM_LATENCY-1:0] valid_pipe;
    reg [31:0] addr_pipe [0:MEM_LATENCY-1];

    integer i, j;
    integer errors;
    integer reads;
    integer writes;
    reg [31:0] observed;

    cache #(
        .EVICT_POLICY(EVICT_POLICY),
        .NUM_WAYS(NUM_WAYS),
        .CACHE_SIZE(CACHE_SIZE),
        .BLOCK_SIZE(BLOCK_SIZE),
        .PREFETCH_EN(PREFETCH_EN)
    ) dut (
        .i_clk(clk),
        .i_rst(rst),
        .i_ren(ren),
        .i_wen(wen),
        .i_addr(addr),
        .i_mask(mask),
        .i_wdata(wdata),
        .o_ready(ready),
        .o_rdata(rdata),
        .o_mem_rd(mem_rd),
        .o_mem_rd_addr(mem_rd_addr),
        .i_mem_valid(mem_valid),
        .i_mem_rd_data(mem_rd_data),
        .o_mem_wr(mem_wr),
        .o_mem_wr_addr(mem_wr_addr),
        .o_mem_wr_data(mem_wr_data),
        .o_mem_wr_be(mem_wr_be)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    function integer mem_index;
        input [31:0] a;
        begin
            if (a < DMEM_BASE || a >= DMEM_BASE + MEM_WORDS*4)
                mem_index = -1;
            else
                mem_index = (a - DMEM_BASE) >> 2;
        end
    endfunction

    always @(posedge clk) begin
        if (rst) begin
            valid_pipe <= {MEM_LATENCY{1'b0}};
            for (i = 0; i < MEM_LATENCY; i = i + 1)
                addr_pipe[i] <= 32'b0;
        end else begin
            valid_pipe[0] <= mem_rd;
            if (mem_rd)
                addr_pipe[0] <= mem_rd_addr;
            for (i = 1; i < MEM_LATENCY; i = i + 1) begin
                valid_pipe[i] <= valid_pipe[i-1];
                addr_pipe[i] <= addr_pipe[i-1];
            end

            if (mem_wr) begin
                writes = writes + 1;
                for (j = 0; j < BLOCK_SIZE; j = j + 1) begin
                    if (mem_wr_be[j] && mem_index(mem_wr_addr + j) >= 0) begin
                        case ((mem_wr_addr + j) & 3)
                            0: mem[mem_index(mem_wr_addr + j)][7:0]
                                   <= mem_wr_data[j*8 +: 8];
                            1: mem[mem_index(mem_wr_addr + j)][15:8]
                                   <= mem_wr_data[j*8 +: 8];
                            2: mem[mem_index(mem_wr_addr + j)][23:16]
                                   <= mem_wr_data[j*8 +: 8];
                            3: mem[mem_index(mem_wr_addr + j)][31:24]
                                   <= mem_wr_data[j*8 +: 8];
                        endcase
                    end
                end
            end
            if (mem_rd)
                reads = reads + 1;
        end
    end

    always @* begin
        mem_valid = valid_pipe[MEM_LATENCY-1];
        mem_rd_data = {BLOCK_SIZE*8{1'b0}};
        for (integer b = 0; b < BLOCK_SIZE; b = b + 1) begin
            if (mem_index(addr_pipe[MEM_LATENCY-1] + b) >= 0)
                mem_rd_data[b*8 +: 8] =
                    mem[mem_index(addr_pipe[MEM_LATENCY-1] + b)]
                       [(((addr_pipe[MEM_LATENCY-1] + b) & 3) * 8) +: 8];
        end
    end

    task access_read;
        input [31:0] a;
        input [31:0] expected;
        integer timeout;
        begin
            @(negedge clk);
            addr = a;
            mask = 4'b1111;
            wdata = 32'b0;
            ren = 1'b1;
            wen = 1'b0;
            timeout = 0;
            @(posedge clk);
            #1;
            while (!ready && timeout < 1000) begin
                @(posedge clk);
                #1;
                timeout = timeout + 1;
            end
            if (!ready) begin
                $display("ERROR: read timeout at %08x", a);
                errors = errors + 1;
            end else begin
                observed = rdata;
                if (observed !== expected) begin
                    $display("ERROR: read %08x expected %08x got %08x", a, expected, observed);
                    errors = errors + 1;
                end else begin
                    $display("PASS: read %08x = %08x", a, observed);
                end
            end
            @(negedge clk);
            ren = 1'b0;
            addr = 32'b0;
        end
    endtask

    task access_write;
        input [31:0] a;
        input [3:0] m;
        input [31:0] d;
        integer timeout;
        begin
            @(negedge clk);
            addr = a;
            mask = m;
            wdata = d;
            ren = 1'b0;
            wen = 1'b1;
            timeout = 0;
            @(posedge clk);
            #1;
            while (!ready && timeout < 1000) begin
                @(posedge clk);
                #1;
                timeout = timeout + 1;
            end
            if (!ready) begin
                $display("ERROR: write timeout at %08x", a);
                errors = errors + 1;
            end
            @(negedge clk);
            wen = 1'b0;
            addr = 32'b0;
        end
    endtask

    initial begin
        rst = 1'b1;
        ren = 1'b0;
        wen = 1'b0;
        addr = 32'b0;
        mask = 4'b1111;
        wdata = 32'b0;
        errors = 0;
        reads = 0;
        writes = 0;

        for (i = 0; i < MEM_WORDS; i = i + 1)
            mem[i] = 32'hA5000000 ^ (i * 32'h1021);

        repeat (5) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;

        // Cold miss, same-line hit, different-line miss, and repeated accesses.
        access_read(DMEM_BASE + 32'd0, 32'hA5000000);
        access_read(DMEM_BASE + 32'd4, 32'hA5001021);
        access_read(DMEM_BASE + BLOCK_SIZE, 32'hA5000000 ^ ((BLOCK_SIZE/4) * 32'h1021));
        access_read(DMEM_BASE + 32'd0, 32'hA5000000);

        // Store-hit path followed by a read-after-write check.
        access_write(DMEM_BASE + 32'd4, 4'b1111, 32'hDEADBEEF);
        access_read(DMEM_BASE + 32'd4, 32'hDEADBEEF);

        // Byte-lane update and read-after-write.
        access_write(DMEM_BASE + 32'd8, 4'b0010, 32'h0000AA00);
        access_read(DMEM_BASE + 32'd8, 32'hA500AA42);

        // More distinct lines exercise replacement and refill.
        access_read(DMEM_BASE + 32'd512, 32'hA5000000 ^ (128 * 32'h1021));
        access_read(DMEM_BASE + 32'd1024, 32'hA5000000 ^ (256 * 32'h1021));
        access_read(DMEM_BASE + 32'd0, 32'hA5000000);

        repeat (20) @(posedge clk);
        if (errors == 0)
            $display("cache_tb PASS: reads=%0d writes=%0d", reads, writes);
        else
            $display("cache_tb FAIL: errors=%0d reads=%0d writes=%0d", errors, reads, writes);
        $finish;
    end

endmodule

`default_nettype wire
