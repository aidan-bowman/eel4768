// The immediate generator is responsible for decoding the 32-bit
// sign-extended immediate from the incoming instruction word. It is a purely
// combinational block that is expected to be embedded in the instruction
// decoder.
module imm (
    // Input instruction word. This is used to extract the relevant immediate
    // bits and assemble them into the final immediate.
    input  wire [31:0] i_inst,
    // Instruction format, determined by the instruction decoder based on the
    // opcode. This is one-hot encoded according to the following format:
    // [0] R-type
    // [1] I-type
    // [2] S-type
    // [3] B-type
    // [4] U-type
    // [5] J-type
    // Because the R-type format does not have an immediate, the output
    // immediate can be treated as a don't-care under this case.
    input  wire [ 5:0] i_format,
    // Output 32-bit immediate, sign-extended from the immediate bitstring.
    output reg  [31:0] o_immediate
);

    // Extract raw bit-fields according to RISC-V RV32I specification
    wire [31:0] imm_i = {{20{i_inst[31]}}, i_inst[31:20]};
    wire [31:0] imm_s = {{20{i_inst[31]}}, i_inst[31:25], i_inst[11:7]};
    wire [31:0] imm_b = {{20{i_inst[31]}}, i_inst[7], i_inst[30:25], i_inst[11:8], 1'b0};
    wire [31:0] imm_u = {i_inst[31:12], 12'b0};
    wire [31:0] imm_j = {{12{i_inst[31]}}, i_inst[19:12], i_inst[20], i_inst[30:21], 1'b0};

    // Combinational logic using case statement based on one-hot format encoding
    always @(*) begin
        case (i_format)
            6'b000010: o_immediate = imm_i; // I-type [1]
            6'b000100: o_immediate = imm_s; // S-type [2]
            6'b001000: o_immediate = imm_b; // B-type [3]
            6'b010000: o_immediate = imm_u; // U-type [4]
            6'b100000: o_immediate = imm_j; // J-type [5]
            default:   o_immediate = 32'b0; // R-type [0] or illegal format default
        endcase
    end

endmodule
