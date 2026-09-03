.data
a: .word 22
b: .word 59
c: .word 0

.text
.global _main

main:
    lui t0, zero, 0x10010   # data segment address

    lw   t1, 0(t0)      # t1 = A (multiplicand, will be shifted left)
    lw   t2, 4(t0)      # t2 = B (multiplier, will be shifted right)

    li   t3, 0           # t3 = result accumulator, C = 0

mul_loop:
    beq  t2, x0, mul_done   # if B == 0, done

    andi t4, t2, 1           # t4 = B & 1 (check lowest bit)
    beq  t4, x0, skip_add    # if bit is 0, skip the add

    add  t3, t3, t1          # C += A

skip_add:
    slli t1, t1, 1            # A <<= 1
    srli t2, t2, 1            # B >>= 1 (logical shift, B treated as unsigned)

    j    mul_loop

mul_done:
    sw   t3, 8(t0)          # store result into c

done:
    # terminate execution (matching example convention)
    addi a0, x0, 0          # return value = 0
    addi a7, x0, 93         # sys_exit
    ecall
