`default_nettype none

// Iterative finite binary32 divide and square-root datapath. The result uses
// the exponent/sign/significand/GRS layout consumed by fpu_rounder.
module fpu_divsqrt (
    input  wire        i_clk,
    input  wire        i_rst,
    input  wire        i_start,
    input  wire        i_sqrt,
    input  wire [31:0] i_a,
    input  wire [31:0] i_b,
    output reg  [37:0] o_value,
    output reg         o_busy,
    output reg         o_ready
);
    function [33:0] normalize;
        input [31:0] value;
        reg [23:0] sig;
        reg signed [9:0] exp;
        integer lead;
        integer n;
        integer shift_count;
        reg found;
        begin
            if (value[30:23] != 0) begin
                sig = {1'b1, value[22:0]};
                exp = $signed({2'b0, value[30:23]}) - 10'sd127;
            end else begin
                sig = {1'b0, value[22:0]};
                exp = -10'sd126;
                lead = 0;
                found = 1'b0;
                for (n = 22; n >= 0; n = n - 1) begin
                    if (value[n] && !found) begin
                        lead = n;
                        found = 1'b1;
                    end
                end
                if (found) begin
                    shift_count = 23 - lead;
                    for (n = 0; n < 23; n = n + 1) begin
                        if (n < shift_count)
                            sig = sig << 1;
                    end
                    exp = exp - shift_count;
                end
            end
            normalize = {exp, sig};
        end
    endfunction

    wire [33:0] a_normalized = normalize(i_a);
    wire [33:0] b_normalized = normalize(i_b);
    wire [23:0] a_sig = a_normalized[23:0];
    wire [23:0] b_sig = b_normalized[23:0];
    wire signed [9:0] a_exp = $signed(a_normalized[33:24]);
    wire signed [9:0] b_exp = $signed(b_normalized[33:24]);

    reg sqrt_mode;
    reg [5:0] count;
    reg [49:0] dividend_shift;
    reg [49:0] quotient;
    reg [23:0] divisor;
    reg [24:0] div_remainder;
    reg signed [9:0] saved_a_exp;
    reg signed [9:0] saved_b_exp;
    reg saved_sign;
    reg [53:0] sqrt_rad_shift;
    reg [26:0] sqrt_root;
    reg [55:0] sqrt_remainder;

    wire [24:0] div_trial_remainder = {div_remainder[23:0], dividend_shift[49]};
    wire div_subtract = (div_trial_remainder >= {1'b0, divisor});
    wire [24:0] div_remainder_next = div_subtract ?
                                    (div_trial_remainder - {1'b0, divisor}) :
                                    div_trial_remainder;
    wire [49:0] quotient_next = {quotient[48:0], div_subtract};
    wire [26:0] quotient_raw = quotient_next[26:0];
    wire quotient_high = quotient_raw[26];
    wire [26:0] quotient_normalized = quotient_high ? quotient_raw :
                                      {quotient_raw[25:0], 1'b0};
    wire signed [9:0] quotient_exp = saved_a_exp - saved_b_exp -
                                      (quotient_high ? 10'sd0 : 10'sd1);
    wire [26:0] quotient_grs = {quotient_normalized[26:1],
                                quotient_normalized[0] | (|div_remainder_next)};

    wire [55:0] sqrt_trial_remainder = (sqrt_remainder << 2) |
                                        {54'b0, sqrt_rad_shift[53:52]};
    wire [28:0] sqrt_trial = {sqrt_root, 2'b01};
    wire sqrt_subtract = (sqrt_trial_remainder >= sqrt_trial);
    wire [55:0] sqrt_remainder_next = sqrt_subtract ?
                                      (sqrt_trial_remainder - sqrt_trial) :
                                      sqrt_trial_remainder;
    wire [26:0] sqrt_root_next = {sqrt_root[25:0], sqrt_subtract};
    wire exponent_odd = saved_a_exp[0];
    wire signed [9:0] sqrt_exp = exponent_odd ?
                                  ((saved_a_exp - 10'sd1) >>> 1) :
                                  (saved_a_exp >>> 1);
    wire [26:0] sqrt_grs = {sqrt_root_next[26:1],
                            sqrt_root_next[0] | (|sqrt_remainder_next)};

    always @(posedge i_clk) begin
        if (i_rst) begin
            o_value <= 38'b0;
            o_busy <= 1'b0;
            o_ready <= 1'b0;
            sqrt_mode <= 1'b0;
            count <= 6'b0;
            dividend_shift <= 50'b0;
            quotient <= 50'b0;
            divisor <= 24'b0;
            div_remainder <= 25'b0;
            saved_a_exp <= 10'sd0;
            saved_b_exp <= 10'sd0;
            saved_sign <= 1'b0;
            sqrt_rad_shift <= 54'b0;
            sqrt_root <= 27'b0;
            sqrt_remainder <= 56'b0;
        end else begin
            o_ready <= 1'b0;
            if (i_start && !o_busy) begin
                sqrt_mode <= i_sqrt;
                count <= 6'b0;
                saved_a_exp <= a_exp;
                saved_b_exp <= b_exp;
                saved_sign <= i_a[31] ^ i_b[31];
                o_busy <= 1'b1;
                if (i_sqrt) begin
                    sqrt_rad_shift <= a_exp[0] ? {a_sig, 30'b0} : {1'b0, a_sig, 29'b0};
                    sqrt_root <= 27'b0;
                    sqrt_remainder <= 56'b0;
                end else begin
                    dividend_shift <= {a_sig, 26'b0};
                    quotient <= 50'b0;
                    divisor <= b_sig;
                    div_remainder <= 25'b0;
                end
            end else if (o_busy && sqrt_mode) begin
                sqrt_rad_shift <= sqrt_rad_shift << 2;
                sqrt_root <= sqrt_root_next;
                sqrt_remainder <= sqrt_remainder_next;
                if (count == 6'd26) begin
                    o_value <= {sqrt_exp, 1'b0, sqrt_grs};
                    o_busy <= 1'b0;
                    o_ready <= 1'b1;
                end else begin
                    count <= count + 1'b1;
                end
            end else if (o_busy) begin
                dividend_shift <= {dividend_shift[48:0], 1'b0};
                quotient <= quotient_next;
                div_remainder <= div_remainder_next;
                if (count == 6'd49) begin
                    o_value <= {quotient_exp, saved_sign, quotient_grs};
                    o_busy <= 1'b0;
                    o_ready <= 1'b1;
                end else begin
                    count <= count + 1'b1;
                end
            end
        end
    end
endmodule

`default_nettype wire
