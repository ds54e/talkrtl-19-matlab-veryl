module pg_cmp #(
    parameter real V_HI = 0.87,
    parameter real V_LO = 0.85
) (
    input  real  v,
    output logic q
);
    timeunit 1ns;
    timeprecision 1ps;

    // Hysteresis: rise above V_HI, fall below V_LO, otherwise hold (also at equality).
    initial q = 1'b0;
    always @(v) begin
        if (!q && v > V_HI) q = 1'b1;
        else if (q && v < V_LO) q = 1'b0;
    end
endmodule
