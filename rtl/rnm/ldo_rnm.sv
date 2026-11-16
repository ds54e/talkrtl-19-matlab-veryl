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

    import udn_pkg::*;

    // Same blocks as the Simscape "Analog LDO" subsystem.
    enet in, out;
    // Rheavy is switched in parallel with Rload: 1800 || 360 = 300 ohm.
    localparam real RHEAVY = 1.0 / (1.0 / RL_HEAVY - 1.0 / RL_NORMAL);

    vsrc     #(.V(1.2))                    vin   (in);                         // Vin
    erramp   #(.A0(A0), .VREF(VREF), .TAU(TAU_EA), .VMAX(VC_MAX))
                                           ea    (en, vfb, vctrl);             // Error Amp
    isrc     #(.GM(GM_PASS), .IMAX(IMAX))  pass  (en, vctrl, in, out, ipass);  // Pass
    ldo_rdiv #(.RTOP(RTOP), .RBOT(RBOT))   rdiv  (out, vfb);                   // Rdiv
    cap_g    #(.C(COUT))                   cout  (out);                        // Cout
    ldo_load #(.RL(RL_NORMAL), .RHEAVY(RHEAVY))
                                           load  (load_hi, out);               // Load
    vsense                                 s_out (out, vout);                  // Vsense_vout
    pg_cmp_rnm                             cmp   (.v(vout), .q(pg_cmp));       // pg_cmp
endmodule

// Rdiv: the feedback divider and its voltage sensor.
module ldo_rdiv import udn_pkg::*; #(parameter real RTOP = 100.0e3, RBOT = 100.0e3)
    (inout enet out, output real vfb);
    timeunit 1ns; timeprecision 1ps;
    enet fb;
    res    #(.R(RTOP)) rtop (out, fb);
    res_g  #(.R(RBOT)) rbot (fb);
    vsense             s_fb (fb, vfb);
endmodule

// Load: Rload, plus Rheavy switched to ground while load_hi is high.
module ldo_load import udn_pkg::*; #(parameter real RL = 1.8e3, RHEAVY = 360.0)
    (input logic load_hi, inout enet out);
    timeunit 1ns; timeprecision 1ps;
    enet sw;
    res_g #(.R(RL))     rload  (out);
    res   #(.R(RHEAVY)) rheavy (out, sw);
    sw_g                swh    (load_hi, sw);
endmodule
