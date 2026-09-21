// pg_cmp_rnm -- hysteretic supply comparator for the SV-RNM LDO.
//
// CONTRACT.md §3: voltage hysteresis only, strict crossing at both
// thresholds, initial state 0.
//
//   pg_cmp == 0 && vout > V_HI : -> 1
//   pg_cmp == 1 && vout < V_LO : -> 0
//   otherwise (including vout exactly at a threshold) : hold
//
// The thresholds are strict, so `vout == 0.87` and `vout == 0.85` do NOT switch.
// `en` is deliberately absent from this module: the contract forbids forcing
// pg_cmp to 0 when the LDO is disabled, so after disable the comparator keeps
// following the residual vout.
//
// The comparator holds state and is advanced by an explicit `update()` call, so
// it can be unit tested directly: the documented staircase
// 0.86/0.87/0.88/0.87/0.86/0.85/0.84 gives 0/0/1/1/1/1/0.
//
// This model only transitions pg_cmp. It never produces `pgood`; that is the
// supervisor's job (CONTRACT §3).
module pg_cmp_rnm #(
    parameter real V_HI = 0.87,
    parameter real V_LO = 0.85
) (
    output logic q
);
    timeunit 1ns;
    timeprecision 1ps;

    // Pure next-state function: no state is read or written here.
    function automatic logic next_q(input logic q_cur, input real v);
        if (!q_cur && v > V_HI) begin
            return 1'b1;
        end else if (q_cur && v < V_LO) begin
            return 1'b0;
        end else begin
            return q_cur;
        end
    endfunction

    task automatic rst();
        q = 1'b0;
    endtask

    task automatic update(input real v);
        q = next_q(q, v);
    endtask

    initial q = 1'b0;
endmodule
