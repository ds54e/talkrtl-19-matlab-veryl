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
    // Nominal 10 ns macro-step uses 100 explicit Euler substeps.
    localparam int FE_SUBSTEPS = 100;

    real vout_q;
    real vctrl_q;

    real vfb_q;
    real ipass_q;

    pg_cmp_rnm u_cmp (.q(pg_cmp));

    task automatic deriv(
        input  real  v,
        input  real  vc,
        input  logic en_i,
        input  logic load_hi_i,
        output real  dvout,
        output real  dvctrl
    );
        real en_r;
        real rload;
        real fbv;
        real vc_target;
        real ip;

        en_r  = en_i ? 1.0 : 0.0;
        rload = load_hi_i ? RL_HEAVY : RL_NORMAL;

        fbv = v * (RBOT / RDIV);

        // Saturation precedes the EA lag.
        vc_target = A0 * en_r * (VREF - fbv);
        if (vc_target < 0.0) begin
            vc_target = 0.0;
        end else if (vc_target > VC_MAX) begin
            vc_target = VC_MAX;
        end
        dvctrl = (vc_target - vc) / TAU_EA;

        ip = GM_PASS * vc;
        if (ip < 0.0) begin
            ip = 0.0;
        end else if (ip > IMAX) begin
            ip = IMAX;
        end
        if (!en_i) begin
            ip = 0.0;
        end

        // Divider current is explicit here; Simscape gets it from the resistor network.
        dvout = (ip - v / rload - v / RDIV) / COUT;
    endtask

    task automatic observe();
        localparam real EN_ONE = 1.0;
        real ip;
        vfb_q = vout_q * (RBOT / RDIV);
        ip    = GM_PASS * vctrl_q;
        if (ip < 0.0) begin
            ip = 0.0;
        end else if (ip > IMAX) begin
            ip = IMAX;
        end
        ipass_q = (en ? EN_ONE : 0.0) * ip;
        vout    = vout_q;
        vfb     = vfb_q;
        vctrl   = vctrl_q;
        ipass   = ipass_q;
    endtask

    // Both derivatives use the same pre-update state; pg_cmp updates once per macro-step.
    task automatic step(input real h);
        real dt;
        real dv;
        real dvc;

        dt = h / FE_SUBSTEPS;

        for (int k = 0; k < FE_SUBSTEPS; k = k + 1) begin
            deriv(vout_q, vctrl_q, en, load_hi, dv, dvc);
            vout_q  = vout_q  + dt * dv;
            vctrl_q = vctrl_q + dt * dvc;
        end

        observe();
        u_cmp.update(vout_q);
    endtask

    // Analog state is cleared only on cold start; digital reset does not touch it.
    task automatic rst_state();
        vout_q  = 0.0;
        vctrl_q = 0.0;
        u_cmp.rst();
        observe();
    endtask

    initial rst_state();
endmodule
