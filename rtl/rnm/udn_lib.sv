// Circuit nodes are {V, I, R} nets resolved with Millman's theorem.
package udn_pkg;
    timeunit 1ns;
    timeprecision 1ps;
    parameter real STEP_NS = 1.25;
    parameter real H = STEP_NS * 1.0e-9;
    parameter real OPEN = 1.0e30;
    typedef struct { real V; real I; real R; } electrical;

    function automatic electrical millman(input electrical drivers[]);
        electrical result;
        real g, s;
        g = 0.0;
        s = 0.0;
        foreach (drivers[k]) begin
            if (drivers[k].R > 0.0 && drivers[k].R < OPEN) begin
                g += 1.0 / drivers[k].R;
                s += drivers[k].V / drivers[k].R;
            end
            s += drivers[k].I;
        end
        result.V = g > 0.0 ? s / g : 0.0;
        result.I = s; // Norton sum, NOT a branch-current measurement.
        result.R = g > 0.0 ? 1.0 / g : OPEN;
        return result;
    endfunction
    nettype electrical enet with millman;

    function automatic real clip(input real x, lo, hi);
        return x < lo ? lo : (x > hi ? hi : x);
    endfunction
endpackage

// All grounded elements use the implicit electrical reference (0 V).
// At t + 1 ps snapshot the settled state and post-NBA inputs; at t + 2 ps
// commit the next state. It is then held through the boundary t + STEP_NS.
// Snapshots never read another element's pending value, so process order
// cannot affect a step. Sensors publish at +3 ps, after resolution settles.
// STEP_NS must exceed 3 ps and divide the 10 ns grid.
import udn_pkg::*;

module vsrc #(parameter real V = 1.2)(inout enet p);
    timeunit 1ns; timeprecision 1ps;
    assign p = '{V, 0.0, 1.0e-9};
endmodule

module res_g #(parameter real R = 1000.0)(inout enet p);
    timeunit 1ns; timeprecision 1ps;
    assign p = '{0.0, 0.0, R};
endmodule

module res #(parameter real R = 1000.0)(inout enet p, inout enet n);
    timeunit 1ns; timeprecision 1ps;
    electrical dp = '{0.0, 0.0, OPEN}, dn = '{0.0, 0.0, OPEN};
    electrical next_p, next_n;
    assign p = dp;
    assign n = dn;

    // Subtract our driver to see the external Thevenin source, then add R.
    // Cancellation loses precision for widely separated conductances; neither
    // resistor in this LDO touches the ideal-source node (R = 1e-9).
    function automatic electrical through(input electrical net_value, input electrical own);
        real g, s;
        g = net_value.R > 0.0 && net_value.R < OPEN ? 1.0 / net_value.R : 0.0;
        s = net_value.I - own.I;
        if (own.R > 0.0 && own.R < OPEN) begin
            g -= 1.0 / own.R;
            s -= own.V / own.R;
        end
        return g > 0.0 ? electrical'{s / g, 0.0, R + 1.0 / g}
                       : electrical'{0.0, 0.0, OPEN};
    endfunction

    function automatic bit changed(input real a, input real b);
        real delta, scale;
        delta = a > b ? a - b : b - a;
        scale = 1.0e-3 + (a < 0.0 ? -a : a) + (b < 0.0 ? -b : b);
        return delta > 1.0e-12 * scale;
    endfunction

    always_comb begin
        next_p = through(n, dn);
        next_n = through(p, dp);
        // Compare Norton contributions, retaining sub-tolerance drivers to stop
        // roundoff ping-pong: 1e-12 relative, with 1 fA / 1 fS absolute floors.
        // A noisy external voltage behind an almost-open R is insignificant.
        if (changed(next_p.V / next_p.R, dp.V / dp.R) ||
            changed(1.0 / next_p.R, 1.0 / dp.R)) dp = next_p;
        if (changed(next_n.V / next_n.R, dn.V / dn.R) ||
            changed(1.0 / next_n.R, 1.0 / dn.R)) dn = next_n;
    end
endmodule

module cap_g #(parameter real C = 10.0e-9)(inout enet p);
    timeunit 1ns; timeprecision 1ps;
    real history = 0.0, snapshot;
    // Backward-Euler companion: history voltage in series with H/C.
    assign p = '{history, 0.0, H / C};
    initial forever begin
        #0.001;
        snapshot = p.V;
        #0.001;
        history = snapshot;
        #(STEP_NS - 0.002);
    end
endmodule

module sw_g #(parameter real RON = 1.0e-6, GOFF = 1.0e-12)
    (input logic on, inout enet p);
    timeunit 1ns; timeprecision 1ps;
    real r = 1.0 / GOFF, next_r;
    assign p = '{0.0, 0.0, r};
    initial forever begin
        #0.001;
        next_r = on ? RON : 1.0 / GOFF;
        #0.001;
        r = next_r;
        #(STEP_NS - 0.002);
    end
endmodule

module isrc #(parameter real GM = 4.0e-3, IMAX = 5.0e-3)
    (input logic en, input real control, inout enet p, inout enet n,
     output real amps);
    timeunit 1ns; timeprecision 1ps;
    bit enabled = 0, next_enabled;
    assign amps = enabled ? clip(GM * control, 0.0, IMAX) : 0.0;
    assign p = '{0.0, -amps, OPEN};
    assign n = '{0.0,  amps, OPEN};
    initial forever begin
        #0.001;
        next_enabled = en;
        #0.001;
        enabled = next_enabled;
        #(STEP_NS - 0.002);
    end
endmodule

module vsense(input enet p, output real volts);
    timeunit 1ns; timeprecision 1ps;
    initial begin
        volts = 0.0;
        forever begin
            #0.003;
            volts = p.V;
            #(STEP_NS - 0.003);
        end
    end
endmodule

// Not a circuit element: like the Simulink blocks, a saturating gain followed
// by a first-order lag, stepped with the same snapshot/commit timing.
module erramp #(parameter real A0 = 200.0, VREF = 0.45, TAU = 0.5e-6, VMAX = 1.0)
    (input logic en, input real vfb, output real vctrl);
    timeunit 1ns; timeprecision 1ps;
    real vc = 0.0, next_vc;
    assign vctrl = vc;
    initial forever begin
        #0.001;
        next_vc = vc + H / TAU * (clip(A0 * (en ? 1.0 : 0.0) * (VREF - vfb), 0.0, VMAX) - vc);
        #0.001;
        vc = next_vc;
        #(STEP_NS - 0.002);
    end
endmodule
