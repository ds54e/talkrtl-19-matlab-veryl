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

    // Vin: DC Voltage Source
    vsrc #(.V(1.2)) vin (.p(in));

    // Error Amp
    erramp #(.A0(200.0), .VREF(0.45), .TAU(0.5e-6), .VMAX(1.0)) ea (
        .en   (en),
        .vfb  (vfb),
        .vctrl(vctrl)
    );

    // Pass: Controlled Current Source from Vin to Vout
    isrc #(.GM(4.0e-3), .IMAX(5.0e-3)) pass (
        .en     (en),
        .control(vctrl),
        .p      (in),
        .n      (out),
        .amps   (ipass)
    );

    // Rdiv
    ldo_rdiv rdiv (.out(out), .vfb(vfb));

    // Cout
    cap_g #(.C(10.0e-9)) cout (.p(out));

    // Load
    ldo_load load (.load_hi(load_hi), .out(out));

    // Voltage Sensor for vout, and the PGOOD comparator
    vsense s_out (.p(out), .volts(vout));
    pg_cmp cmp (.v(vout), .q(pg_cmp));
endmodule

// Rdiv: the feedback divider (vfb = vout / 2) and its voltage sensor.
module ldo_rdiv import udn_pkg::*; (inout enet out, output real vfb);
    timeunit 1ns; timeprecision 1ps;
    enet fb;
    res    #(.R(100.0e3)) rtop (.p(out), .n(fb));
    res_g  #(.R(100.0e3)) rbot (.p(fb));
    vsense                s_fb (.p(fb), .volts(vfb));
endmodule

// Load: Rload, plus Rheavy switched in while load_hi (1.8 k || 360 = 300 ohm).
module ldo_load import udn_pkg::*; (input logic load_hi, inout enet out);
    timeunit 1ns; timeprecision 1ps;
    enet sw;
    res_g #(.R(1.8e3)) rload  (.p(out));
    res   #(.R(360.0)) rheavy (.p(out), .n(sw));
    sw_g               swh    (.on(load_hi), .p(sw));
endmodule
