/*
 * Module: fpu_multadd
 *
 * Description:
 *   Multi-cycle floating-point multiply-add datapath.
 *
 *   Computes:
 *       (i_rs1 * i_rs2) + i_rs3
 *
 *   The multiplier is an external iterative multiplier module.
 *   The addend can be bypassed using i_add_en.
 *
 * Intermediate result format (o_prod):
 *
 *   [37:28] : Signed 10-bit unbiased exponent (two's complement)
 *   [27]    : Result sign
 *   [26:3]  : 24-bit normalized significand
 *   [2]     : Guard bit
 *   [1]     : Round bit
 *   [0]     : Sticky bit
 *
 *   The intermediate is NOT an IEEE-754 encoded floating-point
 *   number. A separate rounding module must convert it into the
 *   final 32-bit IEEE-754 result.
 *
 * Handshake:
 *
 *   - Assert i_start for one clock cycle while the module is idle.
 *   - The input operands and i_add_en are latched on that cycle.
 *   - o_busy remains asserted while the operation is in progress.
 *   - o_ready is asserted when the intermediate result is available.
 *   - o_prod remains stable while the module is in the DONE state.
 *   - The module returns to IDLE after i_start is deasserted.
 *
 *   The multiplier receives a one-cycle start pulse and its
 *   o_ready signal is used to detect multiplication completion.
 *
 * i_add_en:
 *
 *   0 : Multiplication only. The addend is bypassed entirely.
 *   1 : Multiplication followed by addition/subtraction.
 *
 * TODO / Limitations:
 *
 *   - we need to round the output instead of keeping this dumb 38-bit output
 *   - input masks aren't implemented yet! would reduce the complexity of the module
 *   - shorten the header, lol
 *   - IEEE-754 special cases (NaN, infinity, zero, invalid
 *     operations, overflow and underflow) require additional
 *     handling.
 *   - Subnormal operand handling and result generation need
 *     verification.
 *   - Exact-zero sign handling needs to follow the selected
 *     rounding mode.
 *   - The rounding module must implement the required rounding
 *     modes and exception flags.
 *   - Verify sticky-bit propagation, particularly during
 *     subtraction and cancellation.
 *   - Fused operations must round only once, after this module.
 * 
 */
module fpu_multadd (
    input  wire        i_clk,
    input  wire        i_rst,
    input  wire        i_start,

    input  wire [31:0] i_rs1,
    input  wire [31:0] i_rs2,
    input  wire [31:0] i_rs3,

    input  wire        i_add_en,

    output wire [37:0] o_prod,
    output wire        o_busy,
    output wire        o_ready
);

    // ------------------------------------------------------------
    // State machine
    // ------------------------------------------------------------

    localparam S_IDLE      = 3'd0;
    localparam S_MUL_START = 3'd1;
    localparam S_MUL_WAIT  = 3'd2;
    localparam S_CALC      = 3'd3;
    localparam S_DONE      = 3'd4;

    reg [2:0] state;

    reg [31:0] a_reg;
    reg [31:0] b_reg;
    reg [31:0] c_reg;
    reg        add_en_reg;

    reg [37:0] result_reg;

    assign o_prod  = result_reg;
    assign o_busy  = (state != S_IDLE) && (state != S_DONE);
    assign o_ready = (state == S_DONE);

    // ------------------------------------------------------------
    // Unpack operands
    //
    // This datapath handles finite, nonzero operands.
    // The parent FPU must handle IEEE special cases.
    // ------------------------------------------------------------

    wire [23:0] a_sig;
    wire [23:0] b_sig;
    wire [23:0] c_sig;

    wire signed [9:0] a_exp;
    wire signed [9:0] b_exp;
    wire signed [9:0] c_exp;

    function [33:0] unpack_finite;
        input [31:0] value;
        reg [23:0] significand;
        reg signed [9:0] exponent;
        reg found;
        integer lead;
        integer bit_index;
        integer shift_count;
        begin
            if (value[30:23] != 0) begin
                significand = {1'b1, value[22:0]};
                exponent = $signed({2'b00, value[30:23]}) - 10'sd127;
            end else begin
                significand = {1'b0, value[22:0]};
                exponent = -10'sd126;
                found = 1'b0;
                lead = 0;
                for (bit_index = 22; bit_index >= 0; bit_index = bit_index - 1) begin
                    if (value[bit_index] && !found) begin
                        lead = bit_index;
                        found = 1'b1;
                    end
                end
                if (found) begin
                    shift_count = 23 - lead;
                    for (bit_index = 0; bit_index < 23; bit_index = bit_index + 1) begin
                        if (bit_index < shift_count)
                            significand = significand << 1;
                    end
                    exponent = exponent - shift_count;
                end
            end
            unpack_finite = {exponent, significand};
        end
    endfunction

    wire [33:0] a_unpacked = unpack_finite(a_reg);
    wire [33:0] b_unpacked = unpack_finite(b_reg);
    wire [33:0] c_unpacked = unpack_finite(c_reg);
    assign a_sig = a_unpacked[23:0];
    assign b_sig = b_unpacked[23:0];
    assign c_sig = c_unpacked[23:0];
    assign a_exp = $signed(a_unpacked[33:24]);
    assign b_exp = $signed(b_unpacked[33:24]);
    assign c_exp = $signed(c_unpacked[33:24]);

    // ------------------------------------------------------------
    // Iterative multiplier
    //
    // Only the 24-bit significands are multiplied.
    // Both operands are unsigned.
    // ------------------------------------------------------------

    wire [63:0] mul_product;
    wire        mul_busy;
    wire        mul_ready;

    wire [31:0] mul_a;
    wire [31:0] mul_b;

    assign mul_a = {8'b0, a_sig};
    assign mul_b = {8'b0, b_sig};

    multiplier u_multiplier (
        .i_clk         (i_clk),
        .i_rst         (i_rst),
        .i_start       (state == S_MUL_START),
        .i_mula        (mul_a),
        .i_mulb        (mul_b),
        .i_mula_signed (1'b0),
        .i_mulb_signed (1'b0),
        .o_prod        (mul_product),
        .o_busy        (mul_busy),
        .o_ready       (mul_ready)
    );

    // ------------------------------------------------------------
    // Normalize the 48-bit product.
    //
    // A 24x24 multiplication produces a 48-bit product.
    // The leading bit can be either bit 46 or bit 47.
    // ------------------------------------------------------------

    wire product_high;
    wire [23:0] product_sig;
    wire [2:0] product_grs;
    wire signed [9:0] product_exp;

    assign product_high = mul_product[47];

    assign product_sig = product_high
                       ? mul_product[47:24]
                       : mul_product[46:23];

    assign product_grs = product_high
                       ? {mul_product[23],
                          mul_product[22],
                          |mul_product[21:0]}
                       : {mul_product[22],
                          mul_product[21],
                          |mul_product[20:0]};

    assign product_exp = a_exp + b_exp
                       + (product_high ? 10'sd1 : 10'sd0);

    // Extend the significand with guard, round and sticky space.
    wire [26:0] product_ext;
    wire [26:0] c_ext;

    assign product_ext = {product_sig, product_grs};

    assign c_ext = {c_sig, 3'b000};

    // ------------------------------------------------------------
    // Exponent alignment
    //
    // The operand with the smaller exponent is shifted right.
    // Each stage uses a constant shift amount.
    // Shifted-out bits are accumulated into sticky.
    // ------------------------------------------------------------

    wire signed [9:0] exp_diff;
    wire [9:0] exp_distance;
    wire product_is_larger;

    assign exp_diff = product_exp - c_exp;
    assign product_is_larger = (exp_diff >= 0);

    assign exp_distance = product_is_larger
                        ? exp_diff
                        : -exp_diff;

    wire [26:0] smaller_initial;
    wire [26:0] sh1;
    wire [26:0] sh2;
    wire [26:0] sh4;
    wire [26:0] sh8;
    wire [26:0] sh16;
    wire [26:0] sh32;

    wire sticky1;
    wire sticky2;
    wire sticky4;
    wire sticky8;
    wire sticky16;
    wire sticky32;

    assign smaller_initial = product_is_larger ? c_ext : product_ext;

    assign sh1  = exp_distance[0] ? {1'b0, smaller_initial[26:1]} : smaller_initial;
    assign sticky1 = exp_distance[0] ? smaller_initial[0] : 1'b0;

    assign sh2  = exp_distance[1] ? {2'b0, sh1[26:2]} : sh1;
    assign sticky2 = sticky1 | (exp_distance[1] ? |sh1[1:0] : 1'b0);

    assign sh4  = exp_distance[2] ? {4'b0, sh2[26:4]} : sh2;
    assign sticky4 = sticky2 | (exp_distance[2] ? |sh2[3:0] : 1'b0);

    assign sh8  = exp_distance[3] ? {8'b0, sh4[26:8]} : sh4;
    assign sticky8 = sticky4 | (exp_distance[3] ? |sh4[7:0] : 1'b0);

    assign sh16 = exp_distance[4] ? {16'b0, sh8[26:16]} : sh8;
    assign sticky16 = sticky8 | (exp_distance[4] ? |sh8[15:0] : 1'b0);

    assign sh32 = exp_distance[5] ? {27'b0} : sh16;
    assign sticky32 = sticky16 | (exp_distance[5] ? |sh16 : 1'b0);

    wire [26:0] aligned_smaller;
    wire aligned_sticky;

    assign aligned_smaller = (|exp_distance[9:6])
                           ? 27'b0 : sh32;

    assign aligned_sticky = sticky32
                          | ((|exp_distance[9:6]) && (|smaller_initial));

    wire [26:0] aligned_product;
    wire [26:0] aligned_c;
    wire [26:0] aligned_smaller_jammed;

    // Preserve every bit shifted below the GRS field in the sticky position.
    assign aligned_smaller_jammed =
        {aligned_smaller[26:1], aligned_smaller[0] | aligned_sticky};

    assign aligned_product = product_is_larger
                           ? product_ext : aligned_smaller_jammed;

    assign aligned_c = product_is_larger
                     ? aligned_smaller_jammed : c_ext;

    wire [26:0] product_operand;
    wire [26:0] c_operand;

    assign product_operand = aligned_product;
    assign c_operand = aligned_c;

    // ------------------------------------------------------------
    // Add/subtract aligned significands
    // ------------------------------------------------------------

    wire product_sign;
    wire c_sign;

    assign product_sign = a_reg[31] ^ b_reg[31];
    assign c_sign = c_reg[31];

    wire effective_product_sign;
    wire effective_c_sign;

    assign effective_product_sign = product_sign;
    assign effective_c_sign = c_sign;

    wire [26:0] larger_mag;
    wire [26:0] smaller_mag;

    wire product_mag_larger;

    assign product_mag_larger = (product_operand >= c_operand);

    assign larger_mag = product_mag_larger
                      ? product_operand : c_operand;

    assign smaller_mag = product_mag_larger
                       ? c_operand : product_operand;

    wire same_sign;
    wire [27:0] arithmetic_result;
    wire result_sign;

    assign same_sign = (effective_product_sign == effective_c_sign);

    assign arithmetic_result = !add_en_reg
                             ? {1'b0, product_ext}
                             : (same_sign
                                ? ({1'b0, product_operand}
                                   + {1'b0, c_operand})
                                : ({1'b0, larger_mag}
                                   - {1'b0, smaller_mag}));

    assign result_sign = !add_en_reg
                       ? effective_product_sign
                       : (same_sign
                          ? effective_product_sign
                          : (product_mag_larger
                             ? effective_product_sign
                             : effective_c_sign));

    wire signed [9:0] result_exp_initial;

    assign result_exp_initial = !add_en_reg
                                ? product_exp
                                : (product_is_larger
                                   ? product_exp : c_exp);

    // ------------------------------------------------------------
    // Normalize arithmetic result
    //
    // First handle a carry into bit 27.
    // Then shift left in constant stages.
    // ------------------------------------------------------------

    wire [26:0] norm_input;
    wire signed [9:0] norm_exp_initial;
    wire norm_sticky_initial;

    assign norm_input = arithmetic_result[27]
                      ? arithmetic_result[27:1]
                      : arithmetic_result[26:0];

    assign norm_exp_initial = result_exp_initial
                            + (arithmetic_result[27] ? 10'sd1 : 10'sd0);

    assign norm_sticky_initial = aligned_sticky
                               | (arithmetic_result[27]
                                  ? arithmetic_result[0] : 1'b0);

    wire [26:0] left16;
    wire [26:0] left8;
    wire [26:0] left4;
    wire [26:0] left2;
    wire [26:0] left1;

    wire signed [9:0] exp16;
    wire signed [9:0] exp8;
    wire signed [9:0] exp4;
    wire signed [9:0] exp2;
    wire signed [9:0] exp1;

    assign left16 = (norm_input[26:11] == 16'b0)
                  ? {norm_input[10:0], 16'b0} : norm_input;

    assign exp16 = (norm_input[26:11] == 16'b0)
                 ? norm_exp_initial - 10'sd16 : norm_exp_initial;

    assign left8 = (left16[26:19] == 8'b0)
                 ? {left16[18:0], 8'b0} : left16;

    assign exp8 = (left16[26:19] == 8'b0)
                ? exp16 - 10'sd8 : exp16;

    assign left4 = (left8[26:23] == 4'b0)
                 ? {left8[22:0], 4'b0} : left8;

    assign exp4 = (left8[26:23] == 4'b0)
                ? exp8 - 10'sd4 : exp8;

    assign left2 = (left4[26:25] == 2'b0)
                 ? {left4[24:0], 2'b0} : left4;

    assign exp2 = (left4[26:25] == 2'b0)
                ? exp4 - 10'sd2 : exp4;

    assign left1 = (left2[26] == 1'b0)
                 ? {left2[25:0], 1'b0} : left2;

    assign exp1 = (left2[26] == 1'b0)
                ? exp2 - 10'sd1 : exp2;

    wire [26:0] normalized_sig;
    wire [26:0] normalized_sig_raw;
    wire signed [9:0] normalized_exp;

    assign normalized_sig_raw = left1;
    assign normalized_sig = {normalized_sig_raw[26:1],
                             normalized_sig_raw[0] | norm_sticky_initial};
    assign normalized_exp = exp1;

    // ------------------------------------------------------------
    // Sequential control
    // ------------------------------------------------------------

    always @(posedge i_clk) begin
        if (i_rst) begin
            state      <= S_IDLE;
            a_reg      <= 32'b0;
            b_reg      <= 32'b0;
            c_reg      <= 32'b0;
            add_en_reg <= 1'b0;
            result_reg <= 37'b0;
        end
        else begin
            case (state)

                S_IDLE: begin
                    if (i_start) begin
                        a_reg      <= i_rs1;
                        b_reg      <= i_rs2;
                        c_reg      <= i_rs3;
                        add_en_reg <= i_add_en;
                        state      <= S_MUL_START;
                    end
                end

                S_MUL_START: begin
                    state <= S_MUL_WAIT;
                end

                S_MUL_WAIT: begin
                    if (mul_ready) begin
                        state <= S_CALC;
                    end
                end

                S_CALC: begin
                    result_reg <= {
                                   normalized_exp,
                                   result_sign,
                                   normalized_sig[26:3],
                                   normalized_sig[2:0]
                                   };

                    state <= S_DONE;
                end

                S_DONE: begin
                    if (!i_start) begin
                        state <= S_IDLE;
                    end
                end

                default: begin
                    state <= S_IDLE;
                end

            endcase
        end
    end

endmodule
