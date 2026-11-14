`default_nettype none

// Iterative RV32 signed/unsigned divider. A request runs for 32 cycles;
// divide-by-zero and signed-overflow cases return through the same ready
// handshake without entering the iteration loop.
module divider (
    input  wire        i_clk,
    input  wire        i_rst,
    input  wire        i_start,
    input  wire        i_signed,
    input  wire        i_rem,
    input  wire [31:0] i_a,
    input  wire [31:0] i_b,
    output reg  [31:0] o_result,
    output reg         o_busy,
    output reg         o_ready
);
    reg [5:0] count;
    reg [31:0] dividend_shift;
    reg [31:0] quotient;
    reg [31:0] divisor;
    reg [32:0] remainder;
    reg rem_mode;
    reg quotient_negative;
    reg remainder_negative;

    wire a_negative = i_signed && i_a[31];
    wire b_negative = i_signed && i_b[31];
    wire [31:0] a_magnitude = a_negative ? (~i_a + 32'd1) : i_a;
    wire [31:0] b_magnitude = b_negative ? (~i_b + 32'd1) : i_b;
    wire [32:0] trial_remainder = {remainder[31:0], dividend_shift[31]};
    wire subtract_divisor = (trial_remainder >= {1'b0, divisor});
    wire [32:0] remainder_next = subtract_divisor ?
                                 (trial_remainder - {1'b0, divisor}) :
                                 trial_remainder;
    wire [31:0] quotient_next = {quotient[30:0], subtract_divisor};
    wire [31:0] signed_quotient = quotient_negative ? (~quotient_next + 32'd1) : quotient_next;
    wire [31:0] signed_remainder = remainder_negative ? (~remainder_next[31:0] + 32'd1) :
                                                        remainder_next[31:0];

    always @(posedge i_clk) begin
        if (i_rst) begin
            count <= 6'b0;
            dividend_shift <= 32'b0;
            quotient <= 32'b0;
            divisor <= 32'b0;
            remainder <= 33'b0;
            rem_mode <= 1'b0;
            quotient_negative <= 1'b0;
            remainder_negative <= 1'b0;
            o_result <= 32'b0;
            o_busy <= 1'b0;
            o_ready <= 1'b0;
        end else begin
            o_ready <= 1'b0;
            if (i_start && !o_busy) begin
                if (i_b == 32'b0) begin
                    o_result <= i_rem ? i_a : 32'hffffffff;
                    o_ready <= 1'b1;
                end else if (i_signed && i_a == 32'h80000000 && i_b == 32'hffffffff) begin
                    o_result <= i_rem ? 32'b0 : 32'h80000000;
                    o_ready <= 1'b1;
                end else begin
                    count <= 6'b0;
                    dividend_shift <= a_magnitude;
                    quotient <= 32'b0;
                    divisor <= b_magnitude;
                    remainder <= 33'b0;
                    rem_mode <= i_rem;
                    quotient_negative <= a_negative ^ b_negative;
                    remainder_negative <= a_negative;
                    o_busy <= 1'b1;
                end
            end else if (o_busy) begin
                dividend_shift <= {dividend_shift[30:0], 1'b0};
                quotient <= quotient_next;
                remainder <= remainder_next;
                if (count == 6'd31) begin
                    o_result <= rem_mode ? signed_remainder : signed_quotient;
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
