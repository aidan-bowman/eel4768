`default_nettype none

// The arithmetic logic unit (ALU) is responsible for performing the core
// calculations of the processor. It takes two 32-bit operands and outputs
// a 32 bit result based on the selection operation - addition, comparison,
// shift, or logical operation. This ALU is a purely combinational block, so
// you should not attempt to add any registers or pipeline it.
module alu (
    // Major operation selection.
    // 3'b000: addition/subtraction if `i_sub` asserted
    // 3'b001: shift left logical
    // 3'b010: set less than
    // 3'b011: set less than unsigned
    // 3'b100: exclusive or
    // 3'b101: shift right logical/arithmetic if `i_arith` asserted
    // 3'b110: or
    // 3'b111: and
    input  wire [ 2:0] i_opsel,
    // When asserted, addition operations should subtract instead.
    // This is only used for `i_opsel == 3'b000` (addition/subtraction).
    input  wire        i_sub,
    // When asserted, comparison operations should be treated as unsigned.
    // This is only used for branch comparisons, as the set less than unsigned
    // mode is already specified by `i_opsel`. For branch operations, the ALU
    // result is not used, only the comparison results.
    input  wire        i_unsigned,
    // When asserted, right shifts should be treated as arithmetic instead of
    // logical. This is only used for `i_opsel == 3'b101` (shift right).
    input  wire        i_arith,
    // First 32-bit input operand.
    input  wire [31:0] i_op1,
    // Second 32-bit input operand.
    input  wire [31:0] i_op2,
    // 32-bit output result. Any carry out (from addition) should be ignored.
    output wire [31:0] o_result,
    // Equality result. This is used downstream to determine if a
    // branch should be taken.
    output wire        o_eq,
    // Set less than result. This is used downstream to determine if a
    // branch should be taken.
    output wire        o_slt
);
    // Your implementation goes under here
    // ------------------------------------

    // ============================================================
    // 1. 32-BIT TWO'S-COMPLEMENT LOOKAHEAD CARRY ADDER
    // ============================================================

    // For subtraction:
    //     A - B = A + (~B) + 1
    //
    // i_sub = 0:
    //     A + B
    //
    // i_sub = 1:
    //     A + (~B) + 1

    wire [31:0] cla_b;
    wire [31:0] cla_p;
    wire [31:0] cla_g;
    wire [32:0] cla_c;
    wire [31:0] cla_sum;

    assign cla_b = i_op2 ^ {32{i_sub}};

    // Propagate and generate signals
    assign cla_p = i_op1 ^ cla_b;
    assign cla_g = i_op1 & cla_b;

    // Initial carry-in
    assign cla_c[0] = i_sub;


    // ------------------------------------------------------------
    // Four-bit CLA group propagate/generate
    // ------------------------------------------------------------

    wire [7:0] group_p;
    wire [7:0] group_g;

    // Group 0: bits 3:0
    assign group_p[0] = cla_p[3] &
                        cla_p[2] &
                        cla_p[1] &
                        cla_p[0];

    assign group_g[0] = cla_g[3] |
                        (cla_p[3] & cla_g[2]) |
                        (cla_p[3] & cla_p[2] & cla_g[1]) |
                        (cla_p[3] & cla_p[2] & cla_p[1] & cla_g[0]);

    // Group 1: bits 7:4
    assign group_p[1] = cla_p[7] &
                        cla_p[6] &
                        cla_p[5] &
                        cla_p[4];

    assign group_g[1] = cla_g[7] |
                        (cla_p[7] & cla_g[6]) |
                        (cla_p[7] & cla_p[6] & cla_g[5]) |
                        (cla_p[7] & cla_p[6] & cla_p[5] & cla_g[4]);

    // Group 2: bits 11:8
    assign group_p[2] = cla_p[11] &
                        cla_p[10] &
                        cla_p[9] &
                        cla_p[8];

    assign group_g[2] = cla_g[11] |
                        (cla_p[11] & cla_g[10]) |
                        (cla_p[11] & cla_p[10] & cla_g[9]) |
                        (cla_p[11] & cla_p[10] & cla_p[9] & cla_g[8]);

    // Group 3: bits 15:12
    assign group_p[3] = cla_p[15] &
                        cla_p[14] &
                        cla_p[13] &
                        cla_p[12];

    assign group_g[3] = cla_g[15] |
                        (cla_p[15] & cla_g[14]) |
                        (cla_p[15] & cla_p[14] & cla_g[13]) |
                        (cla_p[15] & cla_p[14] & cla_p[13] & cla_g[12]);

    // Group 4: bits 19:16
    assign group_p[4] = cla_p[19] &
                        cla_p[18] &
                        cla_p[17] &
                        cla_p[16];

    assign group_g[4] = cla_g[19] |
                        (cla_p[19] & cla_g[18]) |
                        (cla_p[19] & cla_p[18] & cla_g[17]) |
                        (cla_p[19] & cla_p[18] & cla_p[17] & cla_g[16]);

    // Group 5: bits 23:20
    assign group_p[5] = cla_p[23] &
                        cla_p[22] &
                        cla_p[21] &
                        cla_p[20];

    assign group_g[5] = cla_g[23] |
                        (cla_p[23] & cla_g[22]) |
                        (cla_p[23] & cla_p[22] & cla_g[21]) |
                        (cla_p[23] & cla_p[22] & cla_p[21] & cla_g[20]);

    // Group 6: bits 27:24
    assign group_p[6] = cla_p[27] &
                        cla_p[26] &
                        cla_p[25] &
                        cla_p[24];

    assign group_g[6] = cla_g[27] |
                        (cla_p[27] & cla_g[26]) |
                        (cla_p[27] & cla_p[26] & cla_g[25]) |
                        (cla_p[27] & cla_p[26] & cla_p[25] & cla_g[24]);

    // Group 7: bits 31:28
    assign group_p[7] = cla_p[31] &
                        cla_p[30] &
                        cla_p[29] &
                        cla_p[28];

    assign group_g[7] = cla_g[31] |
                        (cla_p[31] & cla_g[30]) |
                        (cla_p[31] & cla_p[30] & cla_g[29]) |
                        (cla_p[31] & cla_p[30] & cla_p[29] & cla_g[28]);


    // ------------------------------------------------------------
    // Lookahead carry between the four-bit groups
    // ------------------------------------------------------------

    assign cla_c[4] = group_g[0] |
                      (group_p[0] & cla_c[0]);

    assign cla_c[8] = group_g[1] |
                      (group_p[1] & group_g[0]) |
                      (group_p[1] & group_p[0] & cla_c[0]);

    assign cla_c[12] = group_g[2] |
                       (group_p[2] & group_g[1]) |
                       (group_p[2] & group_p[1] & group_g[0]) |
                       (group_p[2] & group_p[1] & group_p[0] & cla_c[0]);

    assign cla_c[16] = group_g[3] |
                       (group_p[3] & group_g[2]) |
                       (group_p[3] & group_p[2] & group_g[1]) |
                       (group_p[3] & group_p[2] & group_p[1] & group_g[0]) |
                       (group_p[3] & group_p[2] & group_p[1] & group_p[0] & cla_c[0]);

    assign cla_c[20] = group_g[4] |
                       (group_p[4] & group_g[3]) |
                       (group_p[4] & group_p[3] & group_g[2]) |
                       (group_p[4] & group_p[3] & group_p[2] & group_g[1]) |
                       (group_p[4] & group_p[3] & group_p[2] & group_p[1] & group_g[0]) |
                       (group_p[4] & group_p[3] & group_p[2] & group_p[1] & group_p[0] & cla_c[0]);

    assign cla_c[24] = group_g[5] |
                       (group_p[5] & group_g[4]) |
                       (group_p[5] & group_p[4] & group_g[3]) |
                       (group_p[5] & group_p[4] & group_p[3] & group_g[2]) |
                       (group_p[5] & group_p[4] & group_p[3] & group_p[2] & group_g[1]) |
                       (group_p[5] & group_p[4] & group_p[3] & group_p[2] & group_p[1] & group_g[0]) |
                       (group_p[5] & group_p[4] & group_p[3] & group_p[2] & group_p[1] & group_p[0] & cla_c[0]);

    assign cla_c[28] = group_g[6] |
                       (group_p[6] & group_g[5]) |
                       (group_p[6] & group_p[5] & group_g[4]) |
                       (group_p[6] & group_p[5] & group_p[4] & group_g[3]) |
                       (group_p[6] & group_p[5] & group_p[4] & group_p[3] & group_g[2]) |
                       (group_p[6] & group_p[5] & group_p[4] & group_p[3] & group_p[2] & group_g[1]) |
                       (group_p[6] & group_p[5] & group_p[4] & group_p[3] & group_p[2] & group_p[1] & group_g[0]) |
                       (group_p[6] & group_p[5] & group_p[4] & group_p[3] & group_p[2] & group_p[1] & group_p[0] & cla_c[0]);

    assign cla_c[32] = group_g[7] |
                       (group_p[7] & group_g[6]) |
                       (group_p[7] & group_p[6] & group_g[5]) |
                       (group_p[7] & group_p[6] & group_p[5] & group_g[4]) |
                       (group_p[7] & group_p[6] & group_p[5] & group_p[4] & group_g[3]) |
                       (group_p[7] & group_p[6] & group_p[5] & group_p[4] & group_p[3] & group_g[2]) |
                       (group_p[7] & group_p[6] & group_p[5] & group_p[4] & group_p[3] & group_p[2] & group_g[1]) |
                       (group_p[7] & group_p[6] & group_p[5] & group_p[4] & group_p[3] & group_p[2] & group_p[1] & group_g[0]) |
                       (group_p[7] & group_p[6] & group_p[5] & group_p[4] & group_p[3] & group_p[2] & group_p[1] & group_p[0] & cla_c[0]);


    // ------------------------------------------------------------
    // Lookahead carries inside each four-bit group
    // ------------------------------------------------------------

    // Group 0
    assign cla_c[1] = cla_g[0] |
                      (cla_p[0] & cla_c[0]);

    assign cla_c[2] = cla_g[1] |
                      (cla_p[1] & cla_g[0]) |
                      (cla_p[1] & cla_p[0] & cla_c[0]);

    assign cla_c[3] = cla_g[2] |
                      (cla_p[2] & cla_g[1]) |
                      (cla_p[2] & cla_p[1] & cla_g[0]) |
                      (cla_p[2] & cla_p[1] & cla_p[0] & cla_c[0]);


    // Group 1
    assign cla_c[5] = cla_g[4] |
                      (cla_p[4] & cla_c[4]);

    assign cla_c[6] = cla_g[5] |
                      (cla_p[5] & cla_g[4]) |
                      (cla_p[5] & cla_p[4] & cla_c[4]);

    assign cla_c[7] = cla_g[6] |
                      (cla_p[6] & cla_g[5]) |
                      (cla_p[6] & cla_p[5] & cla_g[4]) |
                      (cla_p[6] & cla_p[5] & cla_p[4] & cla_c[4]);


    // Group 2
    assign cla_c[9] = cla_g[8] |
                      (cla_p[8] & cla_c[8]);

    assign cla_c[10] = cla_g[9] |
                       (cla_p[9] & cla_g[8]) |
                       (cla_p[9] & cla_p[8] & cla_c[8]);

    assign cla_c[11] = cla_g[10] |
                       (cla_p[10] & cla_g[9]) |
                       (cla_p[10] & cla_p[9] & cla_g[8]) |
                       (cla_p[10] & cla_p[9] & cla_p[8] & cla_c[8]);


    // Group 3
    assign cla_c[13] = cla_g[12] |
                       (cla_p[12] & cla_c[12]);

    assign cla_c[14] = cla_g[13] |
                       (cla_p[13] & cla_g[12]) |
                       (cla_p[13] & cla_p[12] & cla_c[12]);

    assign cla_c[15] = cla_g[14] |
                       (cla_p[14] & cla_g[13]) |
                       (cla_p[14] & cla_p[13] & cla_g[12]) |
                       (cla_p[14] & cla_p[13] & cla_p[12] & cla_c[12]);


    // Group 4
    assign cla_c[17] = cla_g[16] |
                       (cla_p[16] & cla_c[16]);

    assign cla_c[18] = cla_g[17] |
                       (cla_p[17] & cla_g[16]) |
                       (cla_p[17] & cla_p[16] & cla_c[16]);

    assign cla_c[19] = cla_g[18] |
                       (cla_p[18] & cla_g[17]) |
                       (cla_p[18] & cla_p[17] & cla_g[16]) |
                       (cla_p[18] & cla_p[17] & cla_p[16] & cla_c[16]);


    // Group 5
    assign cla_c[21] = cla_g[20] |
                       (cla_p[20] & cla_c[20]);

    assign cla_c[22] = cla_g[21] |
                       (cla_p[21] & cla_g[20]) |
                       (cla_p[21] & cla_p[20] & cla_c[20]);

    assign cla_c[23] = cla_g[22] |
                       (cla_p[22] & cla_g[21]) |
                       (cla_p[22] & cla_p[21] & cla_g[20]) |
                       (cla_p[22] & cla_p[21] & cla_p[20] & cla_c[20]);


    // Group 6
    assign cla_c[25] = cla_g[24] |
                       (cla_p[24] & cla_c[24]);

    assign cla_c[26] = cla_g[25] |
                       (cla_p[25] & cla_g[24]) |
                       (cla_p[25] & cla_p[24] & cla_c[24]);

    assign cla_c[27] = cla_g[26] |
                       (cla_p[26] & cla_g[25]) |
                       (cla_p[26] & cla_p[25] & cla_g[24]) |
                       (cla_p[26] & cla_p[25] & cla_p[24] & cla_c[24]);


    // Group 7
    assign cla_c[29] = cla_g[28] |
                       (cla_p[28] & cla_c[28]);

    assign cla_c[30] = cla_g[29] |
                       (cla_p[29] & cla_g[28]) |
                       (cla_p[29] & cla_p[28] & cla_c[28]);

    assign cla_c[31] = cla_g[30] |
                       (cla_p[30] & cla_g[29]) |
                       (cla_p[30] & cla_p[29] & cla_g[28]) |
                       (cla_p[30] & cla_p[29] & cla_p[28] & cla_c[28]);


    // Sum
    assign cla_sum = cla_p ^ cla_c[31:0];


    // ============================================================
    // 2. BARREL SHIFTER
    // ============================================================

    // Five stages allow shifts of:
    // 1, 2, 4, 8, and 16 bits.
    //
    // The bits of i_op2[4:0] select which stages are active.
    // This supports every shift amount from 0 through 31.

    wire [31:0] sll_1;
    wire [31:0] sll_2;
    wire [31:0] sll_4;
    wire [31:0] sll_8;
    wire [31:0] sll_16;

    assign sll_1 = i_op2[0] ?
                   {i_op1[30:0], 1'b0} :
                   i_op1;

    assign sll_2 = i_op2[1] ?
                   {sll_1[29:0], 2'b0} :
                   sll_1;

    assign sll_4 = i_op2[2] ?
                   {sll_2[27:0], 4'b0} :
                   sll_2;

    assign sll_8 = i_op2[3] ?
                   {sll_4[23:0], 8'b0} :
                   sll_4;

    assign sll_16 = i_op2[4] ?
                    {sll_8[15:0], 16'b0} :
                    sll_8;


    // Logical right shift
    wire [31:0] srl_1;
    wire [31:0] srl_2;
    wire [31:0] srl_4;
    wire [31:0] srl_8;
    wire [31:0] srl_16;

    assign srl_1 = i_op2[0] ?
                   {1'b0, i_op1[31:1]} :
                   i_op1;

    assign srl_2 = i_op2[1] ?
                   {2'b0, srl_1[31:2]} :
                   srl_1;

    assign srl_4 = i_op2[2] ?
                   {4'b0, srl_2[31:4]} :
                   srl_2;

    assign srl_8 = i_op2[3] ?
                   {8'b0, srl_4[31:8]} :
                   srl_4;

    assign srl_16 = i_op2[4] ?
                    {16'b0, srl_8[31:16]} :
                    srl_8;


    // Arithmetic right shift
    wire [31:0] sra_1;
    wire [31:0] sra_2;
    wire [31:0] sra_4;
    wire [31:0] sra_8;
    wire [31:0] sra_16;

    assign sra_1 = i_op2[0] ?
                   {{1{i_op1[31]}}, i_op1[31:1]} :
                   i_op1;

    assign sra_2 = i_op2[1] ?
                   {{2{sra_1[31]}}, sra_1[31:2]} :
                   sra_1;

    assign sra_4 = i_op2[2] ?
                   {{4{sra_2[31]}}, sra_2[31:4]} :
                   sra_2;

    assign sra_8 = i_op2[3] ?
                   {{8{sra_4[31]}}, sra_4[31:8]} :
                   sra_4;

    assign sra_16 = i_op2[4] ?
                    {{16{sra_8[31]}}, sra_8[31:16]} :
                    sra_8;


    wire [31:0] shift_left_result;
    wire [31:0] shift_right_result;

    assign shift_left_result = sll_16;

    assign shift_right_result = i_arith ?
                                sra_16 :
                                srl_16;


    // ============================================================
    // 3. COMPARATOR
    // ============================================================

    // Equality of each bit, starting from the most significant bit.
    // eq_prefix[n] means all bits from 31 down through n are equal.

    wire [31:0] eq_prefix;

    assign eq_prefix[31] = ~(i_op1[31] ^ i_op2[31]);

    assign eq_prefix[30] = eq_prefix[31] &
                           ~(i_op1[30] ^ i_op2[30]);

    assign eq_prefix[29] = eq_prefix[30] &
                           ~(i_op1[29] ^ i_op2[29]);

    assign eq_prefix[28] = eq_prefix[29] &
                           ~(i_op1[28] ^ i_op2[28]);

    assign eq_prefix[27] = eq_prefix[28] &
                           ~(i_op1[27] ^ i_op2[27]);

    assign eq_prefix[26] = eq_prefix[27] &
                           ~(i_op1[26] ^ i_op2[26]);

    assign eq_prefix[25] = eq_prefix[26] &
                           ~(i_op1[25] ^ i_op2[25]);

    assign eq_prefix[24] = eq_prefix[25] &
                           ~(i_op1[24] ^ i_op2[24]);

    assign eq_prefix[23] = eq_prefix[24] &
                           ~(i_op1[23] ^ i_op2[23]);

    assign eq_prefix[22] = eq_prefix[23] &
                           ~(i_op1[22] ^ i_op2[22]);

    assign eq_prefix[21] = eq_prefix[22] &
                           ~(i_op1[21] ^ i_op2[21]);

    assign eq_prefix[20] = eq_prefix[21] &
                           ~(i_op1[20] ^ i_op2[20]);

    assign eq_prefix[19] = eq_prefix[20] &
                           ~(i_op1[19] ^ i_op2[19]);

    assign eq_prefix[18] = eq_prefix[19] &
                           ~(i_op1[18] ^ i_op2[18]);

    assign eq_prefix[17] = eq_prefix[18] &
                           ~(i_op1[17] ^ i_op2[17]);

    assign eq_prefix[16] = eq_prefix[17] &
                           ~(i_op1[16] ^ i_op2[16]);

    assign eq_prefix[15] = eq_prefix[16] &
                           ~(i_op1[15] ^ i_op2[15]);

    assign eq_prefix[14] = eq_prefix[15] &
                           ~(i_op1[14] ^ i_op2[14]);

    assign eq_prefix[13] = eq_prefix[14] &
                           ~(i_op1[13] ^ i_op2[13]);

    assign eq_prefix[12] = eq_prefix[13] &
                           ~(i_op1[12] ^ i_op2[12]);

    assign eq_prefix[11] = eq_prefix[12] &
                           ~(i_op1[11] ^ i_op2[11]);

    assign eq_prefix[10] = eq_prefix[11] &
                           ~(i_op1[10] ^ i_op2[10]);

    assign eq_prefix[9] = eq_prefix[10] &
                          ~(i_op1[9] ^ i_op2[9]);

    assign eq_prefix[8] = eq_prefix[9] &
                          ~(i_op1[8] ^ i_op2[8]);

    assign eq_prefix[7] = eq_prefix[8] &
                          ~(i_op1[7] ^ i_op2[7]);

    assign eq_prefix[6] = eq_prefix[7] &
                          ~(i_op1[6] ^ i_op2[6]);

    assign eq_prefix[5] = eq_prefix[6] &
                          ~(i_op1[5] ^ i_op2[5]);

    assign eq_prefix[4] = eq_prefix[5] &
                          ~(i_op1[4] ^ i_op2[4]);

    assign eq_prefix[3] = eq_prefix[4] &
                          ~(i_op1[3] ^ i_op2[3]);

    assign eq_prefix[2] = eq_prefix[3] &
                          ~(i_op1[2] ^ i_op2[2]);

    assign eq_prefix[1] = eq_prefix[2] &
                          ~(i_op1[1] ^ i_op2[1]);

    assign eq_prefix[0] = eq_prefix[1] &
                          ~(i_op1[0] ^ i_op2[0]);


    // Unsigned comparison:
    // The first differing bit determines which operand is smaller.

    wire unsigned_less;

    assign unsigned_less =
        ((~i_op1[31]) & i_op2[31]) |
        (eq_prefix[31] & (~i_op1[30]) & i_op2[30]) |
        (eq_prefix[30] & (~i_op1[29]) & i_op2[29]) |
        (eq_prefix[29] & (~i_op1[28]) & i_op2[28]) |
        (eq_prefix[28] & (~i_op1[27]) & i_op2[27]) |
        (eq_prefix[27] & (~i_op1[26]) & i_op2[26]) |
        (eq_prefix[26] & (~i_op1[25]) & i_op2[25]) |
        (eq_prefix[25] & (~i_op1[24]) & i_op2[24]) |
        (eq_prefix[24] & (~i_op1[23]) & i_op2[23]) |
        (eq_prefix[23] & (~i_op1[22]) & i_op2[22]) |
        (eq_prefix[22] & (~i_op1[21]) & i_op2[21]) |
        (eq_prefix[21] & (~i_op1[20]) & i_op2[20]) |
        (eq_prefix[20] & (~i_op1[19]) & i_op2[19]) |
        (eq_prefix[19] & (~i_op1[18]) & i_op2[18]) |
        (eq_prefix[18] & (~i_op1[17]) & i_op2[17]) |
        (eq_prefix[17] & (~i_op1[16]) & i_op2[16]) |
        (eq_prefix[16] & (~i_op1[15]) & i_op2[15]) |
        (eq_prefix[15] & (~i_op1[14]) & i_op2[14]) |
        (eq_prefix[14] & (~i_op1[13]) & i_op2[13]) |
        (eq_prefix[13] & (~i_op1[12]) & i_op2[12]) |
        (eq_prefix[12] & (~i_op1[11]) & i_op2[11]) |
        (eq_prefix[11] & (~i_op1[10]) & i_op2[10]) |
        (eq_prefix[10] & (~i_op1[9]) & i_op2[9]) |
        (eq_prefix[9] & (~i_op1[8]) & i_op2[8]) |
        (eq_prefix[8] & (~i_op1[7]) & i_op2[7]) |
        (eq_prefix[7] & (~i_op1[6]) & i_op2[6]) |
        (eq_prefix[6] & (~i_op1[5]) & i_op2[5]) |
        (eq_prefix[5] & (~i_op1[4]) & i_op2[4]) |
        (eq_prefix[4] & (~i_op1[3]) & i_op2[3]) |
        (eq_prefix[3] & (~i_op1[2]) & i_op2[2]) |
        (eq_prefix[2] & (~i_op1[1]) & i_op2[1]) |
        (eq_prefix[1] & (~i_op1[0]) & i_op2[0]);


    // Signed comparison:
    //
    // If the signs differ:
    //     negative < positive
    //
    // If the signs are the same:
    //     unsigned comparison gives the correct result.

    wire signed_less;

    assign signed_less =
        (i_op1[31] & ~i_op2[31]) |
        (~(i_op1[31] ^ i_op2[31]) & unsigned_less);


    // ============================================================
    // 4. EQUALITY OUTPUT
    // ============================================================

    assign o_eq = ~(|(i_op1 ^ i_op2));


    // ============================================================
    // 5. BRANCH SET-LESS-THAN OUTPUT
    // ============================================================

    // i_unsigned controls branch comparison type.
    // This output is independent of i_opsel.

    assign o_slt = i_unsigned ?
                   unsigned_less :
                   signed_less;


    // ============================================================
    // 6. ALU RESULT MULTIPLEXER
    // ============================================================

    assign o_result =
        (i_opsel == 3'b000) ? cla_sum :
        (i_opsel == 3'b001) ? shift_left_result :
        (i_opsel == 3'b010) ? {31'b0, signed_less} :
        (i_opsel == 3'b011) ? {31'b0, unsigned_less} :
        (i_opsel == 3'b100) ? (i_op1 ^ i_op2) :
        (i_opsel == 3'b101) ? shift_right_result :
        (i_opsel == 3'b110) ? (i_op1 | i_op2) :
                               (i_op1 & i_op2);


endmodule

`default_nettype wire
