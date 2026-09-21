// system_nominal_tb -- end-to-end: SV-RNM LDO + Veryl supervisor.
//
//     en, load_hi -> SV-RNM LDO -> vout -> hysteretic comparator -> pg_cmp
//                                                                     |
//                                                    Veryl supervisor |
//                                                                     v
//                                                                  pgood
//
// `load_hi` goes only to the RNM. The supervisor is the Veryl source
// `rtl/veryl/pgood_supervisor.veryl`, used through its committed generated
// snapshot `rtl/generated/veryl/pgood_supervisor.sv` (the snapshot is verified
// against a fresh regeneration by `tools/check-generated-rtl`, and is what
// `sim/run_verilator.sh` compiles). No
// Stateflow, no CSR, no shadow register: the DUT's `en` and `pg_cmp` are the
// real signals and `pgood`/`state` are recorded live.
//
// ---------------------------------------------------------------------------
// Initial condition
//
// The supervisor's state registers carry no initializer, so before any
// clock edge `state`/`pgood` are X. The contract's initial condition (OFF,
// pgood=0, timing discarded) is therefore established with the DUT's own
// synchronous reset: two preamble clock periods with rst=1. No back-door poke
// of DUT internals is used. Those preamble periods are excluded from the
// comparison, and they do NOT advance the analog model, so the analog timebase
// stays aligned with the reference tick grid:
//
//     reference tick k  <->  analog time k*100 ns  <->  k-th post-reset observation
//
// Wall-clock therefore runs `preamble_ns` ahead of the analog timebase. The
// CSV records `time_ns = k*100` (the reference observation time) and the actual
// wall time separately in `record_ns`, so the offset is stated rather than
// implied.
//
// ---------------------------------------------------------------------------
// Scheduling. This is the part that must not
// be left to delta-cycle luck.
//
// CONTRACT section 4 fixes the per-tick order as
//     environment update -> observation -> output record
// and requires that at a tick time the sampled inputs (`en`, `pg_cmp`) are the
// values after that tick's environment update.
//
// ONE `initial` process owns the whole run: it drives `clk`, `en`, `load_hi`,
// it calls every analog step, and it writes every record. There is no second
// writer, so the ordering below is guaranteed by program order rather than by
// simulator event ordering.
//
// Clock: 100 ns period, 50 ns high / 50 ns low, rising edge at the observation
// instants.
//
// Timeline of one period, entered at the observation instant T_k with clk
// already high:
//
//   T_k       capture the analog state and the inputs the supervisor samples
//   T_k+10..  `#DT` then step: the step lands at the END of its interval, so
//   T_k+50    the first thing that happens after `clk = 1` was set in the
//             previous period is a time advance. That lets the supervisor's
//             always_ff run at T_k while `pg_cmp` still holds its T_k value.
//             Stepping before the time advance would instead let the
//             supervisor observe pg_cmp(T_k + 10 ns).
//   T_k+50    clk falls (cosmetic; the supervisor is posedge-only)
//   T_k+50    output record: supervisor outputs are read 50 ns after the edge,
//             long after its non-blocking updates completed. The supervisor is
//             purely synchronous, so its outputs cannot change between the edge
//             and this read.
//   T_k+60..  the rest of the tick's integration
//   T_k+100   environment input update, then the next rising edge
module system_nominal_tb;
    timeunit 1ns;
    timeprecision 1ps;

    localparam int  CLK_HALF_NS       = 50;
    localparam int  PREAMBLE_TICKS    = 2;   // reset periods, excluded from compare
    localparam logic [1:0] ST_OFF  = 2'd0;
    localparam logic [1:0] ST_WAIT = 2'd1;
    localparam logic [1:0] ST_ON   = 2'd2;

    // ---- scenario (shared with rnm_core_tb; nominal defaults) --------------
    int  en_rise_ns   = 2000;
    int  load_rise_ns = 25000;
    int  load_fall_ns = 35000;
    int  en_fall_ns   = 0;
    int  end_ns       = 50000;
    int  dt_ps        = 10000;
    string csv_path   = "system_nominal.csv";

    real dt_ns;
    real dt_s;
    int  steps_per_tick;
    int  half_steps;
    int  ntick;
    real preamble_ns = 0.0;

    logic clk     = 1'b0;
    logic rst     = 1'b0;
    logic en      = 1'b0;
    logic load_hi = 1'b0;

    real  vout, vfb, vctrl, ipass;
    logic pg_cmp;
    logic pgood;
    logic [1:0] state;

    int  errors = 0;
    int  fd;
    int  nan_or_inf = 0;
    int  bound_low  = 0;
    int  bound_high = 0;
    int  bad_state  = 0;

    // captured at the observation instant T_k
    real  cap_vout, cap_vfb, cap_vctrl, cap_ipass;
    logic cap_pg_cmp, cap_en, cap_load_hi;

    ldo_rnm u_ldo (
        .en      (en),
        .load_hi (load_hi),
        .vout    (vout),
        .vfb     (vfb),
        .vctrl   (vctrl),
        .ipass   (ipass),
        .pg_cmp  (pg_cmp)
    );

    pgood_supervisor u_sup (
        .clk    (clk),
        .rst    (rst),
        .en     (en),
        .pg_cmp (pg_cmp),
        .pgood  (pgood),
        .state  (state)
    );

    function automatic logic env_en(input int t_ns);
        if (en_fall_ns != 0 && t_ns >= en_fall_ns) return 1'b0;
        return (t_ns >= en_rise_ns);
    endfunction

    function automatic logic env_lh(input int t_ns);
        return (t_ns >= load_rise_ns && t_ns < load_fall_ns);
    endfunction

    function automatic string state_name(input logic [1:0] s);
        case (s)
            ST_OFF:  return "OFF";
            ST_WAIT: return "WAIT";
            ST_ON:   return "ON";
            default: return "BAD";
        endcase
    endfunction

    task automatic check(input logic cond, input string what);
        if (!cond) begin
            errors = errors + 1;
            $display("SYSTEM_NOMINAL_FAIL: %s", what);
        end
    endtask

    task automatic capture();
        cap_vout = vout; cap_vfb = vfb; cap_vctrl = vctrl; cap_ipass = ipass;
        cap_pg_cmp = pg_cmp; cap_en = en; cap_load_hi = load_hi;
    endtask

    task automatic get_plusargs();
        int v;
        if ($value$plusargs("EN_RISE_NS=%d",   v)) en_rise_ns   = v;
        if ($value$plusargs("LOAD_RISE_NS=%d", v)) load_rise_ns = v;
        if ($value$plusargs("LOAD_FALL_NS=%d", v)) load_fall_ns = v;
        if ($value$plusargs("EN_FALL_NS=%d",   v)) en_fall_ns   = v;
        if ($value$plusargs("END_NS=%d",       v)) end_ns       = v;
        if ($value$plusargs("DT_PS=%d",        v)) dt_ps        = v;
        void'($value$plusargs("CSV=%s", csv_path));
    endtask

    // One tick's output record. The first eight columns are the reference tick
    // record; the rest is debug context.
    task automatic record(input int tick);
        if (state !== ST_OFF && state !== ST_WAIT && state !== ST_ON) bad_state = bad_state + 1;
        $fwrite(fd, "%0d,%0d,%0d,%0d,%0d,%0d,%s,%0d,%.17g,%.17g,%.17g,%.17g,%0d,%.17g\n",
                tick, tick*100, rst, cap_en, cap_pg_cmp, state, state_name(state), pgood,
                cap_vout, cap_vfb, cap_vctrl, cap_ipass, cap_load_hi, $realtime);
        if (cap_vout != cap_vout || cap_vout > 1.0e30 || cap_vout < -1.0e30) nan_or_inf = nan_or_inf + 1;
        if (cap_vout < -1.0e-6) bound_low = bound_low + 1;
        if (cap_vout >= 1.1) bound_high = bound_high + 1;
    endtask

    initial begin
        get_plusargs();
        dt_ns = dt_ps / 1000.0;
        dt_s  = dt_ps * 1e-12;
        steps_per_tick = 100000 / dt_ps;
        half_steps = steps_per_tick / 2;
        ntick = end_ns / 100;
        preamble_ns = PREAMBLE_TICKS * 100.0;

        $display("SYSTEM_NOMINAL: dt_ps=%0d steps_per_tick=%0d half_steps=%0d ntick=%0d preamble_ns=%0.0f",
                 dt_ps, steps_per_tick, half_steps, ntick, preamble_ns);
        $display("SYSTEM_NOMINAL: scenario en_rise=%0d load_rise=%0d load_fall=%0d en_fall=%0d",
                 en_rise_ns, load_rise_ns, load_fall_ns, en_fall_ns);

        check(steps_per_tick % 2 == 0, "steps per tick splits into two halves");
        check(half_steps * dt_ps * 2 == 100000, "clock halves span exactly 100 ns");

        fd = $fopen(csv_path, "w");
        check(fd != 0, "CSV opened for writing");
        $fwrite(fd, "tick,time_ns,rst,en,pg_cmp,state,state_name,pgood,vout,vfb,vctrl,ipass,load_hi,record_ns\n");

        // ---- analog cold start + DUT reset preamble -----------------------
        u_ldo.rst_state();
        rst = 1'b1;
        en  = 1'b0;
        load_hi = 1'b0;
        clk = 1'b0;
        repeat (PREAMBLE_TICKS) begin
            #(CLK_HALF_NS) clk = 1'b1;    // DUT samples with rst=1
            #(CLK_HALF_NS) clk = 1'b0;
        end
        rst = 1'b0;
        check(state === ST_OFF && pgood === 1'b0,
              "DUT reaches the contract initial condition (OFF, pgood=0) after the reset preamble");

        // ---- tick 0: pure initial observation, no clock edge ---------------
        en      = env_en(0);
        load_hi = env_lh(0);
        capture();
        record(0);

        // ---- prologue: analog [0 -> 100 ns], clk low ----------------------
        repeat (steps_per_tick) begin
            #(dt_ns);
            u_ldo.step(dt_s);
        end
        // environment input update, then the first real rising edge
        en      = env_en(100);
        load_hi = env_lh(100);
        clk     = 1'b1;

        for (int k = 1; k <= ntick; k++) begin
            // observation instant for tick k. Reading the analog/input values
            // here is race-free: this process is their only writer.
            capture();
            check($realtime == preamble_ns + k*100.0,
                  "observation instant is exactly preamble + k*100 ns");

            // first half: the immediate #DT lets the supervisor's always_ff run
            // at this instant before any step can move pg_cmp.
            repeat (half_steps) begin
                #(dt_ns);
                u_ldo.step(dt_s);
            end
            clk = 1'b0;                       // falling edge
            record(k);                        // output record

            if (k < ntick) begin
                repeat (half_steps) begin
                    #(dt_ns);
                    u_ldo.step(dt_s);
                end
                en      = env_en((k+1)*100);
                load_hi = env_lh((k+1)*100);
                clk     = 1'b1;               // rising edge for tick k+1
            end
        end

        $fclose(fd);

        $display("SYSTEM_NOMINAL: nan_or_inf=%0d bound_low=%0d boundary_violations=%0d bad_state=%0d",
                 nan_or_inf, bound_low, bound_high, bad_state);
        check(nan_or_inf == 0, "no NaN/Inf in vout");
        check(bound_low == 0,  "vout never below -1 uV");
        check(bound_high == 0, "vout always below 1.1 V");
        check(bad_state == 0,  "state stayed in {OFF, WAIT, ON}");

        if (errors != 0) $fatal(1, "SYSTEM_NOMINAL_FAIL errors=%0d", errors);
        $display("SYSTEM_NOMINAL_PASS");
        $finish;
    end
endmodule
