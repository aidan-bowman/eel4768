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
module hart_tb #(
                 parameter DMEM_MAX_WORDS = 65536 // 2^16, or 64KB
                 );

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
    wire o_retire_valid;             // not used in trace
    wire [31:0] o_retire_inst;       // not used in trace
    wire o_retire_trap;
    wire o_retire_halt;
    wire [4:0] o_retire_rs1_raddr;
    wire [31:0] o_retire_rs1_rdata;
    wire [4:0] o_retire_rs2_raddr;
    wire [31:0] o_retire_rs2_rdata;
    wire [4:0] o_retire_rd_waddr;
    wire [31:0] o_retire_rd_wdata;
    wire [31:0] o_retire_pc;         // not used in trace
    wire [31:0] o_retire_next_pc;
    
    integer     start;
    integer     trace_file;
    
    

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

    // --------------------------------------------------
    // Instruction memory
    // --------------------------------------------------

    reg [31:0] imem [0:29999];

    // magic incantation to load hex program
    initial begin
        $readmemh("hart_program.hex", imem);
    end

    always @(*) begin
        i_imem_rdata = imem[o_imem_raddr >> 2];
    end


    // --------------------------------------------------
    // Data memory
    // --------------------------------------------------

    reg [31:0] mem_addr [0:DMEM_MAX_WORDS-1];
    reg [31:0] mem_data [0:DMEM_MAX_WORDS-1];

    integer mem_count;
    integer r;
    integer w;
    reg     found;
    reg [31:0] write_addr;
    reg [31:0] write_data;

    initial begin
        mem_count = 0;
    end

    // Combinational read
    always @(*) begin
        i_dmem_rdata = 32'b0;

        if (!o_dmem_ren) begin
            i_dmem_rdata = 32'b0;
        end
        else begin
            for (r = 0; r < mem_count; r = r + 1) begin
                if (mem_addr[r] == (o_dmem_addr >> 2))
                    i_dmem_rdata = mem_data[r];
            end
        end
    end // always @ (*)

    // Clocked write
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
                write_data[7:0]   = o_dmem_wdata[7:0];

            if (o_dmem_mask[1])
                write_data[15:8]  = o_dmem_wdata[15:8];

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
                mem_count           = mem_count + 1;
            end // else: !if(found)
        end // if (o_dmem_wen)
    end // always @ (posedge i_clk)


    // --------------------------------------------------
    // Clock
    // --------------------------------------------------

    always #5 i_clk = ~i_clk;


    // ---------------------------------------------------------------------
    // 4. The test program.
    // ---------------------------------------------------------------------

    // this block initializes the testing environment
    initial begin
        // Records a waveform of every signal in this testbench. Open it with
        // `gtkwave build/opmux.vcd` to see the inputs and outputs over time --
        // the fastest way to understand a failure the printout only summarizes.
        $dumpfile("hart.vcd");
        $dumpvars(0, hart_tb);

        trace_file = $fopen("generated.trace", "w");
        
        i_clk = 0;
        i_rst = 1;
        i_dmem_rdata = 0;

        // make sure we reset
        @(posedge i_clk);
        @(posedge i_clk);
        @(negedge i_clk);
        i_rst = 0;
    end // initial begin

    // this block runs testing once we start
    always @(posedge i_clk) begin
        if (i_rst == 0) begin
            $fwrite(trace_file, "%08x %08x %d %d %02x %08x %02x %08x %02x %08x %d %08x %x %08x %08x\n",
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
                    {o_dmem_wen, o_dmem_ren},
                    o_dmem_addr,
                    o_dmem_mask,
                    o_dmem_wdata,
                    o_retire_next_pc);
            
            if (o_retire_halt == 1) begin
                $finish;
            end
        end // if (i_rst == 0)
    end // always @ (posedge i_clk)
    
    
    // this block exists to make sure we close even if the program takes a while
    initial begin 
        #999999 $fclose(trace_file);
        $finish;
    end
endmodule

`default_nettype wire
