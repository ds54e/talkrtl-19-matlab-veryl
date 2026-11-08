module pg_cmp_rnm #(
    parameter real V_HI = 0.87,
    parameter real V_LO = 0.85
) (
    input  real  v,
    output logic q
);
    timeunit 1ns;
    timeprecision 1ps;

    function automatic logic next_q(input logic q_cur, input real v);
        if (!q_cur && v > V_HI) begin
            return 1'b1;
        end else if (q_cur && v < V_LO) begin
            return 1'b0;
        end else begin
            return q_cur;
        end
    endfunction

    initial q = 1'b0;
    always @(v) q = next_q(q, v);
endmodule
