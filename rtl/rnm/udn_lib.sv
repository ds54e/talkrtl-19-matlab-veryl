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
// Only elements with state step in time (here the capacitor; ldo.sv's error
// amplifier does the same): every STEP_NS they update with nonblocking
// assignments, so none sees another's new state within the step. Everything
// else is continuous.
import udn_pkg::*;

module vsrc #(parameter real V)(inout enet p);
    timeunit 1ns; timeprecision 1ps;
    assign p = '{V, 0.0, 1.0e-9};
endmodule

module res_g #(parameter real R)(inout enet p);
    timeunit 1ns; timeprecision 1ps;
    assign p = '{0.0, 0.0, R};
endmodule

module res #(parameter real R)(inout enet p, inout enet n);
    timeunit 1ns; timeprecision 1ps;
    // Each end is driven by the other end's external Thevenin source (that
    // net's totals minus our own driver) in series with R, settling within the
    // time slot. Plain real scalars here: xezim runs this much faster than
    // struct-valued functions. The subtraction loses precision next to an
    // ideal source (R = 1e-9); no resistor in this demo touches that node.
    real vp = 0.0, rp = OPEN, vn = 0.0, rn = OPEN;  // our drivers on p and n
    assign p = '{vp, 0.0, rp};
    assign n = '{vn, 0.0, rn};

    always_comb begin
        real gp, sp, gn, sn, vp1, rp1, vn1, rn1, dv, dg;
        // External views from the current drivers, both before either update.
        gn = n.R < OPEN ? 1.0 / n.R : 0.0;
        sn = n.I;
        if (rn < OPEN) begin gn -= 1.0 / rn; sn -= vn / rn; end
        gp = p.R < OPEN ? 1.0 / p.R : 0.0;
        sp = p.I;
        if (rp < OPEN) begin gp -= 1.0 / rp; sp -= vp / rp; end
        vp1 = gn > 0.0 ? sn / gn : 0.0;  rp1 = gn > 0.0 ? R + 1.0 / gn : OPEN;
        vn1 = gp > 0.0 ? sp / gp : 0.0;  rn1 = gp > 0.0 ? R + 1.0 / gp : OPEN;
        // Update only on a real change (about 1e-12 relative, on the Norton
        // current and conductance), so roundoff cannot bounce between the ends.
        dv = vp1 / rp1 - vp / rp;  dg = 1.0 / rp1 - 1.0 / rp;
        if (dv * dv > 1.0e-24 * (1.0e-6 + (vp1 / rp1) * (vp1 / rp1) + (vp / rp) * (vp / rp)) ||
            dg * dg > 1.0e-24 * (1.0e-6 + 1.0 / (rp1 * rp1) + 1.0 / (rp * rp))) begin
            vp = vp1;
            rp = rp1;
        end
        dv = vn1 / rn1 - vn / rn;  dg = 1.0 / rn1 - 1.0 / rn;
        if (dv * dv > 1.0e-24 * (1.0e-6 + (vn1 / rn1) * (vn1 / rn1) + (vn / rn) * (vn / rn)) ||
            dg * dg > 1.0e-24 * (1.0e-6 + 1.0 / (rn1 * rn1) + 1.0 / (rn * rn))) begin
            vn = vn1;
            rn = rn1;
        end
    end
endmodule

module cap_g #(parameter real C)(inout enet p);
    timeunit 1ns; timeprecision 1ps;
    real history = 0.0;
    // Backward-Euler companion: history voltage in series with H/C.
    assign p = '{history, 0.0, H / C};
    always #STEP_NS history <= p.V;
endmodule

module sw_g #(parameter real RON, GOFF)
    (input logic on, inout enet p);
    timeunit 1ns; timeprecision 1ps;
    assign p = '{0.0, 0.0, on ? RON : 1.0 / GOFF};
endmodule

// Ideal current source: amps flows out of p and into n.
module isrc(input real amps, inout enet p, inout enet n);
    timeunit 1ns; timeprecision 1ps;
    assign p = '{0.0, -amps, OPEN};
    assign n = '{0.0,  amps, OPEN};
endmodule
