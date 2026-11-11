`default_nettype none

// Rounds the fpu_multadd intermediate format to IEEE-754 binary32.
// Intermediate layout: signed unbiased exponent, sign, 24-bit significand,
// guard, round, sticky. Supports all five RISC-V rounding modes.
module fpu_rounder (
    input  wire [37:0] i_value,
    input  wire [ 2:0] i_rm,
    output wire [31:0] o_result,
    output wire [ 4:0] o_fflags
);
    wire signed [9:0] exponent_in = $signed(i_value[37:28]);
    wire sign = i_value[27];
    wire [26:0] significand_in = i_value[26:0];

    function [27:0] right_shift_jam;
        input [26:0] value;
        input [4:0] amount;
        reg sticky;
        integer bit_index;
        begin
            sticky = 1'b0;
            for (bit_index = 0; bit_index < 27; bit_index = bit_index + 1) begin
                if (bit_index < amount) begin
                    sticky = sticky | value[0];
                    value = value >> 1;
                end
            end
            right_shift_jam = {sticky, value};
        end
    endfunction

    wire subnormal = (exponent_in < -10'sd126);
    wire signed [10:0] shift_signed = -11'sd126 - exponent_in;
    wire [4:0] shift_amount = (shift_signed > 11'sd27) ? 5'd27 : shift_signed[4:0];

    wire [27:0] shifted_pair = right_shift_jam(significand_in, shift_amount);
    wire [26:0] shifted = shifted_pair[26:0];
    wire shifted_out = shifted_pair[27];
    wire [26:0] significand = subnormal ? shifted : significand_in;
    wire sticky = subnormal ? (significand[0] | shifted_out) : significand[0];
    wire guard_bit = significand[2];
    wire round_bit = significand[1];
    wire sticky_bit = sticky;
    wire discarded = guard_bit | round_bit | sticky_bit;
    wire lsb = significand[3];

    wire increment = (i_rm == 3'b000) ? (guard_bit & (round_bit | sticky_bit | lsb)) :
                     (i_rm == 3'b001) ? 1'b0 :
                     (i_rm == 3'b010) ? (sign & discarded) :
                     (i_rm == 3'b011) ? (~sign & discarded) :
                     (i_rm == 3'b100) ? guard_bit : 1'b0;

    wire [24:0] rounded_sig = {1'b0, significand[26:3]} + increment;
    wire carry = rounded_sig[24];
    wire [23:0] normal_sig = carry ? rounded_sig[24:1] : rounded_sig[23:0];
    wire signed [10:0] exponent_rounded = {exponent_in[9], exponent_in} + {10'b0, carry};
    wire overflow = !subnormal && (exponent_rounded > 11'sd127);
    wire to_infinity = (i_rm == 3'b000) || (i_rm == 3'b100) ||
                       ((i_rm == 3'b010) && sign) ||
                       ((i_rm == 3'b011) && !sign);
    wire [31:0] overflow_result = to_infinity ? {sign, 8'hff, 23'b0} :
                                  {sign, 8'hfe, 23'h7fffff};

    wire [7:0] normal_exp_field = exponent_rounded + 11'sd127;
    wire [31:0] finite_result = subnormal ?
                                (rounded_sig[23] ? {sign, 8'h01, rounded_sig[22:0]} :
                                                   {sign, 8'h00, rounded_sig[22:0]}) :
                                {sign, normal_exp_field[7:0], normal_sig[22:0]};

    assign o_result = overflow ? overflow_result : finite_result;
    assign o_fflags[4] = 1'b0;
    assign o_fflags[3] = 1'b0;
    assign o_fflags[2] = overflow;
    assign o_fflags[1] = subnormal && discarded && !rounded_sig[23];
    assign o_fflags[0] = discarded | overflow;
endmodule

`default_nettype wire
