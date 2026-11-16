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

    erramp #(.A0(200.0), .VREF(0.45), .TAU(0.5e-6), .VMAX(1.0)) ea (
        .en   (en),
        .vfb  (vfb),
        .vctrl(vctrl)
    );

    isrc #(.GM(4.0e-3), .IMAX(5.0e-3)) pass (
        .en     (en),
        .control(vctrl),
        .p      (in),
        .n      (out),
        .amps   (ipass)
    );

    ldo_rdiv rdiv (.out(out), .vfb(vfb));
    cap_g #(.C(10.0e-9)) cout (.p(out));
    ldo_load load (.load_hi(load_hi), .out(out));
    vsense s_out (.p(out), .volts(vout));
    pg_cmp cmp (.v(vout), .q(pg_cmp));
endmodule

module ldo_rdiv import udn_pkg::*; (inout enet out, output real vfb);
    timeunit 1ns; timeprecision 1ps;
    enet fb;
    res    #(.R(100.0e3)) rtop (.p(out), .n(fb));
    res_g  #(.R(100.0e3)) rbot (.p(fb));
    vsense                s_fb (.p(fb), .volts(vfb));
endmodule

// While load_hi, Rheavy is in parallel with Rload: 1.8 k || 360 = 300 ohm.
module ldo_load import udn_pkg::*; (input logic load_hi, inout enet out);
    timeunit 1ns; timeprecision 1ps;
    enet sw;
    res_g #(.R(1.8e3)) rload  (.p(out));
    res   #(.R(360.0)) rheavy (.p(out), .n(sw));
    sw_g               swh    (.on(load_hi), .p(sw));
endmodule
