
`timescale 1ns/1ps
`default_nettype none

module cache_tb;

    parameter BLOCK_SIZE  = 128;
    parameter CACHE_SIZE  = 1;
    parameter NUM_WAYS    = 2;
    parameter EVICT_POLICY = 0;
    parameter PREFETCH_EN = 0;
    parameter MEM_LATENCY = 4;
    parameter MEM_WORDS   = 16384;

    localparam [31:0] DMEM_BASE = 32'h10010000;
    localparam integer MEM_BYTES = MEM_WORDS * 4;
    localparam integer TIMEOUT_LIMIT = 1000;

    reg clk;
    reg rst;
    reg ren;
    reg wen;
    reg [31:0] addr;
    reg [3:0] mask;
    reg [31:0] wdata;

    wire stall;
    wire [31:0] rdata;

    wire mem_rd;
    wire [31:0] mem_rd_addr;
    reg mem_valid;
    reg [BLOCK_SIZE*8-1:0] mem_rd_data;

    wire mem_wr;
    wire [31:0] mem_wr_addr;
    wire [BLOCK_SIZE*8-1:0] mem_wr_data;
    wire [BLOCK_SIZE-1:0] mem_wr_be;

    // Backing memory and independent reference memory.
    reg [31:0] mem [0:MEM_WORDS-1];
    reg [31:0] expected_mem [0:MEM_WORDS-1];

    // Simulated memory response pipeline.
    reg [MEM_LATENCY-1:0] valid_pipe;
    reg [31:0] addr_pipe [0:MEM_LATENCY-1];

    integer errors;
    integer reads;
    integer writes;
    integer hits_or_requests;
    integer test_count;

    integer init_i;
    integer pipe_i;
    integer read_byte_i;
    integer write_byte_i;
    integer idx;
    integer byte_addr;
    integer timeout;
    integer random_i;

    reg [31:0] observed;
    reg [31:0] expected_value;
    reg [31:0] random_addr;
    reg [31:0] random_data;
    reg [3:0] random_mask;

    integer seed;

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
        .o_stall(stall),
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

    // Convert a byte address to a backing-memory word index.
    function integer mem_index;
        input [31:0] a;
        begin
            if (a < DMEM_BASE ||
                a >= DMEM_BASE + MEM_BYTES)
                mem_index = -1;
            else
                mem_index = (a - DMEM_BASE) >> 2;
        end
    endfunction

    // Deterministic initial data pattern.
    function [31:0] initial_word;
        input integer word_index;
        begin
            initial_word =
                32'hA5000000 ^ (word_index * 32'h00001021);
        end
    endfunction

    // Apply byte-enable writes to the reference model.
    task update_expected;
        input [31:0] a;
        input [3:0] m;
        input [31:0] d;
        integer lane;
        integer word_index;
        begin
            word_index = mem_index(a);

            if (word_index < 0) begin
                $display("ERROR: reference write out of range: %08x", a);
                errors = errors + 1;
            end else begin
                for (lane = 0; lane < 4; lane = lane + 1) begin
                    if (m[lane]) begin
                        case (lane)
                            0: expected_mem[word_index][7:0]   = d[7:0];
                            1: expected_mem[word_index][15:8]  = d[15:8];
                            2: expected_mem[word_index][23:16] = d[23:16];
                            3: expected_mem[word_index][31:24] = d[31:24];
                        endcase
                    end
                end
            end
        end
    endtask

    // Main cache-memory interface model.
    // A read request is delayed by MEM_LATENCY clock cycles.
    always @(posedge clk) begin
        if (rst) begin
            valid_pipe <= {MEM_LATENCY{1'b0}};

            for (pipe_i = 0; pipe_i < MEM_LATENCY; pipe_i = pipe_i + 1) begin
                addr_pipe[pipe_i] <= 32'b0;
            end
        end else begin
            valid_pipe[0] <= mem_rd;

            if (mem_rd)
                addr_pipe[0] <= mem_rd_addr;

            for (pipe_i = 1; pipe_i < MEM_LATENCY; pipe_i = pipe_i + 1) begin
                valid_pipe[pipe_i] <= valid_pipe[pipe_i-1];
                addr_pipe[pipe_i] <= addr_pipe[pipe_i-1];
            end

            if (mem_rd)
                reads = reads + 1;

            // Accept write-back/write-through requests from the cache.
            if (mem_wr) begin
                writes = writes + 1;

                for (write_byte_i = 0;
                     write_byte_i < BLOCK_SIZE;
                     write_byte_i = write_byte_i + 1) begin

                    byte_addr = mem_wr_addr + write_byte_i;
                    idx = mem_index(byte_addr);

                    if (mem_wr_be[write_byte_i] && idx >= 0) begin
                        case (byte_addr & 3)
                            0: mem[idx][7:0] =
                                mem_wr_data[write_byte_i*8 +: 8];
                            1: mem[idx][15:8] =
                                mem_wr_data[write_byte_i*8 +: 8];
                            2: mem[idx][23:16] =
                                mem_wr_data[write_byte_i*8 +: 8];
                            3: mem[idx][31:24] =
                                mem_wr_data[write_byte_i*8 +: 8];
                        endcase
                    end
                end
            end
        end
    end

    // Generate refill data from backing memory.
    always @* begin
        mem_valid = valid_pipe[MEM_LATENCY-1];
        mem_rd_data = {BLOCK_SIZE*8{1'b0}};

        for (read_byte_i = 0;
             read_byte_i < BLOCK_SIZE;
             read_byte_i = read_byte_i + 1) begin

            idx = mem_index(addr_pipe[MEM_LATENCY-1] + read_byte_i);

            if (idx >= 0) begin
                mem_rd_data[read_byte_i*8 +: 8] =
                    mem[idx][
                        (((addr_pipe[MEM_LATENCY-1] + read_byte_i) & 3) * 8)
                        +: 8
                    ];
            end
        end
    end

    // ------------------------------------------------------------
    // Read test: compare returned data against the reference model.
    // ------------------------------------------------------------
    task access_read;
        input [31:0] a;
        integer wait_cycles;
        integer word_index;
        reg [31:0] exp;
        begin
            test_count = test_count + 1;
            word_index = mem_index(a);

            if (word_index < 0) begin
                $display("ERROR: test read address out of range: %08x", a);
                errors = errors + 1;
            end else begin
                exp = expected_mem[word_index];

                @(negedge clk);
                addr = a;
                mask = 4'b1111;
                wdata = 32'b0;
                ren = 1'b1;
                wen = 1'b0;

                wait_cycles = 0;

                @(posedge clk);
                #1;

                while (stall && wait_cycles < TIMEOUT_LIMIT) begin
                    @(posedge clk);
                    #1;
                    wait_cycles = wait_cycles + 1;
                end

                if (stall) begin
                    $display(
                        "ERROR: READ TIMEOUT addr=%08x after %0d cycles",
                        a, wait_cycles
                    );
                    errors = errors + 1;
                end else begin
                    observed = rdata;

                    if (observed !== exp) begin
                        $display(
                            "ERROR: READ addr=%08x expected=%08x got=%08x",
                            a, exp, observed
                        );
                        errors = errors + 1;
                    end else begin
                        $display(
                            "PASS: READ addr=%08x data=%08x",
                            a, observed
                        );
                    end
                end

                @(negedge clk);
                ren = 1'b0;
                addr = 32'b0;
            end
        end
    endtask

    // ------------------------------------------------------------
    // Write test: update the reference model and issue the store.
    // ------------------------------------------------------------
    task access_write;
        input [31:0] a;
        input [3:0] m;
        input [31:0] d;
        integer wait_cycles;
        begin
            test_count = test_count + 1;

            if (mem_index(a) < 0) begin
                $display("ERROR: test write address out of range: %08x", a);
                errors = errors + 1;
            end else begin
                // The reference model changes only the selected lanes.
                update_expected(a, m, d);

                @(negedge clk);
                addr = a;
                mask = m;
                wdata = d;
                ren = 1'b0;
                wen = 1'b1;

                wait_cycles = 0;

                @(posedge clk);
                #1;

                while (stall && wait_cycles < TIMEOUT_LIMIT) begin
                    @(posedge clk);
                    #1;
                    wait_cycles = wait_cycles + 1;
                end

                if (stall) begin
                    $display(
                        "ERROR: WRITE TIMEOUT addr=%08x mask=%b",
                        a, m
                    );
                    errors = errors + 1;
                end else begin
                    $display(
                        "PASS: WRITE addr=%08x mask=%b data=%08x",
                        a, m, d
                    );
                end

                @(negedge clk);
                wen = 1'b0;
                addr = 32'b0;
            end
        end
    endtask

    // Read a word and compare it against an explicitly supplied value.
    task check_value;
        input [31:0] a;
        input [31:0] exp;
        begin
            access_read(a);
        end
    endtask

    // Test every word in a selected byte range.
    task verify_range;
        input [31:0] start_addr;
        input integer word_count;
        integer k;
        integer word_index;
        begin
            for (k = 0; k < word_count; k = k + 1) begin
                word_index = mem_index(start_addr + k*4);

                if (word_index >= 0)
                    access_read(
                        start_addr + k*4
                    );
            end
        end
    endtask

    // Test reads from a sequence of addresses.
    task test_sequential_reads;
        input [31:0] start_addr;
        input integer word_count;
        integer k;
        integer word_index;
        begin
            $display("\n--- Sequential read test ---");

            for (k = 0; k < word_count; k = k + 1) begin
                word_index = mem_index(start_addr + k*4);

                if (word_index >= 0)
                    access_read(
                        start_addr + k*4
                    );
            end
        end
    endtask

    // Test repeated access to the same cache line.
    task test_repeated_access;
        input [31:0] a;
        input integer repetitions;
        integer k;
        integer word_index;
        begin
            $display("\n--- Repeated-access test ---");
            word_index = mem_index(a);

            if (word_index >= 0) begin
                for (k = 0; k < repetitions; k = k + 1)
                    access_read(a);
            end
        end
    endtask

    // ------------------------------------------------------------
    // Test sequence.
    // ------------------------------------------------------------
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
        test_count = 0;
        seed = 32'h13572468;

        for (init_i = 0; init_i < MEM_WORDS; init_i = init_i + 1) begin
            mem[init_i] = initial_word(init_i);
            expected_mem[init_i] = initial_word(init_i);
        end

        repeat (5) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;

        // 1. Cold miss, same-line access, and repeated reads.
        $display("\n=== TEST 1: Cold misses and cache hits ===");
        access_read(DMEM_BASE);
        access_read(DMEM_BASE + 4);
        access_read(DMEM_BASE + 8);
        access_read(DMEM_BASE);
        test_repeated_access(DMEM_BASE, 5);

        // 2. Access the first word of another cache block.
        $display("\n=== TEST 2: Different cache lines ===");
        access_read(DMEM_BASE + BLOCK_SIZE);
        access_read(DMEM_BASE + 2*BLOCK_SIZE);
        access_read(DMEM_BASE + 3*BLOCK_SIZE);

        // 3. Full-word write and read-after-write.
        $display("\n=== TEST 3: Full-word stores ===");
        access_write(DMEM_BASE + 4, 4'b1111, 32'hDEADBEEF);
        access_read(DMEM_BASE + 4);

        // 4. Individual byte lanes.
        $display("\n=== TEST 4: Byte-enable stores ===");
        access_write(DMEM_BASE + 8, 4'b0001, 32'h000000AA);
        access_read(DMEM_BASE + 8);

        access_write(DMEM_BASE + 8, 4'b0010, 32'h0000BB00);
        access_read(DMEM_BASE + 8);

        access_write(DMEM_BASE + 8, 4'b0100, 32'h00CC0000);
        access_read(DMEM_BASE + 8);

        access_write(DMEM_BASE + 8, 4'b1000, 32'hDD000000);
        access_read(DMEM_BASE + 8);

        // 5. Partial stores with multiple byte lanes enabled.
        $display("\n=== TEST 5: Partial-word stores ===");
        access_write(DMEM_BASE + 12, 4'b0011, 32'h0000BEEF);
        access_read(DMEM_BASE + 12);

        access_write(DMEM_BASE + 12, 4'b1100, 32'hCAFE0000);
        access_read(DMEM_BASE + 12);

        access_write(DMEM_BASE + 16, 4'b0101, 32'h00AA00CC);
        access_read(DMEM_BASE + 16);

        access_write(DMEM_BASE + 20, 4'b1010, 32'hBB00DD00);
        access_read(DMEM_BASE + 20);

        // 6. Refill and revisit earlier addresses.
        $display("\n=== TEST 6: Refill and revisit ===");
        access_read(DMEM_BASE);
        access_read(DMEM_BASE + BLOCK_SIZE);
        access_read(DMEM_BASE + 4);
        access_read(DMEM_BASE + 8);

        // 7. Sequential access across several blocks.
        test_sequential_reads(DMEM_BASE + 4*BLOCK_SIZE, 64);

        // 8. More addresses to exercise replacement.
        $display("\n=== TEST 8: Replacement pressure ===");
        for (random_i = 0; random_i < 24; random_i = random_i + 1) begin
            random_addr = DMEM_BASE + random_i*BLOCK_SIZE;
            access_read(random_addr);
        end

        // Revisit addresses after replacement activity.
        access_read(DMEM_BASE);
        access_read(DMEM_BASE + BLOCK_SIZE);

        // 9. Deterministic pseudo-random reads and writes.
        // Keep all accesses word-aligned and within backing memory.
        $display("\n=== TEST 9: Pseudo-random stress test ===");
        for (random_i = 0; random_i < 100; random_i = random_i + 1) begin
            random_addr =
                DMEM_BASE +
                (($random(seed) & 32'h00000FFF) * 4);

            random_addr = DMEM_BASE +
                (((random_addr - DMEM_BASE) / 4) % MEM_WORDS) * 4;

            random_data = $random(seed);
            random_mask = $random(seed);

            if ((random_i % 3) == 0) begin
                access_write(random_addr, random_mask, random_data);
                access_read(
                    random_addr
                );
            end else begin
                access_read(
                    random_addr
                );
            end
        end

        // 10. Verify a region containing modified data.
        $display("\n=== TEST 10: Final reference-model verification ===");
        verify_range(DMEM_BASE, 32);

        repeat (20) @(posedge clk);

        $display("\n========================================");
        $display("CACHE TEST SUMMARY");
        $display("Configuration: BLOCK_SIZE=%0d CACHE_SIZE=%0d NUM_WAYS=%0d",
                 BLOCK_SIZE, CACHE_SIZE, NUM_WAYS);
        $display("EVICT_POLICY=%0d PREFETCH_EN=%0d MEM_LATENCY=%0d",
                 EVICT_POLICY, PREFETCH_EN, MEM_LATENCY);
        $display("Completed transactions: %0d", test_count);
        $display("Backing-memory read requests: %0d", reads);
        $display("Backing-memory write requests: %0d", writes);
        $display("Errors: %0d", errors);

        if (errors == 0)
            $display("RESULT: PASS");
        else
            $display("RESULT: FAIL");

        $display("========================================");
        $finish;
    end

endmodule

`default_nettype wire
