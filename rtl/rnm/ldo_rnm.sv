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

    enet vin_node, vout_node, vfb_node, switch_node;
    real pass_amps;
    // Preserve the effective-heavy-load parameter: 1800 || 360 = 300 ohm.
    localparam real RHEAVY = 1.0 / (1.0 / RL_HEAVY - 1.0 / RL_NORMAL);

    udn_voltage_source #(.V(1.2)) u_vin (vin_node); // Vin: DC Voltage Source
    udn_current_source #(.GM(GM_PASS), .IMAX(IMAX)) u_pass
        (en, vctrl, vin_node, vout_node, pass_amps); // Pass: Controlled Current Source
    udn_resistor #(.R(RTOP)) u_rtop (vout_node, vfb_node); // Rdiv: Rtop
    udn_ground_resistor #(.R(RBOT)) u_rbot (vfb_node); // Rdiv: Rbot
    udn_capacitor #(.C(COUT)) u_cout (vout_node); // Cout
    udn_ground_resistor #(.R(RL_NORMAL)) u_rload (vout_node); // Load: Rload
    udn_resistor #(.R(RHEAVY)) u_rheavy (vout_node, switch_node); // Load: Rheavy
    udn_ground_switch u_switch (load_hi, switch_node); // Load: Switch to ground
    udn_voltage_sensor u_vout (vout_node, vout); // Vout Voltage Sensor
    udn_voltage_sensor u_vfb (vfb_node, vfb); // Vfb Voltage Sensor
    udn_current_sensor u_ipass (pass_amps, ipass); // Pass Current Sensor

    // Error Amp: Simulink saturation followed by a first-order lag.
    real vc = 0.0, next_vc;
    assign vctrl = vc;
    initial forever begin
        #0.001;
        next_vc = vc + H / TAU_EA * (clip(A0 * (en ? 1.0 : 0.0) *
                                        (VREF - vfb), 0.0, VC_MAX) - vc);
        #0.001;
        vc = next_vc;
        #(STEP_NS - 0.002);
    end

    pg_cmp_rnm u_cmp (.v(vout), .q(pg_cmp));
endmodule
