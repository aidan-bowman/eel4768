`default_nettype none

// The floating-point unit implements the RISC-V F extension (single
// precision, IEEE 754-2008) and the Zicsr instructions for its control and
// status register fcsr. It sits in the execute stage beside the ALU and the
// multiply/divide unit, and decodes the details of its own instructions from
// the instruction word.
//
// It owns all F-extension state: fcsr, holding the dynamic rounding mode frm
// (fcsr[7:5]) and the accrued exception flags fflags (fcsr[4:0] = NV DZ OF
// UF NX). Floating-point exceptions never trap; they only set flags, which
// stay set until software clears them through a CSR instruction.
//
// fcsr only changes on a rising edge where the instruction in execute
// actually moves on to the memory stage (i_advance). An instruction can sit
// in execute for several cycles (for example while a cache miss freezes the
// pipeline); committing its flags or CSR write on every one of those cycles
// would make a CSR instruction read back its own write.
module fpu (
    // Global clock.
    input  wire        i_clk,
    // Synchronous active-high reset. Clears fcsr (frm = round to nearest,
    // ties to even; no flags set).
    input  wire        i_rst,
    // The instruction word in the execute stage.
    input  wire [31:0] i_inst,
    // Asserted when i_inst is a valid, legal floating-point unit instruction
    // (decoder o_fpu): every OP-FP and fused multiply-add instruction and the
    // CSR instructions on fflags/frm/fcsr.
    input  wire        i_valid,
    // Asserted when the instruction in execute advances to the memory stage
    // on the next rising edge. Side effects (fcsr updates) happen only then.
    input  wire        i_advance,
    // Floating-point source operands (rs1, rs2, rs3), raw IEEE bit patterns.
    input  wire [31:0] i_frs1,
    input  wire [31:0] i_frs2,
    input  wire [31:0] i_frs3,
    // Integer source operand (forwarded rs1), used by fmv.w.x, fcvt.s.w[u]
    // and the register forms of the CSR instructions.
    input  wire [31:0] i_xrs1,
    // Result for instructions that write a floating-point register.
    output wire [31:0] o_fp_result,
    // Result for instructions that write an integer register: fmv.x.w,
    // fclass.s, feq/flt/fle.s, fcvt.w[u].s, and the old CSR value.
    output wire [31:0] o_int_result,
    // The accrued exception flags as they will be after this instruction
    // (reported in the retire trace).
    output wire [ 4:0] o_fflags,
    // Asserted while a multi-cycle operation (fdiv.s/fsqrt.s) is in progress
    // and the instruction must stay in execute.
    output wire        o_busy,
    // Asserted when a rounding instruction selects the dynamic rounding mode
    // (rm = 111) while frm holds a reserved value (101-111). The instruction
    // traps as illegal and changes no state.
    output wire        o_rm_trap
);
    // ------------------------------------------------------------
    // Instruction decode and operand classification
    // ------------------------------------------------------------
    reg [7:0] fcsr;
    wire [23:0] op;
    wire [5:0] csr_op;
    wire [2:0] rm;
    wire [11:0] csr_addr;
    wire [9:0] rs1_mask;
    wire [9:0] rs2_mask;
    wire [9:0] rs3_mask;
    wire [2:0] effective_rm;

    fpu_decoder decoder (
        .i_inst(i_inst), .i_valid(i_valid), .o_op(op),
        .o_csr_op(csr_op), .o_rm(rm), .o_csr_addr(csr_addr)
    );
    classify classify_rs1 (.i_fp(i_frs1), .o_mask(rs1_mask));
    classify classify_rs2 (.i_fp(i_frs2), .o_mask(rs2_mask));
    classify classify_rs3 (.i_fp(i_frs3), .o_mask(rs3_mask));

    wire rs1_nan = rs1_mask[9] | rs1_mask[8];
    wire rs2_nan = rs2_mask[9] | rs2_mask[8];
    wire rs3_nan = rs3_mask[9] | rs3_mask[8];
    wire rs1_snan = rs1_mask[8];
    wire rs2_snan = rs2_mask[8];
    wire rs3_snan = rs3_mask[8];
    wire rs1_inf = rs1_mask[0] | rs1_mask[7];
    wire rs2_inf = rs2_mask[0] | rs2_mask[7];
    wire rs3_inf = rs3_mask[0] | rs3_mask[7];
    wire rs1_zero = rs1_mask[4] | rs1_mask[3];
    wire rs2_zero = rs2_mask[4] | rs2_mask[3];
    wire rs3_zero = rs3_mask[4] | rs3_mask[3];

    // Only operations that use the rm field can trap on a reserved dynamic
    // rounding mode. Sign injection, min/max, comparisons, moves, and CSR
    // operations do not use it.
    wire rounding_op = op[0] | op[1] | op[2] | op[3] | op[4] |
                       op[5] | op[6] | op[7] | op[8] |
                       op[18] | op[19] | op[20] | op[21];
    assign effective_rm = (rm == 3'b111) ? fcsr[7:5] : rm;
    assign o_rm_trap = i_valid && rounding_op && (rm == 3'b111) &&
                       (fcsr[7:5] >= 3'b101);

    // ------------------------------------------------------------
    // Multi-cycle add, multiply, and fused multiply-add datapath
    // ------------------------------------------------------------
    wire math_op = op[0] | op[1] | op[2] | op[5] | op[6] | op[7] | op[8];
    wire fused_op = op[5] | op[6] | op[7] | op[8];
    wire addsub_op = op[0] | op[1];
    wire product_op = op[2] | fused_op;
    wire product_sign = i_frs1[31] ^ i_frs2[31] ^ (op[7] | op[8]);
    wire add_b_sign = i_frs2[31] ^ op[1];
    wire fused_c_sign = i_frs3[31] ^ op[6] ^ op[8];
    wire product_invalid = product_op && ((rs1_inf && rs2_zero) || (rs2_inf && rs1_zero));
    wire add_inf_invalid = addsub_op && rs1_inf && rs2_inf &&
                           (i_frs1[31] != add_b_sign);
    wire fused_inf_invalid = fused_op && (rs1_inf || rs2_inf) && !product_invalid &&
                             rs3_inf && (product_sign != fused_c_sign);
    wire math_invalid = product_invalid | add_inf_invalid | fused_inf_invalid;
    wire product_inf = (rs1_inf || rs2_inf) && !product_invalid;
    wire product_zero = rs1_zero || rs2_zero;
    wire math_nan = rs1_nan || rs2_nan || (fused_op && rs3_nan);
    wire math_special = math_nan || math_invalid ||
                        (addsub_op && (rs1_inf || rs2_inf || rs1_zero || rs2_zero)) ||
                        (product_op && (product_inf || product_zero || (fused_op && rs3_inf)));
    wire [31:0] add_special_result =
        (rs1_inf || rs2_inf) ?
        {rs1_inf ? i_frs1[31] : add_b_sign, 8'hff, 23'b0} :
        (rs1_zero && rs2_zero) ?
        {((i_frs1[31] == add_b_sign) ? i_frs1[31] : (effective_rm == 3'b010)), 31'b0} :
        rs1_zero ? {add_b_sign, i_frs2[30:0]} : {i_frs1[31], i_frs1[30:0]};
    wire [31:0] product_special_result =
        product_inf ? {product_sign, 8'hff, 23'b0} :
        fused_op && !rs3_zero ? i_frs3 :
        fused_op && rs3_zero ?
        {((product_sign == fused_c_sign) ? product_sign : (effective_rm == 3'b010)), 31'b0} :
        {product_sign, 31'b0};
    wire [31:0] math_special_result = math_nan || math_invalid ? 32'h7fc00000 :
                                      addsub_op ? add_special_result : product_special_result;
    wire [4:0] math_special_fflags = (math_invalid || rs1_snan || rs2_snan ||
                                      (fused_op && rs3_snan)) ? 5'b10000 : 5'b0;
    wire math_active = math_op && !math_special;
    reg math_started;
    reg math_valid;
    wire math_start = math_active && !math_started && !math_valid && !o_rm_trap;

    // Reuse the multiply-add unit for addition by multiplying rs1 by 1.0.
    wire [31:0] math_a = (op[7] | op[8]) ? {~i_frs1[31], i_frs1[30:0]} :
                         (op[0] | op[1]) ? 32'h3f800000 : i_frs1;
    wire [31:0] math_b = (op[0] | op[1]) ? i_frs1 : i_frs2;
    wire [31:0] math_c = op[2] ? 32'b0 :
                         op[1] ? {~i_frs2[31], i_frs2[30:0]} :
                         (op[6] | op[8]) ? {~i_frs3[31], i_frs3[30:0]} :
                         (op[0] ? i_frs2 : i_frs3);
    wire math_add_en = !op[2];
    wire [37:0] math_intermediate;
    wire math_unit_busy;
    wire math_unit_ready;
    wire [31:0] math_result;
    wire [4:0] math_fflags;
    wire divsqrt_op = op[3] | op[4];
    reg divsqrt_started;
    reg divsqrt_valid;
    wire divsqrt_special = (op[4] && (rs1_nan || rs1_inf || rs1_zero ||
                                      (i_frs1[31] && !rs1_zero))) ||
                            (op[3] && (rs1_nan || rs2_nan ||
                                      (rs1_zero && rs2_zero) ||
                                      (rs1_inf && rs2_inf) || rs2_zero || rs2_inf ||
                                      rs1_inf || rs1_zero));
    wire divsqrt_invalid = (op[4] && i_frs1[31] && !rs1_zero && !rs1_nan) ||
                           (op[3] && ((rs1_zero && rs2_zero) || (rs1_inf && rs2_inf)));
    wire divsqrt_dz = op[3] && rs2_zero && !rs1_zero && !rs1_inf && !rs1_nan;
    wire [31:0] divsqrt_special_result =
        (rs1_nan || rs2_nan || divsqrt_invalid) ?
        32'h7fc00000 :
        op[4] ? (rs1_inf ? 32'h7f800000 : i_frs1) :
        (rs1_inf || rs2_zero) ? {(i_frs1[31] ^ i_frs2[31]), 8'hff, 23'b0} :
                                {(i_frs1[31] ^ i_frs2[31]), 31'b0};
    wire [4:0] divsqrt_special_fflags = divsqrt_invalid || rs1_snan || rs2_snan ?
                                         5'b10000 : (divsqrt_dz ? 5'b01000 : 5'b0);
    wire divsqrt_active = divsqrt_op && !divsqrt_special;
    wire divsqrt_start = divsqrt_active && !divsqrt_started && !divsqrt_valid && !o_rm_trap;
    wire [37:0] divsqrt_intermediate;
    wire divsqrt_unit_busy;
    wire divsqrt_unit_ready;
    wire [31:0] divsqrt_result;
    wire [4:0] divsqrt_fflags;

    fpu_multadd math_unit (
        .i_clk(i_clk), .i_rst(i_rst), .i_start(math_start),
        .i_rs1(math_a), .i_rs2(math_b), .i_rs3(math_c),
        .i_add_en(math_add_en), .o_prod(math_intermediate),
        .o_busy(math_unit_busy), .o_ready(math_unit_ready)
    );
    fpu_rounder rounder (
        .i_value(math_intermediate), .i_rm(effective_rm),
        .o_result(math_result), .o_fflags(math_fflags)
    );
    fpu_divsqrt divsqrt_unit (
        .i_clk(i_clk), .i_rst(i_rst), .i_start(divsqrt_start),
        .i_sqrt(op[4]), .i_a(i_frs1), .i_b(i_frs2),
        .o_value(divsqrt_intermediate), .o_busy(divsqrt_unit_busy),
        .o_ready(divsqrt_unit_ready)
    );
    fpu_rounder divsqrt_rounder (
        .i_value(divsqrt_intermediate), .i_rm(effective_rm),
        .o_result(divsqrt_result), .o_fflags(divsqrt_fflags)
    );

    // ------------------------------------------------------------
    // Integer and floating-point conversion datapaths
    // ------------------------------------------------------------
    function [36:0] convert_int_to_fp;
        input [31:0] value;
        input is_unsigned;
        input [2:0] rounding_mode;
        reg sign;
        reg [31:0] magnitude;
        reg found;
        integer lead;
        integer idx;
        integer shift;
        reg [23:0] significand;
        reg [31:0] shifted_value;
        reg guard_bit;
        reg sticky_bit;
        reg inexact;
        reg increment;
        reg [24:0] rounded;
        reg [7:0] exponent_field;
        begin
            sign = !is_unsigned && value[31];
            magnitude = sign ? (~value + 32'd1) : value;
            found = 1'b0;
            lead = 0;
            for (idx = 31; idx >= 0; idx = idx - 1) begin
                if (magnitude[idx] && !found) begin
                    lead = idx;
                    found = 1'b1;
                end
            end
            significand = 24'b0;
            guard_bit = 1'b0;
            sticky_bit = 1'b0;
            inexact = 1'b0;
            increment = 1'b0;
            if (found) begin
                if (lead <= 23) begin
                    shifted_value = magnitude;
                    for (idx = 0; idx < 23; idx = idx + 1) begin
                        if (idx < (23 - lead))
                            shifted_value = shifted_value << 1;
                    end
                    significand = shifted_value[23:0];
                end else begin
                    shift = lead - 23;
                    shifted_value = magnitude;
                    for (idx = 0; idx < 8; idx = idx + 1) begin
                        if (idx < shift) begin
                            sticky_bit = sticky_bit | guard_bit;
                            guard_bit = shifted_value[0];
                            shifted_value = shifted_value >> 1;
                        end
                    end
                    significand = shifted_value[23:0];
                    inexact = guard_bit | sticky_bit;
                    increment = (rounding_mode == 3'b000) ?
                                (guard_bit && (sticky_bit || significand[0])) :
                                (rounding_mode == 3'b010) ? (sign && inexact) :
                                (rounding_mode == 3'b011) ? (!sign && inexact) :
                                (rounding_mode == 3'b100) ? guard_bit : 1'b0;
                end
            end
            rounded = {1'b0, significand} + increment;
            exponent_field = lead + 8'd127 + rounded[24];
            convert_int_to_fp = {4'b0, inexact, sign,
                                 found ? exponent_field : 8'b0,
                                 found ? (rounded[24] ? rounded[23:1] : rounded[22:0]) : 23'b0};
        end
    endfunction

    function [36:0] convert_fp_to_int;
        input [31:0] value;
        input is_unsigned;
        input [2:0] rounding_mode;
        reg sign;
        reg [7:0] exp_field;
        reg [23:0] significand;
        reg signed [10:0] exponent;
        reg [63:0] magnitude;
        reg [63:0] rounded_magnitude;
        reg guard_bit;
        reg sticky_bit;
        reg inexact;
        reg increment;
        reg invalid;
        reg [31:0] result;
        reg [63:0] shifted_magnitude;
        reg [23:0] shifted_significand;
        integer shift;
        integer idx;
        begin
            sign = value[31];
            exp_field = value[30:23];
            significand = (exp_field == 0) ? {1'b0, value[22:0]} :
                                             {1'b1, value[22:0]};
            exponent = (exp_field == 0) ? -11'sd126 : $signed({3'b0, exp_field}) - 11'sd127;
            magnitude = 64'b0;
            guard_bit = 1'b0;
            sticky_bit = 1'b0;
            inexact = 1'b0;
            if (exponent > 11'sd31) begin
                magnitude = 64'h0000000100000000;
            end else if (exponent >= 11'sd23) begin
                shift = exponent - 11'sd23;
                shifted_magnitude = {40'b0, significand};
                for (idx = 0; idx < 8; idx = idx + 1) begin
                    if (idx < shift)
                        shifted_magnitude = shifted_magnitude << 1;
                end
                magnitude = shifted_magnitude;
            end else begin
                shift = 23 - exponent;
                if (shift < 24) begin
                    shifted_significand = significand;
                    for (idx = 0; idx < 24; idx = idx + 1) begin
                        if (idx < shift) begin
                            sticky_bit = sticky_bit | guard_bit;
                            guard_bit = shifted_significand[0];
                            shifted_significand = shifted_significand >> 1;
                        end
                    end
                    magnitude = shifted_significand;
                end else begin
                    magnitude = 0;
                    guard_bit = (shift == 24) ? significand[23] : 1'b0;
                    sticky_bit = (shift == 24) ? (|significand[22:0]) : (|significand);
                end
                inexact = guard_bit | sticky_bit;
            end
            increment = (rounding_mode == 3'b000) ?
                        (guard_bit && (sticky_bit || magnitude[0])) :
                        (rounding_mode == 3'b010) ? (sign && inexact) :
                        (rounding_mode == 3'b011) ? (!sign && inexact) :
                        (rounding_mode == 3'b100) ? guard_bit : 1'b0;
            rounded_magnitude = magnitude + increment;
            invalid = (exp_field == 8'hff) || (exponent > 11'sd31) ||
                      (!is_unsigned &&
                       ((!sign && (rounded_magnitude > 64'h000000007fffffff)) ||
                        (sign && (rounded_magnitude > 64'h0000000080000000)))) ||
                      (is_unsigned && sign && (|value[30:0]) && (rounded_magnitude != 0)) ||
                      (is_unsigned && !sign && (rounded_magnitude > 64'h00000000ffffffff));
            if (invalid) begin
                result = (exp_field == 8'hff && value[22:0] != 0) ?
                         (is_unsigned ? 32'hffffffff : 32'h7fffffff) :
                         is_unsigned ? (sign ? 32'b0 : 32'hffffffff) :
                         (sign ? 32'h80000000 : 32'h7fffffff);
            end else begin
                result = rounded_magnitude[31:0];
                if (!is_unsigned && sign)
                    result = ~result + 32'd1;
            end
            convert_fp_to_int = {invalid, 3'b0, (inexact && !invalid), result};
        end
    endfunction

    wire [36:0] int_to_fp_conv = convert_int_to_fp(i_xrs1, op[21], effective_rm);
    wire [36:0] fp_to_int_conv = convert_fp_to_int(i_frs1, op[19], effective_rm);

    always @(posedge i_clk) begin
        if (i_rst) begin
            math_started <= 1'b0;
            math_valid <= 1'b0;
        end else if (i_advance) begin
            math_started <= 1'b0;
            math_valid <= 1'b0;
        end else begin
            if (math_start)
                math_started <= 1'b1;
            if (math_unit_ready)
                math_valid <= 1'b1;
        end
    end

    always @(posedge i_clk) begin
        if (i_rst) begin
            divsqrt_started <= 1'b0;
            divsqrt_valid <= 1'b0;
        end else if (i_advance) begin
            divsqrt_started <= 1'b0;
            divsqrt_valid <= 1'b0;
        end else begin
            if (divsqrt_start)
                divsqrt_started <= 1'b1;
            if (divsqrt_unit_ready)
                divsqrt_valid <= 1'b1;
        end
    end

    assign o_busy = !o_rm_trap &&
                    ((math_active && !math_valid) || (divsqrt_active && !divsqrt_valid));

    // ------------------------------------------------------------
    // Floating-point control and status register
    // ------------------------------------------------------------

    // CSR reads return the old value. Register and immediate CSR forms share
    // the same update logic; immediate forms use the instruction's zimm field.
    wire [31:0] csr_old = (csr_addr == 12'h001) ? {27'b0, fcsr[4:0]} :
                          (csr_addr == 12'h002) ? {29'b0, fcsr[7:5]} :
                          {24'b0, fcsr};
    wire csr_write = |csr_op;
    wire csr_imm = csr_op[3] | csr_op[4] | csr_op[5];
    wire [31:0] csr_source = csr_imm ? {27'b0, i_inst[19:15]} : i_xrs1;
    wire [31:0] csr_new = (csr_op[0] | csr_op[3]) ? csr_source :
                          (csr_op[1] | csr_op[4]) ? (csr_old | csr_source) :
                          (csr_old & ~csr_source);

    // CSR writes and accrued exception flags commit only as the instruction
    // advances, so a stalled instruction cannot apply its side effect twice.
    always @(posedge i_clk) begin
        if (i_rst) begin
            fcsr <= 8'b0;
        end else if (i_advance) begin
            if (csr_write) begin
                if (csr_addr == 12'h001)
                    fcsr[4:0] <= csr_new[4:0];
                else if (csr_addr == 12'h002)
                    fcsr[7:5] <= csr_new[2:0];
                else if (csr_addr == 12'h003)
                    fcsr <= csr_new[7:0];
            end else if (math_op) begin
                fcsr[4:0] <= fcsr[4:0] | (math_special ? math_special_fflags : math_fflags);
            end else if (divsqrt_op) begin
                fcsr[4:0] <= fcsr[4:0] | (divsqrt_special ? divsqrt_special_fflags : divsqrt_fflags);
            end else if (op[18] | op[19]) begin
                fcsr[4:0] <= fcsr[4:0] | fp_to_int_conv[36:32];
            end else if (op[20] | op[21]) begin
                fcsr[4:0] <= fcsr[4:0] | int_to_fp_conv[36:32];
            end else if (op[14] | op[15] | op[16] | op[12] | op[13]) begin
                fcsr[4] <= fcsr[4] |
                           ((op[14] | op[15] | op[16]) && cmp_nv) |
                           ((op[12] | op[13]) && (rs1_mask[8] | rs2_mask[8]));
            end
        end
    end

    // ------------------------------------------------------------
    // Comparisons and min/max
    // ------------------------------------------------------------

    wire cmp_result;
    wire cmp_nv;
    compare compare_unit (
        .i_rm(rm), .i_rs1(i_frs1), .i_rs1_mask(rs1_mask),
        .i_rs2(i_frs2), .i_rs2_mask(rs2_mask),
        .o_out(cmp_result), .o_nv(cmp_nv)
    );

    // IEEE ordering by sign and magnitude, with explicit zero and NaN cases.
    // RISC-V min/max returns the numeric operand when only one input is NaN,
    // and the canonical NaN when both inputs are NaN.
    wire numeric_lt = (i_frs1[31] != i_frs2[31]) ? i_frs1[31] :
                      i_frs1[31] ? (i_frs1[30:0] > i_frs2[30:0]) :
                                   (i_frs1[30:0] < i_frs2[30:0]);
    wire minmax_lt = rs1_nan ? 1'b0 : rs2_nan ? 1'b1 :
                     (rs1_zero && rs2_zero) ? i_frs1[31] : numeric_lt;
    wire [31:0] minmax_result = rs1_nan && rs2_nan ? 32'h7fc00000 :
                                rs1_nan ? i_frs2 :
                                rs2_nan ? i_frs1 :
                                ((op[12] ? minmax_lt : ~minmax_lt) ?
                                 i_frs1 : i_frs2);

    // ------------------------------------------------------------
    // Result selection
    // ------------------------------------------------------------

    // Result selection for arithmetic, conversion, comparison, move, and CSR
    // datapaths. Invalid arithmetic cases use the canonical quiet NaN.
    assign o_fp_result = op[9]  ? {i_frs1[31], i_frs2[30:0]} :
                         op[10] ? {~i_frs1[31], i_frs2[30:0]} :
                         op[11] ? {i_frs1[31] ^ i_frs2[31], i_frs2[30:0]} :
                         (op[12] | op[13]) ? minmax_result :
                         math_op ? (math_special ? math_special_result : math_result) :
                         divsqrt_op ? (divsqrt_special ? divsqrt_special_result : divsqrt_result) :
                         (op[20] | op[21]) ? int_to_fp_conv[31:0] :
                         op[23] ? i_xrs1 : 32'b0;

    assign o_int_result = op[14] | op[15] | op[16] ? {31'b0, cmp_result} :
                          op[17] ? {22'b0, rs1_mask} :
                          op[22] ? i_frs1 :
                          (op[18] | op[19]) ? fp_to_int_conv[31:0] :
                          csr_write ? csr_old : 32'b0;

    wire [4:0] fflags_csr_result = (csr_write &&
                                     ((csr_addr == 12'h001) || (csr_addr == 12'h003))) ?
                                    csr_new[4:0] : fcsr[4:0];
    assign o_fflags = fflags_csr_result |
                      (math_op ? (math_special ? math_special_fflags : math_fflags) : 5'b0) |
                      (divsqrt_op ? (divsqrt_special ? divsqrt_special_fflags : divsqrt_fflags) : 5'b0) |
                      ((op[18] | op[19]) ? fp_to_int_conv[36:32] : 5'b0) |
                      ((op[20] | op[21]) ? int_to_fp_conv[36:32] : 5'b0) |
                      ((op[14] | op[15] | op[16]) ? {cmp_nv, 4'b0} : 5'b0) |
                      ((op[12] | op[13]) && (rs1_mask[8] | rs2_mask[8]) ?
                       5'b10000 : 5'b0);

endmodule

`default_nettype wire
