/*
 * fpu_decoder.v
 *
 * Decodes RV32F operations and FCSR instructions for fpu.v.
 *
 * Functionality:
 *   - Produces a 24-bit one-hot operation select for all OP-FP and
 *     fused single-precision instructions required by Phase 6.
 *   - Produces a separate 6-bit one-hot select for FCSR instructions.
 *   - Exposes the instruction rounding-mode field and CSR address.
 *   - All operation outputs are gated by i_valid.
 *
 * Operation select (o_op):
 *    [0]  fadd.s
 *    [1]  fsub.s
 *    [2]  fmul.s
 *    [3]  fdiv.s
 *    [4]  fsqrt.s
 *    [5]  fmadd.s
 *    [6]  fmsub.s
 *    [7]  fnmsub.s
 *    [8]  fnmadd.s
 *    [9]  fsgnj.s
 *   [10]  fsgnjn.s
 *   [11]  fsgnjx.s
 *   [12]  fmin.s
 *   [13]  fmax.s
 *   [14]  feq.s
 *   [15]  flt.s
 *   [16]  fle.s
 *   [17]  fclass.s
 *   [18]  fcvt.w.s
 *   [19]  fcvt.wu.s
 *   [20]  fcvt.s.w
 *   [21]  fcvt.s.wu
 *   [22]  fmv.x.w
 *   [23]  fmv.w.x
 *
 * CSR operation select (o_csr_op):
 *    [0]  CSRRW
 *    [1]  CSRRS
 *    [2]  CSRRC
 *    [3]  CSRRWI
 *    [4]  CSRRSI
 *    [5]  CSRRCI
 *
 * Portlist:
 *   i_inst     [31:0] - Instruction being executed.
 *   i_valid           - High when the main decoder identifies a legal
 *                       FPU instruction.
 *   o_op       [23:0] - One-hot FPU operation select.
 *   o_csr_op    [5:0] - One-hot CSR operation select.
 *   o_rm        [2:0] - Rounding mode field (instruction bits [14:12]).
 *   o_csr_addr [11:0] - CSR address (instruction bits [31:20]).
 *
 * Limitations / integration notes:
 *   - flw and fsw are handled by the main decoder and memory datapath,
 *     not by this module.
 *   - The main decoder is responsible for instruction legality and
 *     must assert i_valid only for legal FPU instructions.
 *   - Static rounding modes 101 and 110 must be rejected by the main
 *     decoder. Dynamic rounding mode 111 is passed through unchanged.
 *   - The FPU must validate the dynamic rounding mode against frm.
 *   - CSR addresses are limited to fflags (001), frm (002), and
 *     fcsr (003).
 *   - This module generates operation selects only; it does not
 *     generate register-file enables or writeback controls.
 */

module fpu_decoder (
    input  wire [31:0] i_inst,
    input  wire        i_valid,

    output wire [23:0] o_op,
    output wire [ 5:0] o_csr_op,
    output wire [ 2:0] o_rm,
    output wire [11:0] o_csr_addr
);

    // Instruction fields
    wire [6:0] opcode;
    wire [6:0] funct7;
    wire [2:0] funct3;
    wire [4:0] rs2;
    wire [1:0] fmt;
    wire [11:0] csr;

    assign opcode = i_inst[6:0];
    assign funct7 = i_inst[31:25];
    assign funct3 = i_inst[14:12];
    assign rs2    = i_inst[24:20];
    assign fmt    = i_inst[26:25];
    assign csr    = i_inst[31:20];

    assign o_rm       = funct3;
    assign o_csr_addr = csr;

    // Instruction opcodes
    wire op_opfp;
    wire op_madd;
    wire op_msub;
    wire op_nmsub;
    wire op_nmadd;
    wire op_sys;

    assign op_opfp  = (opcode == 7'b1010011);
    assign op_madd  = (opcode == 7'b1000011);
    assign op_msub  = (opcode == 7'b1000111);
    assign op_nmsub = (opcode == 7'b1001011);
    assign op_nmadd = (opcode == 7'b1001111);
    assign op_sys   = (opcode == 7'b1110011);

    // Rounding modes 101 and 110 are reserved.
    // Dynamic mode 111 is valid here; the FPU checks frm.
    wire rm_valid;
    assign rm_valid = (funct3 != 3'b101) &&
                      (funct3 != 3'b110);

    // ------------------------------------------------------------
    // Arithmetic operations
    // ------------------------------------------------------------

    wire fp_add;
    wire fp_sub;
    wire fp_mul;
    wire fp_div;
    wire fp_sqrt;

    assign fp_add = op_opfp &&
                    (funct7 == 7'b0000000) &&
                    rm_valid;

    assign fp_sub = op_opfp &&
                    (funct7 == 7'b0000100) &&
                    rm_valid;

    assign fp_mul = op_opfp &&
                    (funct7 == 7'b0001000) &&
                    rm_valid;

    assign fp_div = op_opfp &&
                    (funct7 == 7'b0001100) &&
                    rm_valid;

    assign fp_sqrt = op_opfp &&
                     (funct7 == 7'b0101100) &&
                     (rs2 == 5'b00000) &&
                     rm_valid;

    // ------------------------------------------------------------
    // Fused multiply-add operations
    // R4 format requires fmt = 00 (single precision).
    // ------------------------------------------------------------

    wire fp_madd;
    wire fp_msub;
    wire fp_nmsub;
    wire fp_nmadd;

    assign fp_madd = op_madd && (fmt == 2'b00);
    assign fp_msub = op_msub && (fmt == 2'b00);
    assign fp_nmsub = op_nmsub && (fmt == 2'b00);
    assign fp_nmadd = op_nmadd && (fmt == 2'b00);

    // ------------------------------------------------------------
    // Sign injection
    // ------------------------------------------------------------

    wire fp_sgnj;
    wire fp_sgnjn;
    wire fp_sgnjx;

    assign fp_sgnj = op_opfp &&
                     (funct7 == 7'b0010000) &&
                     (funct3 == 3'b000);

    assign fp_sgnjn = op_opfp &&
                      (funct7 == 7'b0010000) &&
                      (funct3 == 3'b001);

    assign fp_sgnjx = op_opfp &&
                      (funct7 == 7'b0010000) &&
                      (funct3 == 3'b010);

    // ------------------------------------------------------------
    // Minimum and maximum
    // ------------------------------------------------------------

    wire fp_min;
    wire fp_max;

    assign fp_min = op_opfp &&
                    (funct7 == 7'b0010100) &&
                    (funct3 == 3'b000);

    assign fp_max = op_opfp &&
                    (funct7 == 7'b0010100) &&
                    (funct3 == 3'b001);

    // ------------------------------------------------------------
    // Comparisons
    // ------------------------------------------------------------

    wire fp_eq;
    wire fp_lt;
    wire fp_le;

    assign fp_eq = op_opfp &&
                   (funct7 == 7'b1010000) &&
                   (funct3 == 3'b010);

    assign fp_lt = op_opfp &&
                   (funct7 == 7'b1010000) &&
                   (funct3 == 3'b001);

    assign fp_le = op_opfp &&
                   (funct7 == 7'b1010000) &&
                   (funct3 == 3'b000);

    // ------------------------------------------------------------
    // Classification
    // ------------------------------------------------------------

    wire fp_class;

    assign fp_class = op_opfp &&
                      (funct7 == 7'b1110000) &&
                      (rs2 == 5'b00000) &&
                      (funct3 == 3'b001);

    // ------------------------------------------------------------
    // Conversions
    // ------------------------------------------------------------

    wire fp_to_int;
    wire fp_to_uint;
    wire int_to_fp;
    wire uint_to_fp;

    assign fp_to_int = op_opfp &&
                       (funct7 == 7'b1100000) &&
                       (rs2 == 5'b00000) &&
                       rm_valid;

    assign fp_to_uint = op_opfp &&
                        (funct7 == 7'b1100000) &&
                        (rs2 == 5'b00001) &&
                        rm_valid;

    assign int_to_fp = op_opfp &&
                       (funct7 == 7'b1101000) &&
                       (rs2 == 5'b00000) &&
                       rm_valid;

    assign uint_to_fp = op_opfp &&
                        (funct7 == 7'b1101000) &&
                        (rs2 == 5'b00001) &&
                        rm_valid;

    // ------------------------------------------------------------
    // Bitwise moves
    // ------------------------------------------------------------

    wire fp_move_x;
    wire fp_move_w;

    assign fp_move_x = op_opfp &&
                       (funct7 == 7'b1110000) &&
                       (rs2 == 5'b00000) &&
                       (funct3 == 3'b000);

    assign fp_move_w = op_opfp &&
                       (funct7 == 7'b1111000) &&
                       (rs2 == 5'b00000) &&
                       (funct3 == 3'b000);

    // ------------------------------------------------------------
    // One-hot FPU operation output
    // ------------------------------------------------------------

    assign o_op[0]  = i_valid && fp_add;
    assign o_op[1]  = i_valid && fp_sub;
    assign o_op[2]  = i_valid && fp_mul;
    assign o_op[3]  = i_valid && fp_div;
    assign o_op[4]  = i_valid && fp_sqrt;

    assign o_op[5]  = i_valid && fp_madd;
    assign o_op[6]  = i_valid && fp_msub;
    assign o_op[7]  = i_valid && fp_nmsub;
    assign o_op[8]  = i_valid && fp_nmadd;

    assign o_op[9]  = i_valid && fp_sgnj;
    assign o_op[10] = i_valid && fp_sgnjn;
    assign o_op[11] = i_valid && fp_sgnjx;

    assign o_op[12] = i_valid && fp_min;
    assign o_op[13] = i_valid && fp_max;

    assign o_op[14] = i_valid && fp_eq;
    assign o_op[15] = i_valid && fp_lt;
    assign o_op[16] = i_valid && fp_le;

    assign o_op[17] = i_valid && fp_class;

    assign o_op[18] = i_valid && fp_to_int;
    assign o_op[19] = i_valid && fp_to_uint;
    assign o_op[20] = i_valid && int_to_fp;
    assign o_op[21] = i_valid && uint_to_fp;

    assign o_op[22] = i_valid && fp_move_x;
    assign o_op[23] = i_valid && fp_move_w;

    // ------------------------------------------------------------
    // CSR instructions
    // ------------------------------------------------------------

    wire csr_addr_valid;
    wire csr_inst;

    assign csr_addr_valid = (csr == 12'h001) ||
                            (csr == 12'h002) ||
                            (csr == 12'h003);

    assign csr_inst = i_valid && op_sys && csr_addr_valid;

    assign o_csr_op[0] = csr_inst && (funct3 == 3'b001); // CSRRW
    assign o_csr_op[1] = csr_inst && (funct3 == 3'b010); // CSRRS
    assign o_csr_op[2] = csr_inst && (funct3 == 3'b011); // CSRRC
    assign o_csr_op[3] = csr_inst && (funct3 == 3'b101); // CSRRWI
    assign o_csr_op[4] = csr_inst && (funct3 == 3'b110); // CSRRSI
    assign o_csr_op[5] = csr_inst && (funct3 == 3'b111); // CSRRCI

endmodule
