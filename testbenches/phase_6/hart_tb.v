`timescale 1ns/1ps
`default_nettype none

module hart_tb;
    parameter BLOCK_SIZE = 16;
    parameter CACHE_SIZE = 2;
    parameter NUM_WAYS = 4;
    parameter EVICT_POLICY = 1;
    parameter PREFETCH_EN = 1;
    parameter MEM_LATENCY = 4;
    parameter IMEM_WORDS = 65536;
    parameter DMEM_WORDS = 32768;

    localparam [31:0] IMEM_BASE = 32'h00400000;
    localparam [31:0] DMEM_BASE = 32'h10010000;

    reg clk, rst;
    wire imem_rd, dmem_rd, dmem_wr;
    wire [31:0] imem_rd_addr, dmem_rd_addr, dmem_wr_addr;
    reg imem_valid, dmem_valid;
    reg [BLOCK_SIZE*8-1:0] imem_rd_data, dmem_rd_data;
    wire [BLOCK_SIZE*8-1:0] dmem_wr_data;
    wire [BLOCK_SIZE-1:0] dmem_wr_be;

    wire retire_valid, retire_trap, retire_halt;
    wire [31:0] retire_inst, retire_pc;
    wire [4:0] retire_frd_waddr, retire_fflags;
    wire retire_frd_wen;
    wire [31:0] retire_frd_wdata;
    wire [4:0] retire_frs2_raddr;
    wire [31:0] retire_frs2_rdata;
    wire retire_dmem_wen;
    wire [31:0] retire_dmem_addr, retire_dmem_wdata;

    reg [31:0] imem [0:IMEM_WORDS-1];
    reg [31:0] dmem [0:DMEM_WORDS-1];
    reg [31:0] expected_dmem [0:DMEM_WORDS-1];
    reg [MEM_LATENCY-1:0] imem_valid_pipe, dmem_valid_pipe;
    reg [31:0] imem_addr_pipe [0:MEM_LATENCY-1];
    reg [31:0] dmem_addr_pipe [0:MEM_LATENCY-1];
    integer i, write_b, write_lane, write_idx, read_b, read_idx;
    integer cycles, retired, mismatches, mainmem_writes, low_region_writes;
    integer mismatch_fd;
    reg halted;

    hart #(
        .RESET_ADDR(IMEM_BASE), .FWD_EN(1), .BYPASS_EN(1),
        .EVICT_POLICY(EVICT_POLICY), .NUM_WAYS(NUM_WAYS),
        .CACHE_SIZE(CACHE_SIZE), .BLOCK_SIZE(BLOCK_SIZE),
        .PREFETCH_EN(PREFETCH_EN)
    ) dut (
        .i_clk(clk), .i_rst(rst),
        .o_imem_rd(imem_rd), .o_imem_rd_addr(imem_rd_addr),
        .i_imem_valid(imem_valid), .i_imem_rd_data(imem_rd_data),
        .o_dmem_rd(dmem_rd), .o_dmem_rd_addr(dmem_rd_addr),
        .i_dmem_valid(dmem_valid), .i_dmem_rd_data(dmem_rd_data),
        .o_dmem_wr(dmem_wr), .o_dmem_wr_addr(dmem_wr_addr),
        .o_dmem_wr_data(dmem_wr_data), .o_dmem_wr_be(dmem_wr_be),
        .o_retire_valid(retire_valid), .o_retire_inst(retire_inst),
        .o_retire_trap(retire_trap), .o_retire_halt(retire_halt),
        .o_retire_frd_wen(retire_frd_wen), .o_retire_frd_waddr(retire_frd_waddr),
        .o_retire_frd_wdata(retire_frd_wdata), .o_retire_fflags(retire_fflags),
        .o_retire_frs2_raddr(retire_frs2_raddr),
        .o_retire_frs2_rdata(retire_frs2_rdata),
        .o_retire_dmem_wen(retire_dmem_wen),
        .o_retire_dmem_addr(retire_dmem_addr),
        .o_retire_dmem_wdata(retire_dmem_wdata),
        .o_retire_pc(retire_pc)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    function integer imem_index;
        input [31:0] addr;
        begin
            if (addr < IMEM_BASE || addr >= IMEM_BASE + IMEM_WORDS*4)
                imem_index = -1;
            else imem_index = (addr - IMEM_BASE) >> 2;
        end
    endfunction

    function integer dmem_index;
        input [31:0] addr;
        begin
            if (addr < DMEM_BASE || addr >= DMEM_BASE + DMEM_WORDS*4)
                dmem_index = -1;
            else dmem_index = (addr - DMEM_BASE) >> 2;
        end
    endfunction

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
            if (imem_rd) imem_addr_pipe[0] <= imem_rd_addr;
            if (dmem_rd) dmem_addr_pipe[0] <= dmem_rd_addr;
            for (i = 1; i < MEM_LATENCY; i = i + 1) begin
                imem_valid_pipe[i] <= imem_valid_pipe[i-1];
                dmem_valid_pipe[i] <= dmem_valid_pipe[i-1];
                imem_addr_pipe[i] <= imem_addr_pipe[i-1];
                dmem_addr_pipe[i] <= dmem_addr_pipe[i-1];
            end

            if (dmem_wr) begin
                if (dmem_wr_addr == 32'h10010020)
                    $display("TARGET LINE WRITE be=%04x line=%08x_%08x_%08x_%08x",
                             dmem_wr_be[15:0], dmem_wr_data[127:96],
                             dmem_wr_data[95:64], dmem_wr_data[63:32], dmem_wr_data[31:0]);
                if (mainmem_writes < 12)
                    $display("MAINMEM WRITE #%0d addr=%08x be-low=%04x data-low=%08x",
                             mainmem_writes, dmem_wr_addr, dmem_wr_be[15:0], dmem_wr_data[127:96]);
                if (dmem_wr_addr < 32'h10018000 && low_region_writes < 12) begin
                    $display("LOW DATA WRITE #%0d addr=%08x be=%04x data=%08x",
                             low_region_writes, dmem_wr_addr, dmem_wr_be[15:0], dmem_wr_data[31:0]);
                    low_region_writes <= low_region_writes + 1;
                end
                mainmem_writes <= mainmem_writes + 1;
                for (write_b = 0; write_b < BLOCK_SIZE; write_b = write_b + 1) begin
                    if (dmem_wr_be[write_b] && dmem_index(dmem_wr_addr+write_b) >= 0) begin
                        write_idx = dmem_index(dmem_wr_addr+write_b);
                        write_lane = (dmem_wr_addr+write_b) & 3;
                        case (write_lane)
                            0: dmem[write_idx][7:0] <= dmem_wr_data[write_b*8 +: 8];
                            1: dmem[write_idx][15:8] <= dmem_wr_data[write_b*8 +: 8];
                            2: dmem[write_idx][23:16] <= dmem_wr_data[write_b*8 +: 8];
                            3: dmem[write_idx][31:24] <= dmem_wr_data[write_b*8 +: 8];
                        endcase
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
        for (read_b = 0; read_b < BLOCK_SIZE; read_b = read_b + 1) begin
            read_idx = imem_index(imem_addr_pipe[MEM_LATENCY-1] + read_b);
            if (read_idx >= 0)
                imem_rd_data[read_b*8 +: 8] = imem[read_idx][(((imem_addr_pipe[MEM_LATENCY-1]+read_b)&3)*8) +: 8];
            read_idx = dmem_index(dmem_addr_pipe[MEM_LATENCY-1] + read_b);
            if (read_idx >= 0)
                dmem_rd_data[read_b*8 +: 8] = dmem[read_idx][(((dmem_addr_pipe[MEM_LATENCY-1]+read_b)&3)*8) +: 8];
        end
    end

    always @(posedge clk) begin
        if (!rst && dut.id_ex_inst == 32'h128d2207)
            $display("LOAD DEBUG: idexpc=%08x rs1=%0d snapshot=%08x exinst=%08x exrd=%0d exsel=%b exvalue=%08x fwd=%b fwddata=%08x alu=%08x",
                     dut.id_ex_pc, dut.id_ex_rs1, dut.id_ex_rs1_data,
                     dut.ex_mem_inst, dut.ex_mem_rd, dut.ex_mem_rd_sel,
                     dut.writeback_data, dut.forward_ex_rs1,
                     dut.forward_rs1_data, dut.alu_result);
        if (!rst && !dut.cache_hold && (dut.ex_mem_trap || dut.dmem_misaligned))
            $display("FAULT SOURCE @%08x inst=%08x id_ex=%08x idtrap=%b rmtrap=%b addr=%08x align=%b read=%b write=%b mis=%b",
                     dut.ex_mem_pc, dut.ex_mem_inst, dut.id_ex_inst, dut.id_ex_trap,
                     dut.fpu_rm_trap, dut.dmem_byte_addr, dut.ex_mem_memalign,
                     dut.ex_mem_memread, dut.ex_mem_memwrite, dut.dmem_misaligned);
    end

    initial begin
        rst = 1'b1;
        cycles = 0;
        retired = 0;
        mainmem_writes = 0;
        low_region_writes = 0;
        halted = 1'b0;
        for (i = 0; i < IMEM_WORDS; i = i + 1) imem[i] = 32'h00000013;
        for (i = 0; i < DMEM_WORDS; i = i + 1) dmem[i] = 32'b0;
        $readmemh("course_files/phase_6/traces/random_program.hex", imem);
        $readmemh("course_files/phase_6/traces/random_dmem.hex", expected_dmem);

        repeat (5) @(posedge clk);
        @(negedge clk) rst = 1'b0;
        while (cycles < 2000000 && !halted) begin
            @(posedge clk);
            cycles = cycles + 1;
            if (retire_valid) begin
                retired = retired + 1;
                if (retire_pc == 32'h0040db4c)
                    $display("FSW DEBUG: frs2=f%0d data=%08x dmem_wen=%b addr=%08x data=%08x",
                             retire_frs2_raddr, retire_frs2_rdata, retire_dmem_wen,
                             retire_dmem_addr, retire_dmem_wdata);
                if (retire_dmem_wen &&
                    ((retire_dmem_addr == 32'h10010084) ||
                     (retire_dmem_addr == 32'h1001012c) ||
                     (retire_dmem_addr == 32'h10010140) ||
                     (retire_dmem_addr == 32'h100261c8) ||
                     (retire_dmem_addr == 32'h1002627c)))
                    $display("MISMATCH ADDRESS STORE: pc=%08x inst=%08x addr=%08x data=%08x src=f%0d/%08x",
                             retire_pc, retire_inst, retire_dmem_addr, retire_dmem_wdata,
                             retire_frs2_raddr, retire_frs2_rdata);
                if ((retire_pc == 32'h00405820) ||
                    (retire_pc == 32'h0040f704) ||
                    (retire_pc == 32'h0041b44c))
                    $display("FMV TRACE: pc=%08x inst=%08x rs1=x%0d xdata=%08x frd_en=%b frd=f%0d fpdata=%08x",
                             retire_pc, retire_inst, dut.mem_wb_rs1,
                             dut.mem_wb_rs1_data, retire_frd_wen,
                             retire_frd_waddr, retire_frd_wdata);
                if ((retire_pc == 32'h00405d04) ||
                    (retire_pc == 32'h00405f28) ||
                    (retire_pc == 32'h00405f2c))
                    $display("LOAD/FP TRACE: pc=%08x inst=%08x dmem_rdata=%08x frs1=f%0d/%08x frs2=f%0d/%08x frd_en=%b frd=f%0d/%08x",
                             retire_pc, retire_inst, dut.mem_wb_dmem_rdata,
                             dut.mem_wb_frs1, dut.mem_wb_frs1_data,
                             dut.mem_wb_frs2, dut.mem_wb_frs2_data,
                             retire_frd_wen, retire_frd_waddr,
                             retire_frd_wdata);
                if (retire_trap) begin
                    $display("FAIL trap PC=%08x inst=%08x", retire_pc, retire_inst);
                    $fatal(1);
                end
                if (retire_halt) halted = 1'b1;
            end
        end
        if (!halted) begin
            $display("FAIL: timed out after %0d cycles (%0d retirements)", cycles, retired);
            $fatal(1);
        end

        // Allow a final cache write-through/write-back to reach main memory.
        repeat (BLOCK_SIZE + MEM_LATENCY + 4) @(posedge clk);
        mismatches = 0;
        mismatch_fd = $fopen("phase6_mismatches.txt", "w");
        for (i = 0; i < DMEM_WORDS; i = i + 1) begin
            if (dmem[i] !== expected_dmem[i]) begin
                if (mismatch_fd != 0)
                    $fdisplay(mismatch_fd, "%08x %08x %08x", DMEM_BASE + i*4, dmem[i], expected_dmem[i]);
                if (mismatches < 20)
                    $display("DMEM mismatch [%0d] @ %08x: got %08x expected %08x",
                             i, DMEM_BASE + i*4, dmem[i], expected_dmem[i]);
                mismatches = mismatches + 1;
            end
        end
        if (mismatch_fd != 0) $fclose(mismatch_fd);
        if (mismatches != 0) begin
            $display("FAIL: %0d data-memory words mismatched after %0d main-memory writes (%0d low-data writes; word9=%08x)",
                     mismatches, mainmem_writes, low_region_writes, dmem[9]);
            $fatal(1);
        end
        $display("PASS: phase 6 program halted; %0d retirements, %0d cycles, %0d main-memory writes; all %0d DMEM words match (last fflags=%02x, frd=%0d/%08x)",
                 retired, cycles, mainmem_writes, DMEM_WORDS, retire_fflags, retire_frd_wen, retire_frd_wdata);
        $finish;
    end
endmodule

`default_nettype wire
