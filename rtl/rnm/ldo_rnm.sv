// SV-RNM LDO on UDN nets: the same blocks as the Simscape "Analog LDO"
// subsystem, with the values from CONTRACT.md.
module ldo_rnm import udn_pkg::*; (
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

    vsrc   #(.V(1.2))                    vin   (in);                         // Vin
    erramp #(.A0(200.0), .VREF(0.45), .TAU(0.5e-6), .VMAX(1.0))
                                         ea    (en, vfb, vctrl);             // Error Amp
    isrc   #(.GM(4.0e-3), .IMAX(5.0e-3)) pass  (en, vctrl, in, out, ipass);  // Pass
    ldo_rdiv                             rdiv  (out, vfb);                   // Rdiv
    cap_g  #(.C(10.0e-9))                cout  (out);                        // Cout
    ldo_load                             load  (load_hi, out);               // Load
    vsense                               s_out (out, vout);                  // Vsense_vout
    pg_cmp_rnm                           cmp   (.v(vout), .q(pg_cmp));       // pg_cmp
endmodule

// Rdiv: the feedback divider (vfb = vout / 2) and its voltage sensor.
module ldo_rdiv import udn_pkg::*; (inout enet out, output real vfb);
    timeunit 1ns; timeprecision 1ps;
    enet fb;
    res    #(.R(100.0e3)) rtop (out, fb);
    res_g  #(.R(100.0e3)) rbot (fb);
    vsense                s_fb (fb, vfb);
endmodule

// Load: Rload, plus Rheavy switched in while load_hi (1.8 k || 360 = 300 ohm).
module ldo_load import udn_pkg::*; (input logic load_hi, inout enet out);
    timeunit 1ns; timeprecision 1ps;
    enet sw;
    res_g #(.R(1.8e3)) rload  (out);
    res   #(.R(360.0)) rheavy (out, sw);
    sw_g               swh    (load_hi, sw);
endmodule
