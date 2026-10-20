`timescale 1ns/1ps
`default_nettype none

module hart_tb;

    parameter BLOCK_SIZE = 128;
    parameter CACHE_SIZE = 16;
    parameter NUM_WAYS = 1;
    parameter EVICT_POLICY = 0;
    parameter PREFETCH_EN = 0;
    parameter MEM_LATENCY = 4;
    parameter MEM_WORDS = 16384;

    localparam [31:0] IMEM_BASE = 32'h00400000;
    localparam [31:0] DMEM_BASE = 32'h10010000;

    reg clk;
    reg rst;

    wire imem_rd;
    wire [31:0] imem_rd_addr;
    reg imem_valid;
    reg [BLOCK_SIZE*8-1:0] imem_rd_data;

    wire dmem_rd;
    wire [31:0] dmem_rd_addr;
    reg dmem_valid;
    reg [BLOCK_SIZE*8-1:0] dmem_rd_data;
    wire dmem_wr;
    wire [31:0] dmem_wr_addr;
    wire [BLOCK_SIZE*8-1:0] dmem_wr_data;
    wire [BLOCK_SIZE-1:0] dmem_wr_be;

    wire retire_valid;
    wire [31:0] retire_inst;
    wire retire_trap;
    wire retire_halt;
    wire [4:0] retire_rs1_raddr;
    wire [4:0] retire_rs2_raddr;
    wire [31:0] retire_rs1_rdata;
    wire [31:0] retire_rs2_rdata;
    wire [4:0] retire_rd_waddr;
    wire [31:0] retire_rd_wdata;
    wire [31:0] retire_dmem_addr;
    wire [3:0] retire_dmem_mask;
    wire retire_dmem_ren;
    wire retire_dmem_wen;
    wire [31:0] retire_dmem_rdata;
    wire [31:0] retire_dmem_wdata;
    wire [31:0] retire_pc;
    wire [31:0] retire_next_pc;

    reg [31:0] imem [0:MEM_WORDS-1];
    reg [31:0] dmem [0:MEM_WORDS-1];

    reg [MEM_LATENCY-1:0] imem_valid_pipe;
    reg [MEM_LATENCY-1:0] dmem_valid_pipe;
    reg [31:0] imem_addr_pipe [0:MEM_LATENCY-1];
    reg [31:0] dmem_addr_pipe [0:MEM_LATENCY-1];

    integer i, j;
    integer cycles;
    integer retired;
    integer trace_fd;
    reg halted;

    hart #(
        .RESET_ADDR(IMEM_BASE),
        .FWD_EN(1),
        .BYPASS_EN(1),
        .EVICT_POLICY(EVICT_POLICY),
        .NUM_WAYS(NUM_WAYS),
        .CACHE_SIZE(CACHE_SIZE),
        .BLOCK_SIZE(BLOCK_SIZE),
        .PREFETCH_EN(PREFETCH_EN)
    ) dut (
        .i_clk(clk),
        .i_rst(rst),
        .o_imem_rd(imem_rd),
        .o_imem_rd_addr(imem_rd_addr),
        .i_imem_valid(imem_valid),
        .i_imem_rd_data(imem_rd_data),
        .o_dmem_rd(dmem_rd),
        .o_dmem_rd_addr(dmem_rd_addr),
        .i_dmem_valid(dmem_valid),
        .i_dmem_rd_data(dmem_rd_data),
        .o_dmem_wr(dmem_wr),
        .o_dmem_wr_addr(dmem_wr_addr),
        .o_dmem_wr_data(dmem_wr_data),
        .o_dmem_wr_be(dmem_wr_be),
        .o_retire_valid(retire_valid),
        .o_retire_inst(retire_inst),
        .o_retire_trap(retire_trap),
        .o_retire_halt(retire_halt),
        .o_retire_rs1_raddr(retire_rs1_raddr),
        .o_retire_rs2_raddr(retire_rs2_raddr),
        .o_retire_rs1_rdata(retire_rs1_rdata),
        .o_retire_rs2_rdata(retire_rs2_rdata),
        .o_retire_rd_waddr(retire_rd_waddr),
        .o_retire_rd_wdata(retire_rd_wdata),
        .o_retire_dmem_addr(retire_dmem_addr),
        .o_retire_dmem_mask(retire_dmem_mask),
        .o_retire_dmem_ren(retire_dmem_ren),
        .o_retire_dmem_wen(retire_dmem_wen),
        .o_retire_dmem_rdata(retire_dmem_rdata),
        .o_retire_dmem_wdata(retire_dmem_wdata),
        .o_retire_pc(retire_pc),
        .o_retire_next_pc(retire_next_pc)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    // Word-index helper for the two independent 64 KiB memories.
    function integer imem_index;
        input [31:0] addr;
        begin
            if (addr < IMEM_BASE || addr >= IMEM_BASE + MEM_WORDS*4)
                imem_index = -1;
            else
                imem_index = (addr - IMEM_BASE) >> 2;
        end
    endfunction

    function integer dmem_index;
        input [31:0] addr;
        begin
            if (addr < DMEM_BASE || addr >= DMEM_BASE + MEM_WORDS*4)
                dmem_index = -1;
            else
                dmem_index = (addr - DMEM_BASE) >> 2;
        end
    endfunction

    // Responses are pipelined and ordered. A request sampled on a rising
    // edge is returned MEM_LATENCY cycles later.
    always @(posedge clk) begin
        if (rst) begin
            imem_valid_pipe <= {MEM_LATENCY{1'b0}};
            dmem_valid_pipe <= {MEM_LATENCY{1'b0}};
            for (i = 0; i < MEM_LATENCY; i = i + 1) begin
                imem_addr_pipe[i] <= 32'b0;
                dmem_addr_pipe[i] <= 32'b0;
            end
        end else begin
            imem_valid_pipe[0] <= imem_rd;
            dmem_valid_pipe[0] <= dmem_rd;
            if (imem_rd)
                imem_addr_pipe[0] <= imem_rd_addr;
            if (dmem_rd)
                dmem_addr_pipe[0] <= dmem_rd_addr;

            for (i = 1; i < MEM_LATENCY; i = i + 1) begin
                imem_valid_pipe[i] <= imem_valid_pipe[i-1];
                dmem_valid_pipe[i] <= dmem_valid_pipe[i-1];
                imem_addr_pipe[i] <= imem_addr_pipe[i-1];
                dmem_addr_pipe[i] <= dmem_addr_pipe[i-1];
            end

            // Main-memory writes are applied on the clock edge with byte enables.
            if (dmem_wr) begin
                for (j = 0; j < BLOCK_SIZE; j = j + 1) begin
                    if (dmem_wr_be[j]) begin
                        if (dmem_index(dmem_wr_addr + j) >= 0) begin
                            case ((dmem_wr_addr + j) & 3)
                                0: dmem[dmem_index(dmem_wr_addr + j) & 32'h3fff][7:0]
                                       <= dmem_wr_data[j*8 +: 8];
                                1: dmem[dmem_index(dmem_wr_addr + j) & 32'h3fff][15:8]
                                       <= dmem_wr_data[j*8 +: 8];
                                2: dmem[dmem_index(dmem_wr_addr + j) & 32'h3fff][23:16]
                                       <= dmem_wr_data[j*8 +: 8];
                                3: dmem[dmem_index(dmem_wr_addr + j) & 32'h3fff][31:24]
                                       <= dmem_wr_data[j*8 +: 8];
                            endcase
                        end
                    end
                end
            end
        end
    end

    always @* begin
        imem_valid = imem_valid_pipe[MEM_LATENCY-1];
        dmem_valid = dmem_valid_pipe[MEM_LATENCY-1];
        imem_rd_data = {BLOCK_SIZE*8{1'b0}};
        dmem_rd_data = {BLOCK_SIZE*8{1'b0}};

        for (integer b = 0; b < BLOCK_SIZE; b = b + 1) begin
            if (imem_index(imem_addr_pipe[MEM_LATENCY-1] + b) >= 0)
                imem_rd_data[b*8 +: 8] =
                    imem[imem_index(imem_addr_pipe[MEM_LATENCY-1] + b) & 32'h3fff]
                         [(((imem_addr_pipe[MEM_LATENCY-1] + b) & 3) * 8) +: 8];
            if (dmem_index(dmem_addr_pipe[MEM_LATENCY-1] + b) >= 0)
                dmem_rd_data[b*8 +: 8] =
                    dmem[dmem_index(dmem_addr_pipe[MEM_LATENCY-1] + b) & 32'h3fff]
                         [(((dmem_addr_pipe[MEM_LATENCY-1] + b) & 3) * 8) +: 8];
        end
    end

    initial begin
        rst = 1'b1;
        cycles = 0;
        retired = 0;
        halted = 1'b0;
        trace_fd = $fopen("generated.trace", "w");

        for (i = 0; i < MEM_WORDS; i = i + 1) begin
            imem[i] = 32'h00000013; // addi x0,x0,0
            dmem[i] = 32'b0;
        end

        $readmemh("random_program.hex", imem);
        repeat (5) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;

        while ((cycles < 2000000) && !halted) begin
            @(posedge clk);
            cycles = cycles + 1;

            if (retire_valid) begin
                retired = retired + 1;
                if (trace_fd != 0) begin
                    $fdisplay(trace_fd,
                        "%08x %08x %0d %0d %0d %08x %08x %08x %08x %08x %0d %0d %08x %08x %08x %08x",
                        retire_pc, retire_inst, retire_trap, retire_halt,
                        retire_rd_waddr, retire_rd_wdata, retire_rs1_rdata,
                        retire_rs2_rdata, retire_dmem_addr, retire_dmem_rdata,
                        retire_dmem_ren, retire_dmem_wen, retire_dmem_wdata,
                        retire_next_pc, retire_rs1_raddr, retire_rs2_raddr);
                end
                if (retire_trap) begin
                    $display("ERROR: trap at PC %08x, instruction %08x", retire_pc, retire_inst);
                    halted = 1'b1;
                end
                if (retire_halt) begin
                    $display("HALT retired at PC %08x after %0d instructions", retire_pc, retired);
                    halted = 1'b1;
                end
            end
        end

        if (trace_fd != 0)
            $fclose(trace_fd);

        if (!halted) begin
            $display("ERROR: timeout after %0d cycles and %0d retirements", cycles, retired);
            $fatal(1);
        end else if (retire_trap) begin
            $fatal(1);
        end else begin
            $display("hart_tb finished: cycles=%0d retired=%0d", cycles, retired);
            $finish;
        end
    end

endmodule

`default_nettype wire
