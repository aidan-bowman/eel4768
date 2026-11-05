module fpu_decoder (
                    input wire [31:0] i_inst,
                    input wire        i_valid,
                    output wire       o_rm_trap,
                    );

    // OPCODE to one-hot of op
    wire op_op;
    wire op_loadfp;
    wire op_storefp;
    wire op_opfp;
    wire op_madd;
    wire op_msub;
    wire op_nmsub;
    wire op_nmadd;
    wire op_sys;

    assign op_op      = (i_inst[6:0] == 7'b0110011); // R
    assign op_loadfp  = (i_inst[6:0] == 7'b0000111); // I
    assign op_storefp = (i_inst[6:0] == 7'b0100111); // S
    assign op_opfp    = (i_inst[6:0] == 7'b1010011); // R
    assign op_madd    = (i_inst[6:0] == 7'b1000011); // R4
    assign op_msub    = (i_inst[6:0] == 7'b1000111); // R4
    assign op_nmsub   = (i_inst[6:0] == 7'b1001011); // R4
    assign op_nmadd   = (i_inst[6:0] == 7'b1001111); // R4
    assign op_sys     = (i_inst[6:0] == 7'b1110011); // R

    // one-hot encoding
    // 1 - R
    // 2 - R4
    // 3 - I (load)
    // 4 - S (store)
    wire [3:0] format;
    assign format = (op_op | op_opfp | op_sys) ? 4'b0001 :
                    (op_madd | op_msub | op_nmsub | op_nmadd) ? 4'b0010 :
                    (op_loadfp) ? 4'b0100 :
                    (op_storefp) ? 4'b1000 :
                    4b'0000; // assumed impossible i.e. all instrs are valid

    
endmodule // fpu_decoder