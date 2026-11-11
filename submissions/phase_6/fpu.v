`default_nettype none

// Single-precision FPU control and the operations that do not require the
// unfinished arithmetic datapaths. Arithmetic and conversion operations are
// deliberately selected as zero here until their datapaths are integrated.
module fpu (
    input wire i_clk,
    input wire i_rst,
    input wire [31:0] i_inst,
    input wire i_valid,
    input wire i_advance,
    input wire [31:0] i_frs1,
    input wire [31:0] i_frs2,
    input wire [31:0] i_frs3,
    input wire [31:0] i_xrs1,
    output wire [31:0] o_fp_result,
    output wire [31:0] o_int_result,
    output wire [4:0] o_fflags,
    output wire o_busy,
    output wire o_rm_trap
);
    reg [7:0] fcsr;
    wire [23:0] op;
    wire [5:0] csr_op;
    wire [2:0] rm;
    wire [11:0] csr_addr;
    wire [9:0] rs1_mask;
    wire [9:0] rs2_mask;
    wire [9:0] rs3_mask;

    fpu_decoder decoder (
        .i_inst(i_inst), .i_valid(i_valid), .o_op(op),
        .o_csr_op(csr_op), .o_rm(rm), .o_csr_addr(csr_addr)
    );
    classify classify_rs1 (.i_fp(i_frs1), .o_mask(rs1_mask));
    classify classify_rs2 (.i_fp(i_frs2), .o_mask(rs2_mask));
    classify classify_rs3 (.i_fp(i_frs3), .o_mask(rs3_mask));

    wire rounding_op = op[0] | op[1] | op[2] | op[3] | op[4] |
                       op[5] | op[6] | op[7] | op[8] |
                       op[18] | op[19] | op[20] | op[21];
    wire [2:0] effective_rm = (rm == 3'b111) ? fcsr[7:5] : rm;
    assign o_rm_trap = i_valid && rounding_op && (rm == 3'b111) &&
                       (fcsr[7:5] >= 3'b101);
    assign o_busy = 1'b0;

    wire [31:0] csr_old = (csr_addr == 12'h001) ? {27'b0, fcsr[4:0]} :
                          (csr_addr == 12'h002) ? {29'b0, fcsr[7:5]} :
                          {24'b0, fcsr};
    wire csr_write = |csr_op;
    wire csr_imm = csr_op[3] | csr_op[4] | csr_op[5];
    wire [31:0] csr_source = csr_imm ? {27'b0, i_inst[19:15]} : i_xrs1;
    wire [31:0] csr_new = (csr_op[0] | csr_op[3]) ? csr_source :
                          (csr_op[1] | csr_op[4]) ? (csr_old | csr_source) :
                          (csr_old & ~csr_source);

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
            end else if (op[14] | op[15] | op[16] | op[12] | op[13]) begin
                fcsr[4] <= fcsr[4] |
                           ((op[14] | op[15] | op[16]) && cmp_nv) |
                           ((op[12] | op[13]) && (rs1_mask[8] | rs2_mask[8]));
            end
        end
    end

    wire cmp_result;
    wire cmp_nv;
    compare compare_unit (
        .i_rm(rm), .i_rs1(i_frs1), .i_rs1_mask(rs1_mask),
        .i_rs2(i_frs2), .i_rs2_mask(rs2_mask),
        .o_out(cmp_result), .o_nv(cmp_nv)
    );

    wire rs1_nan = rs1_mask[9] | rs1_mask[8];
    wire rs2_nan = rs2_mask[9] | rs2_mask[8];
    wire rs1_zero = rs1_mask[4] | rs1_mask[3];
    wire rs2_zero = rs2_mask[4] | rs2_mask[3];
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

    assign o_fp_result = op[9]  ? {i_frs1[31], i_frs2[30:0]} :
                         op[10] ? {~i_frs1[31], i_frs2[30:0]} :
                         op[11] ? {i_frs1[31] ^ i_frs2[31], i_frs2[30:0]} :
                         (op[12] | op[13]) ? minmax_result :
                         op[23] ? i_xrs1 : 32'b0;

    assign o_int_result = op[14] | op[15] | op[16] ? {31'b0, cmp_result} :
                          op[17] ? {22'b0, rs1_mask} :
                          op[22] ? i_frs1 :
                          csr_write ? csr_old : 32'b0;

    assign o_fflags = fcsr[4:0] |
                      ((op[14] | op[15] | op[16]) ? {4'b0, cmp_nv} : 5'b0) |
                      ((op[12] | op[13]) && (rs1_mask[8] | rs2_mask[8]) ?
                       5'b10000 : 5'b0);

    // Keep the effective rounding mode visible to tools and future datapaths.
    wire unused_rm = ^effective_rm ^ ^i_frs3 ^ ^rs3_mask;
endmodule

`default_nettype wire
