    ########################3
    # Generic Matrix Multiplication
    # multiply 4x4 matrices A and B into matrix C
    # written by AJ
    #
    # C_ij = sum from k=0 to 3 of A_ik * B_kj 

    
.data
a:  .word 1, 2, 5, 7
    .word 3, 9, 2, 5
    .word 1, 9, 8, 2
    .word 4, 1, 6, 6
b:  .word 3, 4, 9, 2
    .word 1, 8, 7, 3
    .word 8, 9, 1, 2
    .word 6, 3, 7, 5
c:  .word 0, 0, 0, 0
    .word 0, 0, 0, 0
    .word 0, 0, 0, 0
    .word 0, 0, 0, 0

.text
.globl main

main:
    lui  t0, 0x10010        # Load data segment address

    # using s1, s2, s3, t0, t1, t2
    # since we exit via syscall, we don't have to worry about
    # pushing saved registers on the stack! yippee
    
    lui  s1, 0              # index i for C (increments by 4 since we know matrices are 4x4)
    lui  s2, 0              # index j for C

    # t0 used for desired address of B, then value from B
    # t1 used for desired address of B, then value from B

    # s3 used for sum we're storing in C
    # t2 used for temporary values here and there

L_loop:   
    # since we know k goes from 0-3, lets just hardcode all 4 values
    
    # k = 0
    addi t0, t0, 0          # address = A_00
    addi t0, s1, 0          # address = A_i0
    lw   t0, 0(t0)          # load A_ik
    
    addi t1, t0, 64         # address = B_00
    addi t1, s2, 0          # address = B_0j
    lw   t1, 0(t1)          # load B_kj

    ### TODO: mult t0 and t1, s3 = t0 + t1

    # k = 1
    addi t0, t0, 0          # address = A_00
    addi t0, s1, 0          # address = A_i0
    lw   t0, 1(t0)          # load A_ik
    
    addi t1, t0, 64         # address = B_00
    addi t1, s2, 0          # address = B_0j
    lw   t1, 4(t1)          # load B_kj

    ### TODO: mult t0 and t1, s3 = t0 + t1 + s3

    # k = 2
    addi t0, t0, 0          # address = A_00
    addi t0, s1, 0          # address = A_i0
    lw   t0, 2(t0)          # load A_ik
    
    addi t1, t0, 64         # address = B_00
    addi t1, s2, 0          # address = B_0j
    lw   t1, 8(t1)          # load B_kj

    ### TODO: mult t0 and t1, s3 = t0 + t1 + s3

    # k = 3
    addi t0, t0, 0          # address = A_00
    addi t0, s1, 0          # address = A_i0
    lw   t0, 3(t0)          # load A_ik
    
    addi t1, t0, 64         # address = B_00
    addi t1, s2, 0          # address = B_0j
    lw   t1, 12(t1)         # load B_kj

    ### TODO: mult t0 and t1, s3 = t0 + t1 + s3

    # store sum into C_ij
    add  t2, s1, s2         # address = ij (not C_ij!!)
    sw   s3, 128(t2)        # store C_ij


L_loopreturn:
    # remember, s1 is i, s2 is j
    addi s2, s2, 1          # j++
    addi t2, zero, 4        $ 4 is our comparator for both checks

    # if (j == 4) { j = 0, i++ }
    bne s2, t2, L_checki
    addi s2, zero, 0
    addi s1, s1 1
    
L_checki:
    # if (i != 4) { goto loop }
    bne s1, t2, L_loop

done:
    addi a0, x0, 0          # return value = 0
    addi a7, x0, 93         # sys_exit
    ecall
