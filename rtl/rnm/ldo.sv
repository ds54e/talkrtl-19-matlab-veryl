// SV-RNM LDO chip on UDN nets, with the values from CONTRACT.md: the pass
// between the vin and vout pins, the error amplifier, the feedback divider and
// the PGOOD comparator. Cout and the load are on the board (the testbench).
module ldo import udn_pkg::*; (
    inout  enet  vin,
    inout  enet  vout,
    input  logic en,
    output logic pg_cmp
);
    timeunit 1ns; timeprecision 1ps;

    real vfb, vctrl, ipass;

    ldo_pass pass (.en(en), .vctrl(vctrl), .in(vin), .out(vout), .ipass(ipass));
    ldo_rdiv rdiv (.out(vout), .vfb(vfb));
    ldo_erramp ea (.en(en), .vfb(vfb), .vctrl(vctrl));
    pg_cmp cmp (.v(vout.V), .q(pg_cmp));
endmodule

// Pass: the Simulink gain, saturation and en gate driving a current source.
module ldo_pass import udn_pkg::*; (
    input  logic en,
    input  real  vctrl,
    inout  enet  in,
    inout  enet  out,
    output real  ipass
);
    timeunit 1ns; timeprecision 1ps;
    assign ipass = en ? clip(4.0e-3 * vctrl, 0.0, 5.0e-3) : 0.0;
    isrc src (.amps(ipass), .p(in), .n(out));
endmodule

module ldo_rdiv import udn_pkg::*; (
    inout  enet out,
    output real vfb
);
    timeunit 1ns; timeprecision 1ps;
    enet fb;
    res   #(.R(100.0e3)) rtop (.p(out), .n(fb));
    res_g #(.R(100.0e3)) rbot (.p(fb));
    assign vfb = fb.V;
endmodule

// Error Amp: like the Simulink blocks, a saturating gain followed by a
// first-order lag, not a circuit element.
module ldo_erramp import udn_pkg::*; (
    input  logic en,
    input  real  vfb,
    output real  vctrl
);
    timeunit 1ns; timeprecision 1ps;
    localparam real A0 = 200.0, VREF = 0.45, TAU = 0.5e-6, VMAX = 1.0;
    real target, vc = 0.0;
    assign target = en ? clip(A0 * (VREF - vfb), 0.0, VMAX) : 0.0;
    assign vctrl = vc;
    always #STEP_NS vc <= vc + H / TAU * (target - vc);
endmodule
