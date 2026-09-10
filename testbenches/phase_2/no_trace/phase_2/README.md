# EEL4768 Phase 2 Test Benches

These are self-checking Verilog test benches for the four Phase 2 modules:

- `alu_tb.v` -> `alu.v`
- `imm_tb.v` -> `imm.v`
- `rf_tb.v` -> `rf.v`
- `decoder_tb.v` -> `decoder.v`

They follow the structure of the Phase 2 example test bench: directed tests, pass/fail counts, and VCD waveform output.

## Icarus commands

From the directory containing the Phase 2 RTL and these test benches:

```bash
iverilog -g2012 -s alu_tb -o alu_sim alu_tb.v alu.v
vvp alu_sim

iverilog -g2012 -s imm_tb -o imm_sim imm_tb.v imm.v
vvp imm_sim

iverilog -g2012 -s rf_tb -o rf_sim rf_tb.v rf.v
vvp rf_sim

iverilog -g2012 -s decoder_tb -o decoder_sim decoder_tb.v decoder.v imm.v
vvp decoder_sim
```

Each test bench also produces a `.vcd` waveform that can be opened with GTKWave.

## Important

The current `submissions/phase_2/decoder.v` in the linked repository has several RTL issues that prevent the decoder test bench from compiling/running cleanly. The test bench intentionally uses the documented port names and expected behavior so it can expose those issues after the decoder is corrected.

Notably, the current decoder source contains undeclared `rd`, `rs1`, and `rs2` assignments, uses an assignment inside the `o_halt` expression, has `o_branch_inver` instead of `o_branch_invert`, and drives the 4-bit `o_rd_sel` with 2-bit values.
