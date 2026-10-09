
`timescale 1ns / 1ps
`default_nettype none

module hazard_fwd_tb #(
    parameter DMEM_MAX_WORDS = 65536
);

    reg i_clk;
    reg i_rst;

    reg [31:0] i_imem_rdata;
    reg [31:0] i_dmem_rdata;

    // Instruction and data memory interfaces
    wire [31:0] o_imem_raddr;
    wire [31:0] o_dmem_addr;
    wire        o_dmem_ren;
    wire        o_dmem_wen;
    wire [31:0] o_dmem_wdata;
    wire [3:0]  o_dmem_mask;

    // Retirement interface
    wire        o_retire_valid;
    wire [31:0] o_retire_inst;
    wire        o_retire_trap;
    wire        o_retire_halt;
    wire [4:0]  o_retire_rs1_raddr;
    wire [31:0] o_retire_rs1_rdata;
    wire [4:0]  o_retire_rs2_raddr;
    wire [31:0] o_retire_rs2_rdata;
    wire [4:0]  o_retire_rd_waddr;
    wire [31:0] o_retire_rd_wdata;
    wire [31:0] o_retire_pc;
    wire [31:0] o_retire_next_pc;

    // Phase 4 retirement memory signals
    wire [31:0] o_retire_dmem_addr;
    wire        o_retire_dmem_ren;
    wire        o_retire_dmem_wen;
    wire [3:0]  o_retire_dmem_mask;
    wire [31:0] o_retire_dmem_wdata;
    wire [31:0] o_retire_dmem_rdata;

    integer trace_file;

    // --------------------------------------------------
    // Device under test
    // Forwarding and register-file bypassing enabled
    // --------------------------------------------------
    hart #(
        .FWD_EN(1),
        .BYPASS_EN(1)
    ) dut (
        .i_clk               (i_clk),
        .i_rst               (i_rst),

        .i_imem_rdata        (i_imem_rdata),
        .o_imem_raddr        (o_imem_raddr),

        .o_dmem_addr         (o_dmem_addr),
        .o_dmem_ren          (o_dmem_ren),
        .o_dmem_wen          (o_dmem_wen),
        .o_dmem_wdata        (o_dmem_wdata),
        .o_dmem_mask         (o_dmem_mask),
        .i_dmem_rdata        (i_dmem_rdata),

        .o_retire_valid      (o_retire_valid),
        .o_retire_inst       (o_retire_inst),
        .o_retire_trap       (o_retire_trap),
        .o_retire_halt       (o_retire_halt),

        .o_retire_rs1_raddr  (o_retire_rs1_raddr),
        .o_retire_rs1_rdata  (o_retire_rs1_rdata),
        .o_retire_rs2_raddr  (o_retire_rs2_raddr),
        .o_retire_rs2_rdata  (o_retire_rs2_rdata),

        .o_retire_rd_waddr   (o_retire_rd_waddr),
        .o_retire_rd_wdata   (o_retire_rd_wdata),

        .o_retire_pc         (o_retire_pc),
        .o_retire_next_pc    (o_retire_next_pc),

        .o_retire_dmem_addr  (o_retire_dmem_addr),
        .o_retire_dmem_ren   (o_retire_dmem_ren),
        .o_retire_dmem_wen   (o_retire_dmem_wen),
        .o_retire_dmem_mask  (o_retire_dmem_mask),
        .o_retire_dmem_wdata (o_retire_dmem_wdata),
        .o_retire_dmem_rdata (o_retire_dmem_rdata)
    );

    // --------------------------------------------------
    // Instruction memory
    // --------------------------------------------------
    reg [31:0] imem [0:65535];

    initial begin
        $readmemh("hazard_program.hex", imem);
    end

    // Instruction memory uses the 0x00400000 base address.
    always @(o_imem_raddr) begin
        i_imem_rdata = 32'b0;

        if (o_imem_raddr >= 32'h00400000 &&
            o_imem_raddr <  32'h00400000 + 4*30000 &&
            o_imem_raddr[1:0] == 2'b00) begin

            i_imem_rdata =
                imem[(o_imem_raddr - 32'h00400000) >> 2];
        end
    end

    // --------------------------------------------------
    // Data memory
    // Sparse word-addressed memory with byte enables
    // --------------------------------------------------
    reg [31:0] mem_addr [0:DMEM_MAX_WORDS-1];
    reg [31:0] mem_data [0:DMEM_MAX_WORDS-1];

    integer mem_count;
    integer r;
    integer w;

    reg        found;
    reg        mem_changed;
    reg [31:0] write_addr;
    reg [31:0] write_data;

    initial begin
        mem_count   = 0;
        mem_changed = 1'b0;
    end

    // Combinational memory read
    always @(o_dmem_ren or o_dmem_addr or mem_changed) begin
        i_dmem_rdata = 32'b0;

        if (o_dmem_ren) begin
            for (r = 0; r < mem_count; r = r + 1) begin
                if (mem_addr[r] == (o_dmem_addr >> 2))
                    i_dmem_rdata = mem_data[r];
            end
        end
    end

    // Clocked memory write
    always @(posedge i_clk) begin
        if (o_dmem_wen) begin
            write_addr = o_dmem_addr >> 2;
            found      = 1'b0;
            write_data = 32'b0;

            // Find an existing word
            for (w = 0; w < mem_count; w = w + 1) begin
                if (mem_addr[w] == write_addr) begin
                    found      = 1'b1;
                    write_data = mem_data[w];
                end
            end

            // Apply byte write enables
            if (o_dmem_mask[0])
                write_data[7:0] = o_dmem_wdata[7:0];

            if (o_dmem_mask[1])
                write_data[15:8] = o_dmem_wdata[15:8];

            if (o_dmem_mask[2])
                write_data[23:16] = o_dmem_wdata[23:16];

            if (o_dmem_mask[3])
                write_data[31:24] = o_dmem_wdata[31:24];

            if (found) begin
                // Update an existing entry
                for (w = 0; w < mem_count; w = w + 1) begin
                    if (mem_addr[w] == write_addr)
                        mem_data[w] = write_data;
                end
            end
            else begin
                // Add a new entry
                if (mem_count >= DMEM_MAX_WORDS) begin
                    $display("ERROR: sparse data memory is full");
                    $finish;
                end

                mem_addr[mem_count] = write_addr;
                mem_data[mem_count] = write_data;
                mem_count = mem_count + 1;
            end
        end

        // Notify the combinational read block
        mem_changed = ~mem_changed;
    end

    // --------------------------------------------------
    // Clock
    // --------------------------------------------------
    always #5 i_clk = ~i_clk;

    // --------------------------------------------------
    // Test program and trace generation
    // --------------------------------------------------
    initial begin
        $dumpfile("hazard_fwd.vcd");
        $dumpvars(0, hazard_fwd_tb);

        trace_file = $fopen("generated.trace", "w");

        if (trace_file == 0) begin
            $display("ERROR: Could not open generated.trace");
            $finish;
        end

        i_clk = 1'b0;
        i_rst = 1'b1;

        // Apply reset
        @(posedge i_clk);
        @(posedge i_clk);
        @(negedge i_clk);

        i_rst = 1'b0;
    end

    // Write one trace entry for each retired instruction
    always @(posedge i_clk) begin
        if (!i_rst && o_retire_valid) begin
            $fwrite(trace_file,
                "%08x %08x %d %d %02x %08x %02x %08x %02x %08x %d %08x %x %08x %08x\n",
                o_retire_pc,
                o_retire_inst,
                o_retire_trap,
                o_retire_halt,
                o_retire_rs1_raddr,
                o_retire_rs1_rdata,
                o_retire_rs2_raddr,
                o_retire_rs2_rdata,
                o_retire_rd_waddr,
                o_retire_rd_wdata,
                {o_retire_dmem_wen, o_retire_dmem_ren},
                o_retire_dmem_addr,
                o_retire_dmem_mask,
                o_retire_dmem_wdata,
                o_retire_next_pc
            );

            if (o_retire_halt) begin
                $fclose(trace_file);
                $finish;
            end
        end
    end

    // Safety timeout in case the program never halts
    initial begin
        #999999;
        $display("ERROR: Test timed out before halt.");
        $fclose(trace_file);
        $finish;
    end

endmodule

`default_nettype wire

