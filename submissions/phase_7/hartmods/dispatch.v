`default_nettype none

/* DISPATCH
 */
module dispatch
  #(
    parameter BYPASS_EN = 1
    )
    (
     input wire        i_clk,
     input wire        i_rst,

     // CPU
     // hazard control
     input wire        i_stall,
     output wire       o_stall,
     // from fetch
     input wire [31:0] i_pc,
     input wire [31:0] i_instr,
     input wire        i_nop,
     // to reorder buffer
     );
    
endmodule // dispatch
