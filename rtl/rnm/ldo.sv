// SV-RNM LDO on UDN nets: the same blocks as the Simscape "Analog LDO"
// subsystem, with the values from CONTRACT.md.
module ldo import udn_pkg::*; (
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

    enet in, out;

    vsrc #(.V(1.2)) vin (.p(in));

    ldo_erramp ea (.en(en), .vfb(vfb), .vctrl(vctrl));
    ldo_pass pass (.en(en), .vctrl(vctrl), .in(in), .out(out), .ipass(ipass));
    ldo_rdiv rdiv (.out(out), .vfb(vfb));
    cap_g #(.C(10.0e-9)) cout (.p(out));
    ldo_load load (.load_hi(load_hi), .out(out));
    assign vout = out.V;
    pg_cmp cmp (.v(vout), .q(pg_cmp));
endmodule

// Error Amp: like the Simulink blocks, a saturating gain followed by a
// first-order lag, not a circuit element.
module ldo_erramp import udn_pkg::*; (input logic en, input real vfb, output real vctrl);
    timeunit 1ns; timeprecision 1ps;
    localparam real A0 = 200.0, VREF = 0.45, TAU = 0.5e-6, VMAX = 1.0;
    real vc = 0.0;
    assign vctrl = vc;
    always #STEP_NS vc <= vc + H / TAU * (clip(A0 * (en ? 1.0 : 0.0) * (VREF - vfb), 0.0, VMAX) - vc);
endmodule

// Pass: the Simulink gain, saturation and en gate driving a current source
// from the 1.2 V input to the output.
module ldo_pass import udn_pkg::*;
    (input logic en, input real vctrl, inout enet in, inout enet out, output real ipass);
    timeunit 1ns; timeprecision 1ps;
    assign ipass = en ? clip(4.0e-3 * vctrl, 0.0, 5.0e-3) : 0.0;
    isrc src (.amps(ipass), .p(in), .n(out));
endmodule

module ldo_rdiv import udn_pkg::*; (inout enet out, output real vfb);
    timeunit 1ns; timeprecision 1ps;
    enet fb;
    res    #(.R(100.0e3)) rtop (.p(out), .n(fb));
    res_g  #(.R(100.0e3)) rbot (.p(fb));
    assign vfb = fb.V;
endmodule

// While load_hi, Rheavy is in parallel with Rload: 1.8 k || 360 = 300 ohm.
module ldo_load import udn_pkg::*; (input logic load_hi, inout enet out);
    timeunit 1ns; timeprecision 1ps;
    enet sw;
    res_g #(.R(1.8e3)) rload  (.p(out));
    res   #(.R(360.0)) rheavy (.p(out), .n(sw));
    sw_g               swh    (.on(load_hi), .p(sw));
endmodule
