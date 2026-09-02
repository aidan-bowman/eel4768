import sys
import os

# Register mapping table supporting ABI and numeric names
REG_MAP = {
    "zero": 0, "ra": 1, "sp": 2, "gp": 3, "tp": 4,
    "t0": 5, "t1": 6, "t2": 7, "s0": 8, "fp": 8, "s1": 9,
    "a0": 10, "a1": 11, "a2": 12, "a3": 13, "a4": 14, "a5": 15,
    "a6": 16, "a7": 17, "s2": 18, "s3": 19, "s4": 20, "s5": 21,
    "s6": 22, "s7": 23, "s8": 24, "s9": 25, "s10": 26, "s11": 27,
    "t3": 28, "t4": 29, "t5": 30, "t6": 31
}
for i in range(32):
    REG_MAP[f"x{i}"] = i

def get_reg(reg_str):
    reg_str = reg_str.strip().lower()
    if reg_str in REG_MAP:
        return REG_MAP[reg_str]
    raise ValueError(f"Unknown register: {reg_str}")

def parse_imm(val_str, symbol_table=None, pc=None):
    val_str = val_str.strip()
    if symbol_table is not None and val_str in symbol_table:
        val = symbol_table[val_str]
        if pc is not None:
            return val - pc
        return val
    return int(val_str, 0)

def encode_r(opcode, funct3, funct7, rd, rs1, rs2):
    return ((funct7 & 0x7F) << 25) | ((rs2 & 0x1F) << 20) | ((rs1 & 0x1F) << 15) | \
           ((funct3 & 0x7) << 12) | ((rd & 0x1F) << 7) | (opcode & 0x7F)

def encode_i(opcode, funct3, rd, rs1, imm):
    imm &= 0xFFF
    return ((imm & 0xFFF) << 20) | ((rs1 & 0x1F) << 15) | \
           ((funct3 & 0x7) << 12) | ((rd & 0x1F) << 7) | (opcode & 0x7F)

def encode_s(opcode, funct3, rs1, rs2, imm):
    imm &= 0xFFF
    imm_11_5 = (imm >> 5) & 0x7F
    imm_4_0 = imm & 0x1F
    return (imm_11_5 << 25) | ((rs2 & 0x1F) << 20) | ((rs1 & 0x1F) << 15) | \
           ((funct3 & 0x7) << 12) | (imm_4_0 << 7) | (opcode & 0x7F)

def encode_b(opcode, funct3, rs1, rs2, imm):
    imm &= 0x1FFF
    imm_12 = (imm >> 12) & 0x1
    imm_10_5 = (imm >> 5) & 0x3F
    imm_4_1 = (imm >> 1) & 0xF
    imm_11 = (imm >> 11) & 0x1
    return (imm_12 << 31) | (imm_10_5 << 25) | ((rs2 & 0x1F) << 20) | \
           ((rs1 & 0x1F) << 15) | ((funct3 & 0x7) << 12) | \
           (imm_4_1 << 8) | (imm_11 << 7) | (opcode & 0x7F)

def encode_u(opcode, rd, imm):
    imm &= 0xFFFFF
    return (imm << 12) | ((rd & 0x1F) << 7) | (opcode & 0x7F)

def encode_j(opcode, rd, imm):
    imm &= 0x1FFFFF
    imm_20 = (imm >> 20) & 0x1
    imm_10_1 = (imm >> 1) & 0x3FF
    imm_11 = (imm >> 11) & 0x1
    imm_19_12 = (imm >> 12) & 0xFF
    return (imm_20 << 31) | (imm_10_1 << 21) | (imm_11 << 20) | \
           (imm_19_12 << 12) | ((rd & 0x1F) << 7) | (opcode & 0x7F)

def parse_mem_operand(op_str):
    # Parses format: offset(reg)
    op_str = op_str.strip()
    if '(' in op_str and op_str.endswith(')'):
        imm_part, reg_part = op_str[:-1].split('(')
        return imm_part.strip(), reg_part.strip()
    raise ValueError(f"Invalid memory operand format: {op_str}")

def assemble_instruction(line, pc, symbol_table):
    tokens = line.replace(',', ' ').split()
    instr = tokens[0].lower()
    args = tokens[1:]

    # Base RV32I Instruction Encodings
    if instr in ["add", "sub", "sll", "slt", "sltu", "xor", "srl", "sra", "or", "and"]:
        rd, rs1, rs2 = get_reg(args[0]), get_reg(args[1]), get_reg(args[2])
        f3_map = {"add":0, "sub":0, "sll":1, "slt":2, "sltu":3, "xor":4, "srl":5, "sra":5, "or":6, "and":7}
        f7 = 0x20 if instr in ["sub", "sra"] else 0x00
        return encode_r(0x33, f3_map[instr], f7, rd, rs1, rs2)

    elif instr in ["addi", "slti", "sltiu", "xori", "ori", "andi"]:
        rd, rs1 = get_reg(args[0]), get_reg(args[1])
        imm = parse_imm(args[2], symbol_table)
        f3_map = {"addi":0, "slti":2, "sltiu":3, "xori":4, "ori":6, "andi":7}
        return encode_i(0x13, f3_map[instr], rd, rs1, imm)

    elif instr in ["slli", "srli", "srai"]:
        rd, rs1 = get_reg(args[0]), get_reg(args[1])
        shamt = parse_imm(args[2], symbol_table) & 0x1F
        f3_map = {"slli":1, "srli":5, "srai":5}
        f7 = 0x20 if instr == "srai" else 0x00
        imm = (f7 << 5) | shamt
        return encode_i(0x13, f3_map[instr], rd, rs1, imm)

    elif instr in ["lb", "lh", "lw", "lbu", "lhu"]:
        rd = get_reg(args[0])
        imm_str, reg_str = parse_mem_operand(args[1])
        rs1 = get_reg(reg_str)
        imm = parse_imm(imm_str, symbol_table)
        f3_map = {"lb":0, "lh":1, "lw":2, "lbu":4, "lhu":5}
        return encode_i(0x03, f3_map[instr], rd, rs1, imm)

    elif instr == "jalr":
        rd = get_reg(args[0])
        if len(args) == 2 and '(' in args[1]:
            imm_str, reg_str = parse_mem_operand(args[1])
            rs1 = get_reg(reg_str)
            imm = parse_imm(imm_str, symbol_table)
        else:
            rs1 = get_reg(args[1])
            imm = parse_imm(args[2], symbol_table)
        return encode_i(0x67, 0, rd, rs1, imm)

    elif instr in ["sb", "sh", "sw"]:
        rs2 = get_reg(args[0])
        imm_str, reg_str = parse_mem_operand(args[1])
        rs1 = get_reg(reg_str)
        imm = parse_imm(imm_str, symbol_table)
        f3_map = {"sb":0, "sh":1, "sw":2}
        return encode_s(0x23, f3_map[instr], rs1, rs2, imm)

    elif instr in ["beq", "bne", "blt", "bge", "bltu", "bgeu"]:
        rs1, rs2 = get_reg(args[0]), get_reg(args[1])
        offset = parse_imm(args[2], symbol_table, pc)
        f3_map = {"beq":0, "bne":1, "blt":4, "bge":5, "bltu":6, "bgeu":7}
        return encode_b(0x63, f3_map[instr], rs1, rs2, offset)

    elif instr in ["lui", "auipc"]:
        rd = get_reg(args[0])
        imm = parse_imm(args[1], symbol_table)
        opcode = 0x37 if instr == "lui" else 0x17
        return encode_u(opcode, rd, imm)

    elif instr == "jal":
        if len(args) == 1:
            rd = 1 # Default to ra
            offset = parse_imm(args[0], symbol_table, pc)
        else:
            rd = get_reg(args[0])
            offset = parse_imm(args[1], symbol_table, pc)
        return encode_j(0x6F, rd, offset)

    elif instr == "ecall":
        return 0x00000073

    else:
        raise ValueError(f"Unsupported instruction: {instr}")

def word_to_little_endian_bytes(word):
    # Convert a 32-bit integer into 4 bytes in little-endian order
    return [(word >> (i * 8)) & 0xFF for i in range(4)]

def main():
    if len(sys.argv) != 2:
        print("Usage: python assembler.py <assembly_file>")
        sys.exit(1)

    assembly_file = sys.argv[1]

    with open(assembly_file, 'r') as f:
        lines = f.readlines()

    # Base addresses[cite: 1]
    TEXT_BASE = 0x00400000
    DATA_BASE = 0x10010000

    symbol_table = {}
    current_section = ".text"
    text_pc = TEXT_BASE
    data_pc = DATA_BASE

    parsed_lines = []

    # --- PASS 1: Calculate addresses & build symbol table[cite: 1] ---
    for raw_line in lines:
        # Strip comments
        line = raw_line.split('#')[0].strip()
        if not line:
            continue

        # Check section directives
        if line.startswith(".text"):
            current_section = ".text"
            continue
        elif line.startswith(".data"):
            current_section = ".data"
            continue

        # Handle labels
        if ':' in line:
            label, rest = line.split(':', 1)
            label = label.strip()
            if current_section == ".text":
                symbol_table[label] = text_pc
            else:
                symbol_table[label] = data_pc
            line = rest.strip()
            if not line:
                continue

        if current_section == ".text":
            parsed_lines.append(('text', text_pc, line))
            text_pc += 4
        elif current_section == ".data":
            parsed_lines.append(('data', data_pc, line))
            tokens = line.split()
            directive = tokens[0]
            if directive == ".word":
                values = ' '.join(tokens[1:]).split(',')
                data_pc += 4 * len(values)
            elif directive == ".byte":
                values = ' '.join(tokens[1:]).split(',')
                data_pc += len(values)
            elif directive == ".zero":
                num_bytes = int(tokens[1], 0)
                data_pc += num_bytes

    # --- PASS 2: Encode instructions & data into little-endian bytes[cite: 1] ---
    text_bytes = []
    data_bytes = []

    for section, pc, line in parsed_lines:
        if section == 'text':
            encoded_word = assemble_instruction(line, pc, symbol_table)
            text_bytes.extend(word_to_little_endian_bytes(encoded_word))
        elif section == 'data':
            tokens = line.split()
            directive = tokens[0]
            if directive == ".word":
                raw_vals = ' '.join(tokens[1:]).split(',')
                for v in raw_vals:
                    val = parse_imm(v, symbol_table)
                    text_val = val & 0xFFFFFFFF
                    data_bytes.extend(word_to_little_endian_bytes(text_val))
            elif directive == ".byte":
                raw_vals = ' '.join(tokens[1:]).split(',')
                for v in raw_vals:
                    val = parse_imm(v, symbol_table) & 0xFF
                    data_bytes.append(val)
            elif directive == ".zero":
                num_bytes = int(tokens[1], 0)
                data_bytes.extend([0] * num_bytes)

    # Output file generation
    base_name = os.path.splitext(assembly_file)[0]
    
    # 1. <name>.hex.txt
    with open(f"{base_name}.hex.txt", "w") as f:
        for b in text_bytes:
            f.write(f"0x{b:02X}\n")

    # 2. <name>.bin.txt
    with open(f"{base_name}.bin.txt", "w") as f:
        for b in text_bytes:
            f.write(f"{b:08b}\n")

    # 3. <name>_data.hex.txt
    with open(f"{base_name}_data.hex.txt", "w") as f:
        for b in data_bytes:
            f.write(f"0x{b:02X}\n")

    # 4. <name>_data.bin.txt
    with open(f"{base_name}_data.bin.txt", "w") as f:
        for b in data_bytes:
            f.write(f"{b:08b}\n")

if __name__ == "__main__":
    main()