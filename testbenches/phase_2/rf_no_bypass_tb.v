`timescale 1ns / 1ps
module rf_no_bypass_tb;
    rf_trace_tb #(
        .BYPASS_EN(0),
        .TRACE_FILE("../../course_files/phase_2/traces/rf_no_bypass.trace")
    ) test ();
endmodule
