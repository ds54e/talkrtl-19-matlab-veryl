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

    // Circuit nodes; one instance per block of the Simscape model.
    enet in, out, fb, sw;
    // Rheavy is the resistor switched in parallel with Rload: 1800 || 360 = 300 ohm.
    localparam real RHEAVY = 1.0 / (1.0 / RL_HEAVY - 1.0 / RL_NORMAL);

    vsrc   #(.V(1.2))                    vin    (in);                         // DC Voltage Source
    isrc   #(.GM(GM_PASS), .IMAX(IMAX))  pass   (en, vctrl, in, out, ipass);  // Controlled Current Source
    res    #(.R(RTOP))                   rtop   (out, fb);                    // Resistor
    res_g  #(.R(RBOT))                   rbot   (fb);                         // Resistor
    cap_g  #(.C(COUT))                   cout   (out);                        // Capacitor
    res_g  #(.R(RL_NORMAL))              rload  (out);                        // Resistor
    res    #(.R(RHEAVY))                 rheavy (out, sw);                    // Resistor
    sw_g                                 swh    (load_hi, sw);                // Switch
    vsense                               s_out  (out, vout);                  // Voltage Sensor
    vsense                               s_fb   (fb, vfb);                    // Voltage Sensor
    erramp #(.A0(A0), .VREF(VREF), .TAU(TAU_EA), .VMAX(VC_MAX))
                                         ea     (en, vfb, vctrl);             // Error Amp
    pg_cmp_rnm                           cmp    (.v(vout), .q(pg_cmp));       // pg_cmp
endmodule
