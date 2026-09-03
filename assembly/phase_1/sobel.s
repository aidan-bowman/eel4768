.data
a:      .word 10, 9, 9, 4, 0
        .word 0, 6, 6, 2, 2
        .word 5, 9, 8, 4, 3
        .word 7, 5, 5, 4, 3
        .word 8, 10, 8, 5, 0
gx:     .word -1, 0, 1
        .word -2, 0, 2
        .word -1, 0, 1
gy:     .word 1, 2, 1
        .word 0, 0, 0
        .word -1, -2, -1
c:      .word 0, 0, 0
        .word 0, 0, 0
        .word 0, 0, 0

.text
.globl main

main:
    # TODO: SOBEL CODE GOES HERE

    # TODO: REWRITE AS FUNCTION
    # TODO: MAKE THIS WORK WITH 3x3 MATRICES
gemm:    
    addi sp, sp, -24
    sw ra, 20(sp)
    sw fp, 16(sp)
    sw s1, 12(sp)
    sw s2, 8(sp)
    sw s3, 4(sp)
    sw s4, 0(sp)
    addi fp, sp, 20         # unsure this is the right number

    # using s1, s2, s3, s4, a0, a1, t2
    # since we exit via syscall, we don't have to worry about
    # pushing saved registers on the stack! yippee
    
    addi s1, zero, 0        # index i for C (increments by 16 since we know matrices are 4x4)
    addi s2, zero, 0        # index j for C (increments by 4 since we're 32bit)
    lui  s4, 0x10010        # Load data segment address

    # a0 used for desired address of A, then value from A
    # a1 used for desired address of B, then value from B

    # s3 used for sum we're storing in C
    # t2 used for temporary values here and there

gemm_loop:   
    # since we know k goes from 0-3, lets just hardcode all 4 values
    
    # k = 0
    add a0, s4, s1          # address = A_i0
    lw   a0, 0(a0)          # load A_ik
    
    addi a1, s4, 64         # address = B_00
    add a1, a1, s2          # address = B_0j
    lw   a1, 0(a1)          # load B_kj

    jal mult
    addi s3, a0, 0

    # k = 1
    add a0, s4, s1          # address = A_i0
    lw   a0, 4(a0)          # load A_ik
    
    addi a1, s4, 64         # address = B_00
    add a1, a1, s2          # address = B_0j
    lw   a1, 16(a1)          # load B_kj

    jal mult
    add s3, s3, a0

    # k = 2
    add a0, s4, s1          # address = A_i0
    lw   a0, 8(a0)          # load A_ik
    
    addi a1, s4, 64         # address = B_00
    add a1, a1, s2          # address = B_0j
    lw   a1, 32(a1)          # load B_kj

    jal mult
    add s3, s3, a0

    # k = 3
    add a0, s4, s1          # address = A_i0
    lw   a0, 12(a0)          # load A_ik
    
    addi a1, s4, 64         # address = B_00
    add a1, a1, s2          # address = B_0j
    lw   a1, 48(a1)         # load B_kj

    jal mult
    add s3, s3, a0

    # store sum into C_ij
    add  t2, s4, s1         # address = i  (not C_ij!!)
    add  t2, t2, s2         # address = ij (not C_ij!!)
    sw   s3, 128(t2)        # store C_ij


gemm_loopreturn:
    # remember, s1 is i, s2 is j
    addi s2, s2, 4          # j += 4

    # if (j == 16) { j = 0, i += 16 }
    addi t2, zero, 16       # 4 steps * 4 bitwidth
    bne s2, t2, gemm_checki
    addi s2, zero, 0
    addi s1, s1, 16
    
gemm_checki:
    # if (i != 64) { goto loop }
    addi t2, zero, 64       # 4 steps * 4 columns * 4 bitwidth
    bne s1, t2, gemm_loop

gemm_done:
    # popping ra, fp, s1, s2, s3, s4
    lw ra, 20(sp)
    lw fp, 16(sp)
    lw s1, 12(sp)
    lw s2, 8(sp)
    lw s3, 4(sp)
    lw s4, 0(sp)
    addi sp, sp, 24
    # ret

    # syscall return
    addi a0, x0, 0          # return value = 0
    addi a7, x0, 93         # sys_exit
    ecall


    

# multiply a0 and a1 and put it in a0
mult:
    addi   t3, a0, 0    # t3 = A (multiplicand, will be shifted left)
    addi   t4, a1, 0    # t4 = B (multiplier, will be shifted right)

    addi   t5, zero, 0  # t5 = result accumulator, C = 0

mult_loop:
    beq  t4, x0, mult_done   # if B == 0, done

    andi t6, t4, 1           # t6 = B & 1 (check lowest bit)
    beq  t6, x0, mult_skipadd    # if bit is 0, skip the add

    add  t5, t5, t3          # C += A

mult_skipadd:
    slli t3, t3, 1           # A <<= 1
    srli t4, t4, 1           # B >>= 1 (logical shift, B treated as unsigned)

    j    mult_loop

mult_done:
    addi  a0, t5, 0     # store result
    ret
