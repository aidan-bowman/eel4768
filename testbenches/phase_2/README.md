# Phase 2 trace-driven test benches

These test benches use the **actual Phase 2 trace files from the repository**:

- `course_files/phase_2/traces/alu.trace`
- `course_files/phase_2/traces/imm.trace`
- `course_files/phase_2/traces/rf_bypass.trace`
- `course_files/phase_2/traces/rf_no_bypass.trace`
- `course_files/phase_2/traces/decoder.trace`

The test benches do not invent their own expected values. They read each trace row and compare the DUT outputs against the expected outputs in that row.

The trace files are deliberately kept outside the testbench directory; this lets you test the exact course traces that are already in the repository.

## Recommended location

Put these `.v` files in:

`submissions/phase_2/`

Then run the commands below from that directory.

## Commands

```bash
iverilog -g2012 -s alu_tb -o alu_sim alu_tb.v alu.v
./alu_sim

iverilog -g2012 -s imm_tb -o imm_sim imm_tb.v imm.v
./imm_sim

iverilog -g2012 -s rf_no_bypass_tb -o rf_no_bypass_sim rf_trace_tb.v rf_no_bypass_tb.v rf.v
./rf_no_bypass_sim

iverilog -g2012 -s rf_bypass_tb -o rf_bypass_sim rf_trace_tb.v rf_bypass_tb.v rf.v
./rf_bypass_sim

iverilog -g2012 -s decoder_tb -o decoder_sim decoder_tb.v decoder.v imm.v
./decoder_sim
```

## RF timing

The RF traces describe asynchronous read outputs and a synchronous write/reset port. Each trace row is checked before the clock edge, then the testbench advances one clock edge so that the row's write/reset can affect the following row. This is important for correctly testing the difference between `BYPASS_EN=0` and `BYPASS_EN=1`.

## Decoder don't-cares

`decoder.trace` uses `x` for outputs that are intentionally don't-care for a particular instruction. The decoder testbench ignores those fields rather than incorrectly requiring a particular value.

## VCDs

Each testbench generates a VCD waveform:

- `alu_trace_tb.vcd`
- `imm_trace_tb.vcd`
- `rf_no_bypass_trace_tb.vcd`
- `rf_bypass_trace_tb.vcd`
- `decoder_trace_tb.vcd`

Open them with:

```bash
gtkwave <waveform>.vcd
```
