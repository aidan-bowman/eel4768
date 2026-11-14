/*
 * Module: compare
 *
 * Intent:
 *   Performs IEEE-754 single-precision floating-point comparisons.
 *
 * Inputs:
 *   i_rm       - Comparison operation (RISC-V funct3):
 *                3'b010 = EQ, 3'b001 = LT, 3'b000 = LE
 *   i_rs1      - First 32-bit floating-point operand
 *   i_rs1_mask - i_rs1's classification mask
 *   i_rs2      - Second 32-bit floating-point operand
 *   i_rs2_mask - i_rs2's classification mask
 *
 * Output:
 *   o_out - Comparison result (1 = true, 0 = false)
 *   o_nv  - whether the invalid instr flag should be raised
 *
 * TODO / Limitations:
 *   - Invalid i_rm encodings return 0.
 */

module compare (
                input wire [ 2:0] i_rm,
                input wire [31:0] i_rs1,
                input wire [9: 0] i_rs1_mask,
                input wire [31:0] i_rs2,
                input wire [9: 0] i_rs2_mask,
                output wire       o_out,
                output wire       o_nv
                );
    // detect a NaN; if either mask has 9 or 8, we're a NAN
    wire w_nan;
    assign w_nan = (|i_rs1_mask[9:8]) | (|i_rs2_mask[9:8]);

    // detect both zero; either 4 or 3
    wire w_both_zero;
    assign w_both_zero = (|i_rs1_mask[4:3]) & (|i_rs2_mask[4:3]);

    // Equality: +0 and -0 compare equal.
    wire w_eq;
    assign w_eq = ~w_nan &
                  (w_both_zero | (i_rs1 == i_rs2));

    // Magnitude comparison, excluding the sign bit.
    wire [30:0] w_rs1_mag;
    wire [30:0] w_rs2_mag;
    assign w_rs1_mag = i_rs1[30:0];
    assign w_rs2_mag = i_rs2[30:0];

    // Less-than comparison:
    //   Different signs: the negative operand is smaller.
    //   Both positive: compare magnitudes normally.
    //   Both negative: reverse the magnitude comparison.
    //   Both zeros: neither is less than the other.
    wire w_lt;
    assign w_lt = ~w_nan &
                  ~w_both_zero &
                  ((i_rs1[31] != i_rs2[31]) ?
                   i_rs1[31] :
                   (i_rs1[31] ?
                    (w_rs1_mag > w_rs2_mag) :
                    (w_rs1_mag < w_rs2_mag)));

    // Select the requested comparison operation.
    assign o_out = (i_rm == 3'b010) ? w_eq :
                   (i_rm == 3'b001) ? w_lt :
                   (i_rm == 3'b000) ? (w_eq | w_lt) :
                   1'b0;

    // if EQ op, raise only for signaling NaNs
    // else, raise for any NaNs
    assign o_nv  = (i_rm == 3'b010) ?
                   (i_rs1_mask[8] | i_rs2_mask[8]) :
                   w_nan;
                  
endmodule // compare
