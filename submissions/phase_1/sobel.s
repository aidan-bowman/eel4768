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
    addi sp, sp, -24
    sw ra, 20(sp)
    sw fp, 16(sp)
    sw s1, 12(sp)
    sw s2, 8(sp)
    sw s3, 4(sp)
    sw s4, 0(sp)
    addi fp, sp, 20

    lui  s1, 0x10010        # load data address
    addi s2, zero, 0        # top left for A (funky increment)
    addi s3, zero, 0        # index for C
    # using s4 for sum we're putting in C
    
    
main_loop:
    addi s4, zero, 0        # zero out sum
    
    # 9 spaces to compare (annoying for A)
    # Gx, Gy:   0 4 8, 12 16 20, 24 28 32
    # A:        0 4 8, 20 24 28, 40 44 48
    # add 100 to Gx to get to right spot
    # add 136 to Gy
    
    # box 1
    add  a1, s1, s2         # A + topleft
    lw   a1, 0(a1)          # load to box 1 (see pattern above)

    lw   a0, 100(s1)        # load Gx (see pattern above)

    jal  mult
    add  s4, s4, a0         # add prod into s4

    lw   a0, 136(s1)       # load Gy

    jal  mult
    add  s4, s4, a0         # add prod into s4 again


    # box 2
    add  a1, s1, s2
    lw   a1, 4(a1)

    lw   a0, 104(s1)

    jal  mult
    add  s4, s4, a0

    lw   a0, 140(s1)

    jal  mult
    add  s4, s4, a0

    
    # box 3
    add  a1, s1, s2
    lw   a1, 8(a1)
    lw   a0, 108(s1)
    jal  mult
    add  s4, s4, a0
    lw   a0, 144(s1)
    jal  mult
    add  s4, s4, a0

    
    # box 4
    add  a1, s1, s2
    lw   a1, 20(a1)
    lw   a0, 112(s1)
    jal  mult
    add  s4, s4, a0
    lw   a0, 148(s1)
    jal  mult
    add  s4, s4, a0

    
    # box 5
    add  a1, s1, s2
    lw   a1, 24(a1)
    lw   a0, 116(s1)
    jal  mult
    add  s4, s4, a0
    lw   a0, 152(s1)
    jal  mult
    add  s4, s4, a0

    
    # box 6
    add  a1, s1, s2
    lw   a1, 28(a1)
    lw   a0, 120(s1)
    jal  mult
    add  s4, s4, a0
    lw   a0, 156(s1)
    jal  mult
    add  s4, s4, a0

    
    # box 7
    add  a1, s1, s2
    lw   a1, 40(a1)
    lw   a0, 124(s1)
    jal  mult
    add  s4, s4, a0
    lw   a0, 160(s1)
    jal  mult
    add  s4, s4, a0

    
    # box 8
    add  a1, s1, s2
    lw   a1, 44(a1)
    lw   a0, 128(s1)
    jal  mult
    add  s4, s4, a0
    lw   a0, 164(s1)
    jal  mult
    add  s4, s4, a0

    
    # box 9
    add  a1, s1, s2
    lw   a1, 48(a1)
    lw   a0, 132(s1)
    jal  mult
    add  s4, s4, a0
    lw   a0, 168(s1)
    jal  mult
    add  s4, s4, a0




    # get the right address
    add  t0, s1, s3
    sw   s4, 172(t0)
    
    # s3 += 4
    # if ((s3 == 12) || (s3 == 24))
    #   s2 += 12
    # else
    #   s2 += 4
    # goto main_loop if s3 != 36
    
    addi s3, s3, 4
    addi t1, zero, 36       # used later

    # if ((s3 == 12) || (s3 == 24))
    addi t0, zero, 12
    beq  s3, t0, main_add12
    addi t0, zero, 24
    beq  s3, t0, main_add12

    # else add 4
    addi s2, s2, 4
    bne s3, t1, main_loop
    
    beq zero, zero, main_done
main_add12:
    # add 12
    addi s2, s2, 12
    bne s3, t1, main_loop   # i guess this would always be true, but whatever
    

    
    
main_done:
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
    # a1 is untouched! yippee!!! we exploit this to save a cycle per cell operation
mult:
    addi   t3, a0, 0    # t3 = A (multiplicand, will be shifted left)
    addi   t4, a1, 0    # t4 = B (multiplier, will be shifted right)

    addi   t0, zero, -1 # needed for check later

    addi   t5, zero, 0  # t5 = result accumulator, C = 0

mult_loop:
    beq  t4, x0, mult_done   # if B == 0, done

    andi t6, t4, 1           # t6 = B & 1 (check lowest bit)
    beq  t6, x0, mult_skipadd    # if bit is 0, skip the add

    add  t5, t5, t3          # C += A

mult_skipadd:
    slli t3, t3, 1           # A <<= 1
    srli t4, t4, 1           # B >>= 1

    j    mult_loop

mult_done:
    addi  a0, t5, 0     # store result
    ret
