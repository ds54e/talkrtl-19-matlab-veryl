// rnm_core_tb -- RNM-only testbench for the SV-RNM LDO.
//
// No Veryl, no RgGen, no CSR: this measures the analog model on its own before
// anything is integrated with the supervisor. It writes one CSV row
// per 100 ns tick, matching the reference tick grid (501 ticks over 50 us).
//
// Scenario timing belongs to the testbench/environment, never to the DUT:
// `ldo_rnm` contains no time, no schedule and no scenario. This TB owns the
// scenario used by this RNM-only run and hands the model one fixed step at a time.
//
// Scheduling. CONTRACT §4 fixes the per-tick order
// as "environment update -> observation -> output record". One single `initial`
// process drives the whole run: the analog steps, the `en`/`load_hi` update,
// and the CSV record happen in program order, so the ordering is structural
// rather than a delta-cycle accident. Nothing else writes `en`, `load_hi` or
// the model state, so there is no same-time race to resolve.
//
// per tick k, at t = k*100 ns:
//     N x step(h=DT)   advance exactly one tick of simulated time, using the
//                      en/load_hi in force for the interval being integrated
//     en/load_hi       environment input update for the new tick
//     record           observation of vout/vfb/vctrl/ipass/pg_cmp
//
// The `h` passed to `step()` is DT = 10 ns for the nominal run. `DT_PS` remains
// overridable for experiments; the DUT itself is step-size agnostic.
module rnm_core_tb;
    timeunit 1ns;
    timeprecision 1ps;

    // ---- scenario / setup, overridable by plusargs (nominal defaults) -------
    int  en_rise_ns   = 2000;    // CONTRACT §5 nominal: en rises at 2 us
    int  load_rise_ns = 25000;   // load_hi rises at 25 us
    int  load_fall_ns = 35000;   // load_hi falls at 35 us
    int  en_fall_ns   = 0;       // 0 means "never" (no disable event)
    int  end_ns       = 50000;   // 0 us .. 50 us
    int  dt_ps        = 10000;   // 10 ns
    string csv_path   = "rnm_core.csv";
    string full_path  = "rnm_core_full.csv";

    real dt_ns;
    real dt_s;
    int  steps_per_tick;
    int  ntick;

    logic en      = 1'b0;
    logic load_hi = 1'b0;

    real  vout, vfb, vctrl, ipass;
    logic pg_cmp;

    int  errors = 0;
    int  fd;
    int  full_fd;
    int  nan_or_inf = 0;
    int  bound_low  = 0;
    int  bound_high = 0;
    real worst_low  = 0.0;

    ldo_rnm u_ldo (
        .en      (en),
        .load_hi (load_hi),
        .vout    (vout),
        .vfb     (vfb),
        .vctrl   (vctrl),
        .ipass   (ipass),
        .pg_cmp  (pg_cmp)
    );

    // Environment stimulus. Event times are TB parameters; the DUT never sees
    // them. `en_fall_ns == 0` disables the disable event.
    function automatic logic env_en(input int t_ns);
        if (en_fall_ns != 0 && t_ns >= en_fall_ns) return 1'b0;
        return (t_ns >= en_rise_ns);
    endfunction

    function automatic logic env_lh(input int t_ns);
        return (t_ns >= load_rise_ns && t_ns < load_fall_ns);
    endfunction

    task automatic check(input logic cond, input string what);
        if (!cond) begin
            errors = errors + 1;
            $display("RNM_CORE_FAIL: %s", what);
        end
    endtask

    task automatic record_step();
        $fwrite(full_fd, "%.17g,%.17g,%.17g,%0d\n", $realtime, vout, vctrl, pg_cmp);
    endtask

    task automatic record(input int tick);
        real t_ns;
        t_ns = $realtime;                 // $realtime is in ns for this timeunit
        $fwrite(fd, "%0d,%0d,%0d,%0d,%.17g,%.17g,%.17g,%.17g,%0d\n",
                tick, tick*100, en, load_hi, vout, vfb, vctrl, ipass, pg_cmp);

        // structural self-check: tick k must land exactly on k*100 ns
        check($realtime == tick*100.0, "tick time is exactly tick*100 ns");

        // health (CONTRACT §6): no NaN/Inf, vout >= -1 uV, vout < 1.1 V
        if (vout != vout || vout > 1.0e30 || vout < -1.0e30) begin
            nan_or_inf = nan_or_inf + 1;
        end
        if (vout < -1.0e-6) begin
            bound_low = bound_low + 1;
            if (vout < worst_low) worst_low = vout;
        end
        if (vout >= 1.1) begin
            bound_high = bound_high + 1;
        end
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
        void'($value$plusargs("FULL_CSV=%s", full_path));
    endtask

    initial begin
        get_plusargs();
        dt_ns = dt_ps / 1000.0;                 // ns
        dt_s  = dt_ps * 1.0e-12;                // seconds, for the ODE
        steps_per_tick = 100000 / dt_ps;
        ntick = end_ns / 100;

        $display("RNM_CORE: dt_ps=%0d steps_per_tick=%0d ntick=%0d end_ns=%0d",
                 dt_ps, steps_per_tick, ntick, end_ns);
        $display("RNM_CORE: scenario en_rise=%0d load_rise=%0d load_fall=%0d en_fall=%0d",
                 en_rise_ns, load_rise_ns, load_fall_ns, en_fall_ns);

        check(steps_per_tick * dt_ps == 100000, "DT divides the 100 ns tick");
        check(end_ns % 100 == 0, "END_NS is a whole number of ticks");

        fd = $fopen(csv_path, "w");
        check(fd != 0, "CSV opened for writing");
        $fwrite(fd, "tick,time_ns,en,load_hi,vout,vfb,vctrl,ipass,pg_cmp\n");

        // Full step-resolution trajectory. The reference scalars (heavy-load
        // minimum, means, peak) are 10 ns-resolution values of the fixed-step
        // solver, so they can only be compared at the model's own step
        // resolution -- the 100 ns tick grid is coarser than the reference.
        full_fd = $fopen(full_path, "w");
        check(full_fd != 0, "full CSV opened for writing");
        $fwrite(full_fd, "time_ns,vout,vctrl,pg_cmp\n");

        // ---- cold start: initial condition, no integration yet -------------
        u_ldo.rst_state();
        en      = env_en(0);
        load_hi = env_lh(0);
        record(0);
        record_step();

        for (int k = 1; k <= ntick; k++) begin
            // environment update: advance the analog exactly one tick
            repeat (steps_per_tick) begin
                u_ldo.step(dt_s);
                #(dt_ns);
                record_step();
            end
            // environment input update for the new tick (before observation)
            en      = env_en(k*100);
            load_hi = env_lh(k*100);
            // observation / output record
            record(k);
        end

        $fclose(fd);
        $fclose(full_fd);

        $display("RNM_CORE: nan_or_inf=%0d bound_low=%0d boundary_violations=%0d worst_low=%.17g",
                 nan_or_inf, bound_low, bound_high, worst_low);

        check(nan_or_inf == 0, "no NaN/Inf in vout");
        check(bound_low == 0,  "vout never below -1 uV");
        check(bound_high == 0, "vout always below 1.1 V");
        check(errors == 0,     "no accumulated errors");

        if (errors != 0) $fatal(1, "RNM_CORE_FAIL errors=%0d", errors);
        $display("RNM_CORE_PASS");
        $finish;
    end
endmodule
