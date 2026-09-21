// ldo_rnm -- SystemVerilog Real Number Model of the CONTRACT.md LDO.
//
// Scope: plain SystemVerilog only (logic / real). No wreal, no user-defined
// nettypes, no EEnet, no Verilog-AMS, no DPI. The model is a two-state
// continuous-time system integrated with explicit fixed-step Forward Euler
// substepping:
//
//     states:  vout (real), vctrl (real)
//
//     vfb        = vout * rbot/(rtop+rbot)
//     vc_target  = clip(A0 * en * (vref - vfb), 0, 1 V)
//     d(vctrl)/dt = (vc_target - vctrl) / tau_ea
//     ipass      = en * clip(gm_pass * vctrl, 0, imax)
//     cout*d(vout)/dt = ipass - vout/Rload - vout/(rtop+rbot)
//
// CONTRACT §2 fixes the saturation *before* the EA first-order lag; moving it
// after the lag changes startup behaviour and is forbidden, so `vc_target` is
// clipped and only then differenced against the state.
//
// `load_hi` selects the total load resistance directly: 0 -> Rload normal
// (1.8 kohm), 1 -> Rload heavy (300 ohm). CONTRACT §2 explicitly rules out
// interpreting heavy as "1.8 kohm in parallel with 300 ohm".
//
// Deliberate design properties, checked by the comparison:
//
//   * No time, no schedule, no scenario in this file. `step(h)` is a pure
//     fixed-step advance of the ODEs above; the testbench owns every event
//     time. There is no waveform lookup, no scenario id, no `if (time < ...)`.
//   * `step(h)` subdivides its macro-step h into FE_SUBSTEPS Forward Euler
//     substeps. Each substep re-evaluates vfb / vc_target / ipass / load current
//     from its own `vout`/`vctrl` at the start of that substep and applies both
//     state updates from those same values, so the integrator is explicit and
//     never semi-implicit. The substep size is internal to this module: the
//     caller keeps its own macro-step and observation grid.
//   * `en` and `load_hi` are held constant for the duration of one call, as
//     the TB only ever changes them on an integration boundary.
//   * `vctrl` is the positive-polarity control quantity that strengthens the
//     pass current. It is not a PMOS gate voltage.
//
// Contract constants: vin=1.2 V, vref=0.45 V, rtop=rbot=100 kohm, cout=10 nF,
// Rload 1.8 kohm / 300 ohm, A0=200, tau_ea=0.5 us, gm_pass=4 mA/V, imax=5 mA,
// vctrl range 0..1 V. `vin` is a stated constant of the conditional
// current-drive model but is not an operand of any equation above; the KCL
// deliberately has no vin term (the pass element is modelled as a controlled
// current source, not as a resistive drop).
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

    // Forward Euler substeps per external step(h). The nominal 10 ns macro-step
    // is divided into 100 explicit Euler updates of 0.1 ns each. This keeps the
    // existing external time grid while satisfying the current comparison
    // tolerances.
    localparam int FE_SUBSTEPS = 100;

    // Continuous states.
    real vout_q;
    real vctrl_q;

    // Debug observations, refreshed from the post-step state.
    real vfb_q;
    real ipass_q;

    // pg_cmp is produced by the comparator from vout alone (CONTRACT §3), so
    // this model cannot manufacture pgood out of the acceptance verdict.
    pg_cmp_rnm u_cmp (.q(pg_cmp));

    // One derivative evaluation of the two-state system at the state (v, vc)
    // with the environment inputs held for this step.
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

        // EA: gain, then saturation, then the first-order lag (CONTRACT §2).
        vc_target = A0 * en_r * (VREF - fbv);
        if (vc_target < 0.0) begin
            vc_target = 0.0;
        end else if (vc_target > VC_MAX) begin
            vc_target = VC_MAX;
        end
        dvctrl = (vc_target - vc) / TAU_EA;

        // Pass element: controlled current source, 0..imax, disabled by en.
        ip = GM_PASS * vc;
        if (ip < 0.0) begin
            ip = 0.0;
        end else if (ip > IMAX) begin
            ip = IMAX;
        end
        if (!en_i) begin
            ip = 0.0;
        end

        // KCL at vout: pass current in, load and divider out. The divider term
        // is explicit here because the RNM has no network to compute it; the
        // Simscape model gets it from the resistive network instead.
        dvout = (ip - v / rload - v / RDIV) / COUT;
    endtask

    // Refresh the debug observations from the current state.
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

    // Advance the two states by one fixed macro-step of size `h` as FE_SUBSTEPS
    // explicit Forward Euler substeps, then let the comparator see the new vout.
    // Both derivatives of a substep come from the same pre-update state, so this
    // is explicit Euler and not semi-implicit Euler. `h` is supplied by the
    // caller so that the 10 ns nominal run and any experimental step size use the
    // identical source; the comparator is refreshed once per macro-step, on the
    // same boundary as the observation, never once per substep.
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

    // Cold-start initial condition (CONTRACT §2): vout=0, vctrl=0, pg_cmp=0.
    // The digital reset does not touch the analog state, so this is the only
    // way the analog state is cleared.
    task automatic rst_state();
        vout_q  = 0.0;
        vctrl_q = 0.0;
        u_cmp.rst();
        observe();
    endtask

    initial rst_state();
endmodule
