.data
a: .word 34
b: .word 27
c: .word 0

.text
.global _main

main:
    la   t0, a          # address of a
    la   t1, b          # address of b
    la   t2, c          # address of c

    lw   t3, 0(t0)      # t3 = A (multiplicand, will be shifted left)
    lw   t4, 0(t1)      # t4 = B (multiplier, will be shifted right)

    li   t5, 0           # t5 = result accumulator, C = 0

mul_loop:
    beq  t4, x0, mul_done   # if B == 0, done

    andi t6, t4, 1           # t6 = B & 1 (check lowest bit)
    beq  t6, x0, skip_add    # if bit is 0, skip the add

    add  t5, t5, t3          # C += A

skip_add:
    slli t3, t3, 1            # A <<= 1
    srli t4, t4, 1            # B >>= 1 (logical shift, B treated as unsigned)

    j    mul_loop

mul_done:
    sw   t5, 0(t2)      # store result into c

done:
    # terminate execution (matching example convention)
    li   a7, 10
    ecall