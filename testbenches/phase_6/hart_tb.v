`timescale 1ns/1ps
`default_nettype none

module hart_tb;

    // -------------------------------------------------------------------------
    // Phase 6 graded cache configuration.
    // Override these parameters from the simulator command line when needed.
    // BLOCK_SIZE is measured in bytes; CACHE_SIZE is measured in KB.
    // -------------------------------------------------------------------------
    parameter BLOCK_SIZE   = 16;
    parameter CACHE_SIZE   = 2;
    parameter NUM_WAYS     = 4;
    parameter EVICT_POLICY = 1;  // 0 = LRU, 1 = PLRU
    parameter PREFETCH_EN  = 1;
    parameter MEM_LATENCY  = 4;

    // Separate memory capacities: the program and reference data image have
    // different sizes.
    parameter IMEM_WORDS = 65536;
    parameter DMEM_WORDS = 32768;

    // File paths are relative to the simulator's working directory.
    parameter IMEM_FILE = "traces/random_program.hex";
    parameter DMEM_FILE = "traces/random_dmem.hex";

    // Simulation controls.
    parameter MAX_CYCLES       = 10000000;
    parameter TRACE_EN         = 0;
    parameter DUMP_VCD         = 0;
    parameter EXPECT_NO_TRAPS  = 1;
    parameter MAX_MISMATCH_LOG = 100;

    localparam [31:0] IMEM_BASE = 32'h00400000;
    localparam [31:0] DMEM_BASE = 32'h10010000;

    // The reference image contains 32768 words, covering 0x10010000 through
    // 0x1002FFFF inclusive.
    localparam [31:0] IMEM_END =
        IMEM_BASE + (IMEM_WORDS * 4);
    localparam [31:0] DMEM_END =
        DMEM_BASE + (DMEM_WORDS * 4);

    // -------------------------------------------------------------------------
    // Clock and reset.
    // -------------------------------------------------------------------------
    reg clk;
    reg rst;

    // -------------------------------------------------------------------------
    // Main-memory interface: instruction memory.
    // -------------------------------------------------------------------------
    wire imem_rd;
    wire [31:0] imem_rd_addr;
    reg imem_valid;
    reg [BLOCK_SIZE*8-1:0] imem_rd_data;

    // -------------------------------------------------------------------------
    // Main-memory interface: data memory.
    // -------------------------------------------------------------------------
    wire dmem_rd;
    wire [31:0] dmem_rd_addr;
    reg dmem_valid;
    reg [BLOCK_SIZE*8-1:0] dmem_rd_data;

    wire dmem_wr;
    wire [31:0] dmem_wr_addr;
    wire [BLOCK_SIZE*8-1:0] dmem_wr_data;
    wire [BLOCK_SIZE-1:0] dmem_wr_be;

    // -------------------------------------------------------------------------
    // Phase 5 retirement interface (retained in Phase 6).
    // -------------------------------------------------------------------------
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

    // -------------------------------------------------------------------------
    // New Phase 6 floating-point retirement interface.
    // These names and widths must match the Phase 6 hart specification.
    // -------------------------------------------------------------------------
    wire [4:0] retire_frs1_raddr;
    wire [31:0] retire_frs1_rdata;

    wire [4:0] retire_frs2_raddr;
    wire [31:0] retire_frs2_rdata;

    wire [4:0] retire_frs3_raddr;
    wire [31:0] retire_frs3_rdata;

    wire retire_frd_wen;
    wire [4:0] retire_frd_waddr;
    wire [31:0] retire_frd_wdata;

    wire [4:0] retire_fflags;

    // -------------------------------------------------------------------------
    // Backing memories.
    //
    // imem is initialized with NOPs before loading the program.
    // dmem starts at zero, as required by the Phase 6 assignment.
    // expected_dmem is a separate, read-only golden final-memory image.
    // -------------------------------------------------------------------------
    reg [31:0] imem [0:IMEM_WORDS-1];
    reg [31:0] dmem [0:DMEM_WORDS-1];
    reg [31:0] expected_dmem [0:DMEM_WORDS-1];

    // -------------------------------------------------------------------------
    // Fixed-latency, ordered memory response pipelines.
    // A request sampled on a rising edge is presented to the hart after
    // MEM_LATENCY cycles. This preserves the Phase 5 memory-model behavior.
    // -------------------------------------------------------------------------
    reg [MEM_LATENCY-1:0] imem_valid_pipe;
    reg [MEM_LATENCY-1:0] dmem_valid_pipe;

    reg [31:0] imem_addr_pipe [0:MEM_LATENCY-1];
    reg [31:0] dmem_addr_pipe [0:MEM_LATENCY-1];

    // Loop/index variables are kept separate for their procedural blocks.
    integer init_i;
    integer pipe_i;
    integer write_j;
    integer read_b;
    integer compare_i;

    integer cycles;
    integer retired;
    integer trap_count;
    integer mismatch_count;
    integer trace_fd;

    reg halted;
    reg trace_open;

    integer write_word_index;
    integer read_word_index;
    reg [31:0] write_byte_addr;
    reg [31:0] read_byte_addr;

    // -------------------------------------------------------------------------
    // DUT.
    //
    // The Phase 6 hart must expose all of the retirement outputs below.
    // -------------------------------------------------------------------------
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
        .o_retire_next_pc(retire_next_pc),

        .o_retire_frs1_raddr(retire_frs1_raddr),
        .o_retire_frs1_rdata(retire_frs1_rdata),
        .o_retire_frs2_raddr(retire_frs2_raddr),
        .o_retire_frs2_rdata(retire_frs2_rdata),
        .o_retire_frs3_raddr(retire_frs3_raddr),
        .o_retire_frs3_rdata(retire_frs3_rdata),

        .o_retire_frd_wen(retire_frd_wen),
        .o_retire_frd_waddr(retire_frd_waddr),
        .o_retire_frd_wdata(retire_frd_wdata),
        .o_retire_fflags(retire_fflags)
    );

    // -------------------------------------------------------------------------
    // Clock generation and optional waveform dump.
    // -------------------------------------------------------------------------
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    initial begin
        if (DUMP_VCD != 0) begin
            $dumpfile("phase6.vcd");
            $dumpvars(0, hart_tb);
        end
    end

    // -------------------------------------------------------------------------
    // Address-to-word-index helpers.
    //
    // These functions use the configured memory sizes. They deliberately do
    // not use the Phase 5 hardcoded 0x3fff mask.
    // -------------------------------------------------------------------------
    function integer imem_index;
        input [31:0] addr;
        begin
            if ((addr < IMEM_BASE) || (addr >= IMEM_END))
                imem_index = -1;
            else
                imem_index = (addr - IMEM_BASE) >> 2;
        end
    endfunction

    function integer dmem_index;
        input [31:0] addr;
        begin
            if ((addr < DMEM_BASE) || (addr >= DMEM_END))
                dmem_index = -1;
            else
                dmem_index = (addr - DMEM_BASE) >> 2;
        end
    endfunction

    // Return a section number for addresses in the program's register-dump
    // regions. Zero means the address is not in one of those regions.
    function integer dump_section;
        input [31:0] addr;
        begin
            if ((addr >= 32'h10020000) && (addr <= 32'h100217FF))
                dump_section = 1; // RV32M
            else if ((addr >= 32'h10021800) && (addr <= 32'h10022FFF))
                dump_section = 2; // FP moves and comparisons
            else if ((addr >= 32'h10023000) && (addr <= 32'h100247FF))
                dump_section = 3; // FP conversions
            else if ((addr >= 32'h10024800) && (addr <= 32'h10025FFF))
                dump_section = 4; // FP add/multiply
            else if ((addr >= 32'h10026000) && (addr <= 32'h100277FF))
                dump_section = 5; // Fused operations
            else if ((addr >= 32'h10027800) && (addr <= 32'h10028FFF))
                dump_section = 6; // FP divide/square root
            else if ((addr >= 32'h10029000) && (addr <= 32'h1002A7FF))
                dump_section = 7; // FP CSR
            else if ((addr >= 32'h1002A800) && (addr <= 32'h1002BFFF))
                dump_section = 8; // Mixed instructions
            else if ((addr >= 32'h1002C000) && (addr <= 32'h1002D7FF))
                dump_section = 9; // Cache stalls
            else
                dump_section = 0;
        end
    endfunction

    // -------------------------------------------------------------------------
    // Main-memory response pipeline and write handling.
    //
    // Requests are sampled on the rising edge. Reads return the block of bytes
    // beginning at the requested address. Writes update enabled byte lanes.
    // -------------------------------------------------------------------------
    always @(posedge clk) begin
        if (rst) begin
            imem_valid_pipe <= {MEM_LATENCY{1'b0}};
            dmem_valid_pipe <= {MEM_LATENCY{1'b0}};

            for (pipe_i = 0; pipe_i < MEM_LATENCY; pipe_i = pipe_i + 1) begin
                imem_addr_pipe[pipe_i] <= 32'b0;
                dmem_addr_pipe[pipe_i] <= 32'b0;
            end
        end else begin
            imem_valid_pipe[0] <= imem_rd;
            dmem_valid_pipe[0] <= dmem_rd;

            if (imem_rd)
                imem_addr_pipe[0] <= imem_rd_addr;

            if (dmem_rd)
                dmem_addr_pipe[0] <= dmem_rd_addr;

            for (pipe_i = 1; pipe_i < MEM_LATENCY; pipe_i = pipe_i + 1) begin
                imem_valid_pipe[pipe_i] <= imem_valid_pipe[pipe_i-1];
                dmem_valid_pipe[pipe_i] <= dmem_valid_pipe[pipe_i-1];

                imem_addr_pipe[pipe_i] <= imem_addr_pipe[pipe_i-1];
                dmem_addr_pipe[pipe_i] <= dmem_addr_pipe[pipe_i-1];
            end

            // Apply writes to backing data memory. The cache presents a
            // block-wide byte-enable vector and corresponding block data.
            if (dmem_wr) begin
                for (write_j = 0; write_j < BLOCK_SIZE; write_j = write_j + 1) begin
                    if (dmem_wr_be[write_j]) begin
                        write_byte_addr = dmem_wr_addr + write_j;
                        write_word_index = dmem_index(write_byte_addr);

                        if (write_word_index >= 0) begin
                            case (write_byte_addr[1:0])
                                2'b00:
                                    dmem[write_word_index][7:0]
                                        <= dmem_wr_data[(write_j << 3) +: 8];
                                2'b01:
                                    dmem[write_word_index][15:8]
                                        <= dmem_wr_data[(write_j << 3) +: 8];
                                2'b10:
                                    dmem[write_word_index][23:16]
                                        <= dmem_wr_data[(write_j << 3) +: 8];
                                2'b11:
                                    dmem[write_word_index][31:24]
                                        <= dmem_wr_data[(write_j << 3) +: 8];
                            endcase
                        end
                    end
                end
            end
        end
    end

    // -------------------------------------------------------------------------
    // Read-response data mux.
    //
    // The memory model is byte-addressed at its interface and word-backed
    // internally. Out-of-range bytes return zero rather than indexing outside
    // an array.
    // -------------------------------------------------------------------------
    always @* begin
        imem_valid = imem_valid_pipe[MEM_LATENCY-1];
        dmem_valid = dmem_valid_pipe[MEM_LATENCY-1];

        imem_rd_data = {BLOCK_SIZE*8{1'b0}};
        dmem_rd_data = {BLOCK_SIZE*8{1'b0}};

        for (read_b = 0; read_b < BLOCK_SIZE; read_b = read_b + 1) begin
            read_byte_addr = imem_addr_pipe[MEM_LATENCY-1] + read_b;
            read_word_index = imem_index(read_byte_addr);

            if (read_word_index >= 0) begin
                imem_rd_data[read_b*8 +: 8] =
                    imem[read_word_index][{read_byte_addr[1:0], 3'b000} +: 8];
            end

            read_byte_addr = dmem_addr_pipe[MEM_LATENCY-1] + read_b;
            read_word_index = dmem_index(read_byte_addr);

            if (read_word_index >= 0) begin
                dmem_rd_data[read_b*8 +: 8] =
                    dmem[read_word_index][{read_byte_addr[1:0], 3'b000} +: 8];
            end
        end
    end

    // -------------------------------------------------------------------------
    // Test initialization and execution.
    //
    // Sample retirement on the falling edge. The DUT updates its sequential
    // state on rising edges, so this avoids racing the DUT's nonblocking
    // assignments in the testbench monitor.
    // -------------------------------------------------------------------------
    initial begin
        rst             = 1'b1;
        cycles          = 0;
        retired         = 0;
        trap_count      = 0;
        mismatch_count  = 0;
        halted          = 1'b0;
        trace_fd        = 0;
        trace_open      = 1'b0;

        // Initialize instruction memory with RV32I NOPs and data memory with
        // zero, as required by the Phase 6 test program.
        for (init_i = 0; init_i < IMEM_WORDS; init_i = init_i + 1)
            imem[init_i] = 32'h00000013; // addi x0, x0, 0

        for (init_i = 0; init_i < DMEM_WORDS; init_i = init_i + 1)
            dmem[init_i] = 32'b0;

        // Initialize expected memory to X first. The supplied file should
        // populate all DMEM_WORDS entries.
        for (init_i = 0; init_i < DMEM_WORDS; init_i = init_i + 1)
            expected_dmem[init_i] = 32'hxxxxxxxx;

        $display("Loading instruction memory: %0s", IMEM_FILE);
        $readmemh(IMEM_FILE, imem);

        $display("Loading expected final data memory: %0s", DMEM_FILE);
        $readmemh(DMEM_FILE, expected_dmem);

        if (TRACE_EN != 0) begin
            trace_fd = $fopen("phase6_retire.trace", "w");
            if (trace_fd == 0) begin
                $display("WARNING: Could not open phase6_retire.trace");
            end else begin
                trace_open = 1'b1;
                $fdisplay(trace_fd,
                    "# pc inst trap halt rs1_addr rs1_data rs2_addr rs2_data rd_addr rd_data dmem_addr dmem_ren dmem_wen dmem_mask dmem_rdata dmem_wdata next_pc frs1_addr frs1_data frs2_addr frs2_data frs3_addr frs3_data frd_wen frd_addr frd_data fflags");
            end
        end

        // Hold reset for five rising edges, then deassert away from the
        // active clock edge.
        repeat (5) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;

        $display("Starting Phase 6 hart test.");
        $display("Cache: block=%0d bytes, size=%0d KB, ways=%0d, policy=%0d, prefetch=%0d, latency=%0d",
                 BLOCK_SIZE, CACHE_SIZE, NUM_WAYS, EVICT_POLICY,
                 PREFETCH_EN, MEM_LATENCY);

        while ((cycles < MAX_CYCLES) && !halted) begin
            @(negedge clk);
            cycles = cycles + 1;

            if (retire_valid) begin
                retired = retired + 1;

                if (TRACE_EN != 0 && trace_open) begin
                    $fdisplay(trace_fd,
                        "%08x %08x %0d %0d %0d %08x %0d %08x %0d %08x %08x %0d %0d %x %08x %08x %08x %0d %08x %0d %08x %0d %08x %0d %0d %08x %02x",
                        retire_pc,
                        retire_inst,
                        retire_trap,
                        retire_halt,
                        retire_rs1_raddr,
                        retire_rs1_rdata,
                        retire_rs2_raddr,
                        retire_rs2_rdata,
                        retire_rd_waddr,
                        retire_rd_wdata,
                        retire_dmem_addr,
                        retire_dmem_ren,
                        retire_dmem_wen,
                        retire_dmem_mask,
                        retire_dmem_rdata,
                        retire_dmem_wdata,
                        retire_next_pc,
                        retire_frs1_raddr,
                        retire_frs1_rdata,
                        retire_frs2_raddr,
                        retire_frs2_rdata,
                        retire_frs3_raddr,
                        retire_frs3_rdata,
                        retire_frd_wen,
                        retire_frd_waddr,
                        retire_frd_wdata,
                        retire_fflags);
                end

                if (retire_trap) begin
                    trap_count = trap_count + 1;
                    $display("TRAP #%0d at PC %08x, instruction %08x",
                             trap_count, retire_pc, retire_inst);
                end

                if (retire_halt) begin
                    $display("HALT retired at PC %08x after %0d instructions",
                             retire_pc, retired);
                    halted = 1'b1;
                end
            end
        end

        if (trace_open) begin
            $fclose(trace_fd);
            trace_open = 1'b0;
        end

        if (!halted) begin
            $display("FAIL: timeout after %0d cycles and %0d retirements",
                     cycles, retired);
            $fatal(1);
        end

        // Allow any nonblocking backing-memory writes from the final active
        // edge to settle before comparing the final image.
        #1;

        $display("Execution complete: cycles=%0d, retired=%0d, traps=%0d",
                 cycles, retired, trap_count);

        // Compare every word, not just the program's dump regions. The
        // assignment's random_dmem.hex is the expected final image for the
        // entire 32768-word data-memory range.
        mismatch_count = 0;

        for (compare_i = 0; compare_i < DMEM_WORDS; compare_i = compare_i + 1) begin
            if (dmem[compare_i] !== expected_dmem[compare_i]) begin
                mismatch_count = mismatch_count + 1;

                if (mismatch_count <= MAX_MISMATCH_LOG) begin
                    case (dump_section(DMEM_BASE + (compare_i << 2)))
                        1: $display("MEM MISMATCH [RV32M] at %08x: expected=%08x actual=%08x",
                                    DMEM_BASE + (compare_i << 2),
                                    expected_dmem[compare_i], dmem[compare_i]);
                        2: $display("MEM MISMATCH [FP move/compare] at %08x: expected=%08x actual=%08x",
                                    DMEM_BASE + (compare_i << 2),
                                    expected_dmem[compare_i], dmem[compare_i]);
                        3: $display("MEM MISMATCH [FP convert] at %08x: expected=%08x actual=%08x",
                                    DMEM_BASE + (compare_i << 2),
                                    expected_dmem[compare_i], dmem[compare_i]);
                        4: $display("MEM MISMATCH [FP add/mul] at %08x: expected=%08x actual=%08x",
                                    DMEM_BASE + (compare_i << 2),
                                    expected_dmem[compare_i], dmem[compare_i]);
                        5: $display("MEM MISMATCH [FP fused] at %08x: expected=%08x actual=%08x",
                                    DMEM_BASE + (compare_i << 2),
                                    expected_dmem[compare_i], dmem[compare_i]);
                        6: $display("MEM MISMATCH [FP div/sqrt] at %08x: expected=%08x actual=%08x",
                                    DMEM_BASE + (compare_i << 2),
                                    expected_dmem[compare_i], dmem[compare_i]);
                        7: $display("MEM MISMATCH [FP CSR] at %08x: expected=%08x actual=%08x",
                                    DMEM_BASE + (compare_i << 2),
                                    expected_dmem[compare_i], dmem[compare_i]);
                        8: $display("MEM MISMATCH [mixed] at %08x: expected=%08x actual=%08x",
                                    DMEM_BASE + (compare_i << 2),
                                    expected_dmem[compare_i], dmem[compare_i]);
                        9: $display("MEM MISMATCH [cache stall] at %08x: expected=%08x actual=%08x",
                                    DMEM_BASE + (compare_i << 2),
                                    expected_dmem[compare_i], dmem[compare_i]);
                        default:
                            $display("MEM MISMATCH at %08x: expected=%08x actual=%08x",
                                     DMEM_BASE + (compare_i << 2),
                                     expected_dmem[compare_i], dmem[compare_i]);
                    endcase
                end
            end
        end

        if (mismatch_count > MAX_MISMATCH_LOG)
            $display("... %0d additional memory mismatches omitted.",
                     mismatch_count - MAX_MISMATCH_LOG);

        if ((mismatch_count == 0) &&
            ((EXPECT_NO_TRAPS == 0) || (trap_count == 0))) begin
            $display("PASS: all %0d data-memory words match random_dmem.hex.",
                     DMEM_WORDS);
            $display("Phase 6 hart test passed.");
            $finish;
        end else begin
            if (mismatch_count != 0)
                $display("FAIL: %0d data-memory mismatches.", mismatch_count);

            if (EXPECT_NO_TRAPS != 0 && trap_count != 0)
                $display("FAIL: encountered %0d unexpected traps.", trap_count);

            $fatal(1);
        end
    end

    // Guard against unsupported parameter combinations that would create
    // invalid or nonsensical memory-pipeline/vector dimensions.
    initial begin
        if (BLOCK_SIZE < 16) begin
            $display("ERROR: BLOCK_SIZE must be at least 16 bytes.");
            $fatal(1);
        end

        if (MEM_LATENCY < 1) begin
            $display("ERROR: MEM_LATENCY must be at least 1 cycle.");
            $fatal(1);
        end

        if ((IMEM_WORDS < 36088) || (DMEM_WORDS != 32768)) begin
            $display("WARNING: memory dimensions differ from the supplied Phase 6 trace sizes.");
        end
    end

endmodule

`default_nettype wire
