/*
 * Module: classify
 *
 * Intent:
 *   Classifies an IEEE-754 single-precision floating-point value
 *   according to the RISC-V FCLASS.S instruction.
 *
 * Inputs:
 *   i_fp    - 32-bit floating-point operand
 *
 * Outputs:
 *   o_mask  - 10-bit one-hot classification mask:
 *             [0] - Negative infinity
 *             [1] - Negative normal
 *             [2] - Negative subnormal
 *             [3] - Negative zero
 *             [4] - Positive zero
 *             [5] - Positive subnormal
 *             [6] - Positive normal
 *             [7] - Positive infinity
 *             [8] - Signaling NaN
 *             [9] - Quiet NaN
 *
 * TODO / Limitations:
 *   - Assumes IEEE-754 single-precision encoding.
 */

module classify (
                  input wire [31:0] i_fp,
                  output wire [9:0] o_mask
                 );

    // Extract sign, exponent, and fraction.
    wire        w_sign;
    wire [7:0]  w_exp;
    wire [22:0] w_frac;

    assign w_sign = i_fp[31];
    assign w_exp  = i_fp[30:23];
    assign w_frac = i_fp[22:0];

    // Common classification conditions.
    wire w_exp_zero;
    wire w_exp_ones;
    wire w_frac_zero;

    assign w_exp_zero  = (w_exp == 8'h00);
    assign w_exp_ones  = (w_exp == 8'hFF);
    assign w_frac_zero = (w_frac == 23'b0);

    // Individual classifications.
    wire w_inf;
    wire w_normal;
    wire w_subnormal;
    wire w_zero;
    wire w_nan;

    assign w_inf       = w_exp_ones & w_frac_zero;
    assign w_normal    = ~w_exp_zero & ~w_exp_ones;
    assign w_subnormal = w_exp_zero & ~w_frac_zero;
    assign w_zero      = w_exp_zero & w_frac_zero;
    assign w_nan       = w_exp_ones & ~w_frac_zero;

    // NaN classification:
    // The most significant fraction bit is the quiet/signaling bit.
    wire w_snan;
    wire w_qnan;

    assign w_snan = w_nan & ~w_frac[22];
    assign w_qnan = w_nan &  w_frac[22];

    // Construct the FCLASS.S one-hot result.
    assign o_mask = {
                     w_qnan,
                     w_snan,
                     w_inf       & ~w_sign,
                     w_normal    & ~w_sign,
                     w_subnormal & ~w_sign,
                     w_zero      & ~w_sign,
                     w_zero      &  w_sign,
                     w_subnormal &  w_sign,
                     w_normal    &  w_sign,
                     w_inf       &  w_sign
                     };

endmodule // classify
