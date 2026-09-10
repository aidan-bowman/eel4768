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
