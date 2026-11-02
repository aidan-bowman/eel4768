`default_nettype none

// ##################################
// HAZARD CONTROL
// our job is to DETECT HAZARDS (data AND control)
// and STALL/FLUSH IF NECESSARY
// we don't handle FORWARDING or BYPASSING, that is handled elsewhere
// however, we need to know if we can forward or bypass, because it determines when we stall
module hazardctrl
  #(
     parameter FWD_EN = 1,
     parameter BYPASS_EN = 1
    )
    (
     // INPUTS:
     // ID
      input wire [4:0] i_id_rs1,    // potential RAW or Load-Use hazard
      input wire [4:0] i_id_rs2,    // potential RAW or Load-Store hazard
      input wire       i_id_store,  // necessary to see if load->store is happening
     // EX
      input wire [4:0] i_ex_rd,     // W part of RAW
      input wire [4:0] i_ex_rs1,    // destination for forwarding
      input wire [4:0] i_ex_rs2,    // destination for forwarding
      input wire       i_ex_load,   // necessary to see if load->store is happening
      input wire       i_ex_btaken, // true if we TAKE a branch in i_ex (later: implement better prediction)
     // MEM
      input wire [4:0] i_mem_rd,    // W part of RAW
     // WB
      input wire [4:0] i_wb_rd,     // W part of RAW
    
     // OUTPUTS:
     // IF
      output wire      o_if_hold,   // stall PC and disable IF/ID write
     // ID
      output wire      o_id_nop     // bubble/flush
     );

    // data hazards
    wire ex_match_rs1, ex_match_rs2;
    wire mem_match_rs1, mem_match_rs2;
    wire wb_match_rs1, wb_match_rs2;
    wire load_store_hazard;
    wire stall;

    // control hazards
    wire flush;

    assign ex_match_rs1 = (i_id_rs1 != 5'd0) &&
                          (i_ex_rd != 5'd0) &&
                          (i_id_rs1 == i_ex_rd);

    assign ex_match_rs2 = (i_id_rs2 != 5'd0) &&
                          (i_ex_rd != 5'd0) &&
                          (i_id_rs2 == i_ex_rd);
    
    assign mem_match_rs1 = (i_id_rs1 != 5'd0) &&
                           (i_mem_rd != 5'd0) &&
                           (i_id_rs1 == i_mem_rd);

    assign mem_match_rs2 = (i_id_rs2 != 5'd0) &&
                           (i_mem_rd != 5'd0) &&
                           (i_id_rs2 == i_mem_rd);
    
    assign wb_match_rs1 = (i_id_rs1 != 5'd0) &&
                          (i_wb_rd != 5'd0) &&
                          (i_id_rs1 == i_wb_rd);

    assign wb_match_rs2 = (i_id_rs2 != 5'd0) &&
                          (i_wb_rd != 5'd0) &&
                          (i_id_rs2 == i_wb_rd);

    assign flush = i_ex_btaken; // later: implement better prediction

    
    generate
        // see g_none first for baseline
        if (FWD_EN && BYPASS_EN) begin : g_bypass_forwarding
            // we can't forward from a load...
            // UNLESS we're doing load->store where store is storing loaded value
            // (load rd == store rs2)
            assign stall = i_ex_load & (ex_match_rs1 |
                                        (ex_match_rs2 & i_id_store));
        end else if (FWD_EN) begin : g_forwarding
            // this should honestly not be a case that happens
            // so let's just "throw an error"
            assign stall = 1'b1;
        end else if (BYPASS_EN) begin : g_bypass
            // baseline MINUS wb matches (since we can bypass)
            assign stall = ex_match_rs1 | ex_match_rs2 |
                           mem_match_rs1 | mem_match_rs2;
        end else begin : g_none
            // baseline: any matches are bad
            assign stall = ex_match_rs1 | ex_match_rs2 |
                           mem_match_rs1 | mem_match_rs2 |
                           wb_match_rs1 | wb_match_rs2;
        end
    endgenerate

    assign o_if_hold = stall & ~flush;
    assign o_id_nop  = stall | flush;
endmodule // hazardctrl

`default_nettype wire
