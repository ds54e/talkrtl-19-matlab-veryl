module ldo_rnm #(
    parameter real VREF      = 0.45,
    parameter real RTOP      = 100.0e3,
    parameter real RBOT      = 100.0e3,
    parameter real COUT      = 10.0e-9,
    parameter real RL_NORMAL = 1.8e3,
    parameter real RL_HEAVY  = 300.0,
    parameter real A0        = 200.0,
    parameter real TAU_EA    = 0.5e-6,
    parameter real GM_PASS   = 4.0e-3,
    parameter real IMAX      = 5.0e-3,
    parameter real VC_MAX    = 1.0
) (
    input  logic en,
    input  logic load_hi,
    output real  vout,
    output real  vfb,
    output real  vctrl,
    output real  ipass,
    output logic pg_cmp
);
    timeunit 1ns;
    timeprecision 1ps;

    localparam real RDIV = RTOP + RBOT;
    // Each 10 ns step uses 100 explicit Euler substeps.
    localparam int FE_SUBSTEPS = 100;

    real vout_q;
    real vctrl_q;

    pg_cmp_rnm u_cmp (.v(vout), .q(pg_cmp));

    function automatic real clip(input real x, input real lo, input real hi);
        return x < lo ? lo : (x > hi ? hi : x);
    endfunction

    function automatic real pass_current(input real vc);
        return en ? clip(GM_PASS * vc, 0.0, IMAX) : 0.0;
    endfunction

    task automatic deriv(input real v, input real vc, output real dvout, output real dvctrl);
        real rload = load_hi ? RL_HEAVY : RL_NORMAL;
        // Saturation precedes the EA lag.
        real vc_target = clip(A0 * (en ? 1.0 : 0.0) * (VREF - v * (RBOT / RDIV)), 0.0, VC_MAX);
        dvctrl = (vc_target - vc) / TAU_EA;
        // Divider current is explicit here; Simscape gets it from the resistor network.
        dvout = (pass_current(vc) - v / rload - v / RDIV) / COUT;
    endtask

    task automatic drive_outputs();
        vout  = vout_q;
        vfb   = vout_q * (RBOT / RDIV);
        vctrl = vctrl_q;
        ipass = pass_current(vctrl_q);
    endtask

    // Both derivatives use the same pre-update state.
    task automatic step(input real h);
        real dt = h / FE_SUBSTEPS;
        real dv, dvc;
        for (int k = 0; k < FE_SUBSTEPS; k++) begin
            deriv(vout_q, vctrl_q, dv, dvc);
            vout_q  = vout_q  + dt * dv;
            vctrl_q = vctrl_q + dt * dvc;
        end
        drive_outputs();
    endtask

    // Analog state is cleared only on cold start; digital reset does not touch it.
    initial begin
        vout_q  = 0.0;
        vctrl_q = 0.0;
        drive_outputs();
    end

    always #10 step(10e-9);
endmodule
