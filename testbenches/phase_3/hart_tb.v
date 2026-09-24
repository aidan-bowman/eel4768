```verilog
`timescale 1ns / 1ps
`default_nettype none

// A worked example of a self-checking testbench, for the `opmux` module next
// to it. Read it top to bottom -- it is the shape every testbench you write
// this semester will have:
//
//   1. Declare a `reg` for each DUT input and a `wire` for each DUT output.
//   2. Instantiate the DUT, connecting them by port name.
//   3. Drive the inputs, wait, then compare the outputs against a value you
//      worked out independently of the RTL.
//   4. Count the comparisons and print a verdict, so you never have to read a
//      waveform to find out *whether* something broke -- only *why*.
//
// Point 3 is the one people get wrong. An expected value copied out of the
// design under test proves only that the design agrees with itself.
module hart_tb;

    reg i_clk;
    reg i_rst;

    reg [31:0] i_imem_rdata;
    reg [31:0] i_dmem_rdata;

    // actually used for memory
    wire [31:0] o_imem_raddr;
    wire [31:0] o_dmem_addr;
    wire o_dmem_ren;
    wire o_dmem_wen;
    wire [31:0] o_dmem_wdata;
    wire [3:0] o_dmem_mask;

    // JUST testing
    wire o_retire_valid;
    wire [31:0] o_retire_inst;
    wire o_retire_trap;
    wire o_retire_halt;
    wire [4:0] o_retire_rs1_raddr;
    wire [31:0] o_retire_rs1_rdata;
    wire [4:0] o_retire_rs2_raddr;
    wire [31:0] o_retire_rs2_rdata;
    wire [4:0] o_retire_rd_waddr;
    wire [31:0] o_retire_rd_wdata;
    wire [31:0] o_retire_pc;
    wire [31:0] o_retire_next_pc;

    integer passed;
    integer failed;

    // ---------------------------------------------------------------------
    // 2. The device under test. Connect by name (.port(signal)), never by
    //    position -- positional connections break silently the moment someone
    //    reorders the port list.
    // ---------------------------------------------------------------------

    hart dut (
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
        .o_retire_next_pc    (o_retire_next_pc)
    );

    // ---------------------------------------------------------------------
    // 3. One comparison. Drive the inputs, let the combinational logic
    //    settle, then check both outputs.
    //
    //    `===` rather than `==` on purpose: `===` compares x and z literally,
    //    so an undriven output fails here instead of quietly comparing
    //    "unknown" and returning unknown.
    // ---------------------------------------------------------------------

    // --------------------------------------------------
    // Instruction memory
    // --------------------------------------------------

    reg [31:0] imem [0:255];

    always @(*) begin
        i_imem_rdata = imem[o_imem_raddr >> 2];
    end


    // --------------------------------------------------
    // Data memory
    // --------------------------------------------------

    reg [31:0] dmem [0:255];

    always @(*) begin
        if (o_dmem_ren)
            i_dmem_rdata = dmem[o_dmem_addr >> 2];
        else
            i_dmem_rdata = 32'b0;
    end

    always @(posedge i_clk) begin
        if (o_dmem_wen) begin
            if (o_dmem_mask[0])
                dmem[(o_dmem_addr >> 2)][7:0] <= o_dmem_wdata[7:0];

            if (o_dmem_mask[1])
                dmem[(o_dmem_addr >> 2)][15:8] <= o_dmem_wdata[15:8];

            if (o_dmem_mask[2])
                dmem[(o_dmem_addr >> 2)][23:16] <= o_dmem_wdata[23:16];

            if (o_dmem_mask[3])
                dmem[(o_dmem_addr >> 2)][31:24] <= o_dmem_wdata[31:24];
        end
    end


    // --------------------------------------------------
    // Clock
    // --------------------------------------------------

    always #5 i_clk = ~i_clk;


    task check;
        input [255:0] label;
        input [31:0] expected_inst;
        input [31:0] expected_pc;
        input [31:0] expected_next_pc;
        input [4:0] expected_rd;
        input [31:0] expected_rd_data;

        begin
            #1;

            if (o_retire_valid === 1'b1 &&
                o_retire_inst === expected_inst &&
                o_retire_pc === expected_pc &&
                o_retire_next_pc === expected_next_pc &&
                o_retire_rd_waddr === expected_rd &&
                o_retire_rd_wdata === expected_rd_data) begin

                passed = passed + 1;
                $display("[PASS] %0s", label);

            end else begin

                failed = failed + 1;
                $display("[FAIL] %0s", label);
                $display("         inst=%h (expected %h)",
                         o_retire_inst, expected_inst);
                $display("         pc=%h (expected %h)",
                         o_retire_pc, expected_pc);
                $display("         next_pc=%h (expected %h)",
                         o_retire_next_pc, expected_next_pc);
                $display("         rd=%d (expected %d)",
                         o_retire_rd_waddr, expected_rd);
                $display("         rd_data=%h (expected %h)",
                         o_retire_rd_wdata, expected_rd_data);
            end
        end
    endtask


    // ---------------------------------------------------------------------
    // A reference model, used by the random test below.
    //
    // Deriving it from the specification rather than from the RTL is what
    // makes it worth anything. Here the two happen to look alike because the
    // module is three lines long; for your ALU or decoder they will not, and
    // copying the RTL into the model would make every test pass by
    // construction.
    // ---------------------------------------------------------------------
    //
    // The hart tests below are directed tests instead of random tests because
    // each test is checking a specific RISC-V instruction and its expected
    // architectural result.


    // ---------------------------------------------------------------------
    // 4. The test program.
    // ---------------------------------------------------------------------

    integer i;

    initial begin
        // Records a waveform of every signal in this testbench. Open it with
        // `gtkwave build/opmux.vcd` to see the inputs and outputs over time --
        // the fastest way to understand a failure the printout only summarizes.
        $dumpfile("hart.vcd");
        $dumpvars(0, hart_tb);

        passed = 0;
        failed = 0;

        i_clk = 0;
        i_rst = 1;
        i_dmem_rdata = 0;

        $display("========== hart testbench ==========");


        // --------------------------------------------------
        // Test 1: ADDI
        // x1 = 5
        // --------------------------------------------------

        $display("--- Test 1: ADDI ---");

        for (i = 0; i < 256; i = i + 1) begin
            imem[i] = 32'b0;
            dmem[i] = 32'b0;
        end

        // addi x1, x0, 5
        imem[0] = 32'h00500093;

        // Reset
        @(posedge i_clk);
        @(posedge i_clk);
        i_rst = 0;

        @(posedge i_clk);
        check("ADDI x1 = 5",
              32'h00500093,
              32'h00000000,
              32'h00000004,
              5'd1,
              32'h00000005);


        // --------------------------------------------------
        // Test 2: ADD
        // x1 = 5
        // x2 = 7
        // x3 = x1 + x2 = 12
        // --------------------------------------------------

        $display("--- Test 2: ADD ---");

        i_rst = 1;

        for (i = 0; i < 256; i = i + 1) begin
            imem[i] = 32'b0;
            dmem[i] = 32'b0;
        end

        // addi x1, x0, 5
        imem[0] = 32'h00500093;

        // addi x2, x0, 7
        imem[1] = 32'h00700113;

        // add x3, x1, x2
        imem[2] = 32'h002081b3;

        @(posedge i_clk);
        @(posedge i_clk);
        i_rst = 0;

        @(posedge i_clk);
        check("ADD x1 = 5",
              32'h00500093,
              32'h00000000,
              32'h00000004,
              5'd1,
              32'h00000005);

        @(posedge i_clk);
        check("ADD x2 = 7",
              32'h00700113,
              32'h00000004,
              32'h00000008,
              5'd2,
              32'h00000007);

        @(posedge i_clk);
        check("ADD x3 = 12",
              32'h002081b3,
              32'h00000008,
              32'h0000000c,
              5'd3,
              32'h0000000c);


        // --------------------------------------------------
        // Test 3: SUB
        // x1 = 10
        // x2 = 3
        // x3 = x1 - x2 = 7
        // --------------------------------------------------

        $display("--- Test 3: SUB ---");

        i_rst = 1;

        for (i = 0; i < 256; i = i + 1) begin
            imem[i] = 32'b0;
            dmem[i] = 32'b0;
        end

        // addi x1, x0, 10
        imem[0] = 32'h00a00093;

        // addi x2, x0, 3
        imem[1] = 32'h00300113;

        // sub x3, x1, x2
        imem[2] = 32'h402081b3;

        @(posedge i_clk);
        @(posedge i_clk);
        i_rst = 0;

        @(posedge i_clk);
        check("SUB x1 = 10",
              32'h00a00093,
              32'h00000000,
              32'h00000004,
              5'd1,
              32'h0000000a);

        @(posedge i_clk);
        check("SUB x2 = 3",
              32'h00300113,
              32'h00000004,
              32'h00000008,
              5'd2,
              32'h00000003);

        @(posedge i_clk);
        check("SUB x3 = 7",
              32'h402081b3,
              32'h00000008,
              32'h0000000c,
              5'd3,
              32'h00000007);


        // --------------------------------------------------
        // Test 4: BEQ
        // The branch should skip the instruction at PC = 12.
        // --------------------------------------------------

        $display("--- Test 4: BEQ ---");

        i_rst = 1;

        for (i = 0; i < 256; i = i + 1) begin
            imem[i] = 32'b0;
            dmem[i] = 32'b0;
        end

        // addi x1, x0, 5
        imem[0] = 32'h00500093;

        // addi x2, x0, 5
        imem[1] = 32'h00500113;

        // beq x1, x2, +8
        imem[2] = 32'h00208463;

        // This instruction should be skipped
        // addi x3, x0, 99
        imem[3] = 32'h06300193;

        // This instruction should execute
        // addi x3, x0, 42
        imem[4] = 32'h02a00193;

        @(posedge i_clk);
        @(posedge i_clk);
        i_rst = 0;

        @(posedge i_clk);
        check("BEQ x1 = 5",
              32'h00500093,
              32'h00000000,
              32'h00000004,
              5'd1,
              32'h00000005);

        @(posedge i_clk);
        check("BEQ x2 = 5",
              32'h00500113,
              32'h00000004,
              32'h00000008,
              5'd2,
              32'h00000005);

        @(posedge i_clk);
        check("BEQ taken",
              32'h00208463,
              32'h00000008,
              32'h00000010,
              5'd0,
              32'h00000000);

        // PC should now be 16, proving PC 12 was skipped.
        @(posedge i_clk);
        check("BEQ target executes",
              32'h02a00193,
              32'h00000010,
              32'h00000014,
              5'd3,
              32'h0000002a);


        // --------------------------------------------------
        // Test 5: SW / LW
        // Store 123 to memory[16], then load it into x3.
        // --------------------------------------------------

        $display("--- Test 5: SW / LW ---");

        i_rst = 1;

        for (i = 0; i < 256; i = i + 1) begin
            imem[i] = 32'b0;
            dmem[i] = 32'b0;
        end

        // addi x1, x0, 16
        imem[0] = 32'h01000093;

        // addi x2, x0, 123
        imem[1] = 32'h07b00113;

        // sw x2, 0(x1)
        imem[2] = 32'h0020a023;

        // lw x3, 0(x1)
        imem[3] = 32'h0000a183;

        @(posedge i_clk);
        @(posedge i_clk);
        i_rst = 0;

        @(posedge i_clk);
        check("SW/LW x1 = 16",
              32'h01000093,
              32'h00000000,
              32'h00000004,
              5'd1,
              32'h00000010);

        @(posedge i_clk);
        check("SW/LW x2 = 123",
              32'h07b00113,
              32'h00000004,
              32'h00000008,
              5'd2,
              32'h0000007b);

        @(posedge i_clk);
        check("SW stores x2",
              32'h0020a023,
              32'h00000008,
              32'h0000000c,
              5'd0,
              32'h0000007b);

        @(posedge i_clk);
        check("LW loads x3 = 123",
              32'h0000a183,
              32'h0000000c,
              32'h00000010,
              5'd3,
              32'h0000007b);


        // --- Verdict -------------------------------------------------------
        $display("=====================================");
        $display("%0d passed, %0d failed", passed, failed);

        if (failed == 0)
            $display("ALL TESTS PASSED");
        else
            $display("TEST FAILED");

        // Without $finish the simulation runs forever and iverilog's vvp
        // never returns.
        $finish;
    end

endmodule

`default_nettype wire
```
