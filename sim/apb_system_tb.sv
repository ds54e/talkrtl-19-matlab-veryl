// apb_system_tb -- integrated system: RgGen CSR + SV-RNM LDO + Veryl supervisor.
//
//     APB write --> ldo_csr.o_ctrl_en --> ldo_rnm.en --> pgood_supervisor.en
//                         ^                                      |
//                         |                              pgood   |
//                         +------ i_status_pgood <----------------+
//     ldo_rnm.pg_cmp ----------> pgood_supervisor.pg_cmp
//
// The CSR is the real generated artifact `rtl/generated/rggen/ldo_csr.sv`
// (RgGen 0.36), compiled against the vendored RgGen runtime RTL in
// `third_party/rggen-sv-rtl/`. There is no hand-written register model here: the
// testbench drives the real `rggen_apb_if` and observes the real generated ports.
// `en` is wired to the CSR output only -- the RNM and the supervisor are never
// enabled by the testbench, so the LDO can start only because an APB write
// reached `CTRL.EN`.
//
// Honest latency: `o_ctrl_en` is a register inside the CSR, so `en` changes one or
// more clock edges after the APB transfer. The APB run is therefore the same
// nominal scenario started an integer number of 100 ns ticks later than the
// direct-control run in `sim/system_nominal_tb.sv`. The measured enable latency
// is printed and checked to be non-zero; nothing is time-shifted to hide it. This
// testbench is deliberately NOT the source of the 501-tick exact comparison --
// that stays on the direct-control testbench.
//
// APB master: 2-phase SETUP/ACCESS with a wait state, in sim/apb_master_bfm.sv.
// `pready` is the adapter's registered output, so it is sampled on the following
// rising edge. Clocked values are read 50 ns after a rising edge (the sampling
// point the other testbenches use), never in the same time step as the edge.
//
// The CSV records the APB-enabled run at tick resolution
// (tick,time_ns,ctrl_en,load_hi,pg_cmp,pgood,state,vout).
//
// Scheduling is the same single-process scheme as system_nominal_tb.sv: one
// `initial` block owns the clock, the environment and the analog stepping, so the
// per-tick order (environment update -> observation -> record) is fixed by
// program order.
//
// exit marker: APB_SYSTEM_PASS
module apb_system_tb;
    timeunit 1ns;
    timeprecision 1ps;

    localparam int  CLK_HALF_NS    = 50;
    localparam int  PREAMBLE_TICKS = 2;
    localparam logic [1:0] ST_OFF  = 2'd0;
    localparam logic [1:0] ST_WAIT = 2'd1;
    localparam logic [1:0] ST_ON   = 2'd2;

    // CONTRACT section 7 register map
    localparam logic [2:0] CTRL_ADDR   = 3'h0;   // 0x00 CTRL.EN[0]      RW
    localparam logic [2:0] STATUS_ADDR = 3'h4;   // 0x04 STATUS.PGOOD[0] RO, live

    // ---- scenario -----------------------------------------------------------
    int  en_rise_ns   = 2000;      // scenario enable time
    int  load_rise_ns = 25000;
    int  load_fall_ns = 35000;
    int  end_ns       = 50000;
    int  dt_ps        = 10000;
    int  apb_lead_ns  = 200;       // APB write is issued this long before enable
    string csv_path   = "apb_system.csv";

    real dt_ns;
    real dt_s;
    int  steps_per_tick;
    int  half_steps;
    int  ntick;
    real preamble_ns = 0.0;
    int  cur_tick    = 0;
    int  limit_tick  = 0;

    logic clk = 1'b0;
    logic rst = 1'b0;              // supervisor reset, active high
    logic rst_n;                   // CSR reset, active low
    assign rst_n = ~rst;

    logic load_hi = 1'b0;

    real  vout, vfb, vctrl, ipass;
    logic pg_cmp;
    logic pgood;
    logic [1:0] state;
    logic ctrl_en;                 // ldo_csr.o_ctrl_en -- the only source of `en`

    int errors    = 0;
    int fd;
    int nan_or_inf = 0;
    int bound_low  = 0;
    int bound_high = 0;
    int bad_state  = 0;
    int apb_ops    = 0;
    int apb_errors = 0;

    int k_write_started     = -1;
    int k_ctrl_en_high      = -1;
    int k_pg_cmp_first_high = -1;
    int k_pgood_first_high  = -1;

    // captured at the observation instant
    real  cap_vout;
    logic cap_pg_cmp;
    logic cap_pgood;
    logic cap_ctrl_en;
    logic cap_load_hi;

    // ---- APB master ---------------------------------------------------------
    // The SETUP/ACCESS state machine and the APB signal driving live in
    // sim/apb_master_bfm.sv. This testbench only sets a request and waits for the
    // BFM's `apb_done` while it advances ticks (see apb_op).
    rggen_apb_if #(3, 32) apb_if ();

    logic        apb_start = 1'b0;
    logic        apb_write = 1'b0;
    logic [2:0]  apb_addr  = '0;
    logic [31:0] apb_wdata = '0;

    // BFM outputs: the BFM is their only driver, so they carry no initializer here.
    logic [31:0] apb_rdata;
    logic        apb_err;
    logic        apb_done;
    // sampled by the owning process 50 ns after an edge
    logic [31:0] apb_rdata_s = '0;
    logic        apb_err_s   = 1'b0;
    logic        apb_done_s  = 1'b0;

    apb_master_bfm u_apb_master (
        .clk       (clk),
        .rst_n     (rst_n),
        .apb_bus   (apb_if.master),
        .apb_start (apb_start),
        .apb_write (apb_write),
        .apb_addr  (apb_addr),
        .apb_wdata (apb_wdata),
        .apb_rdata (apb_rdata),
        .apb_err   (apb_err),
        .apb_done  (apb_done)
    );

    // ---- DUTs ---------------------------------------------------------------
    ldo_csr u_csr (
        .i_clk          (clk),
        .i_rst_n        (rst_n),
        .apb_if         (apb_if),
        .o_ctrl_en      (ctrl_en),
        .i_status_pgood (pgood)
    );

    ldo_rnm u_ldo (
        .en      (ctrl_en),
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
        .en     (ctrl_en),
        .pg_cmp (pg_cmp),
        .pgood  (pgood),
        .state  (state)
    );

    // ---- helpers ------------------------------------------------------------
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
            $display("APB_SYSTEM_FAIL: %s", what);
        end
    endtask

    // The analog state and the comparator output are read at the observation
    // instant -- those are exactly the values the supervisor samples at that edge.
    // Clocked DUT outputs (`ctrl_en`, `pgood`) are read at the mid-tick point
    // instead: an NBA updated at a rising edge is not guaranteed to be visible to
    // this process in the same time step, and reading it there lags by one tick.
    task automatic capture();
        cap_vout    = vout;
        cap_pg_cmp  = pg_cmp;
        cap_load_hi = load_hi;
    endtask

    task automatic record(input int tick);
        if (state !== ST_OFF && state !== ST_WAIT && state !== ST_ON) bad_state = bad_state + 1;
        $fwrite(fd, "%0d,%0d,%0d,%0d,%0d,%0d,%0d,%.17g\n",
                tick, tick * 100, cap_ctrl_en, cap_load_hi, cap_pg_cmp, pgood, state, cap_vout);
        if (cap_vout != cap_vout || cap_vout > 1.0e30 || cap_vout < -1.0e30) nan_or_inf = nan_or_inf + 1;
        if (cap_vout < -1.0e-6) bound_low = bound_low + 1;
        if (cap_vout >= 1.1) bound_high = bound_high + 1;
    endtask

    task automatic get_plusargs();
        int v;
        if ($value$plusargs("EN_RISE_NS=%d",   v)) en_rise_ns   = v;
        if ($value$plusargs("LOAD_RISE_NS=%d", v)) load_rise_ns = v;
        if ($value$plusargs("LOAD_FALL_NS=%d", v)) load_fall_ns = v;
        if ($value$plusargs("END_NS=%d",       v)) end_ns       = v;
        if ($value$plusargs("DT_PS=%d",        v)) dt_ps        = v;
        void'($value$plusargs("CSV=%s", csv_path));
    endtask

    // ---- one tick -----------------------------------------------------------
    // Observation instant of `cur_tick` first (analog state and sampled inputs
    // exactly as the supervisor sees them), then the two integration halves with
    // the falling edge and the output record in between.
    task automatic tick_body();
        capture();
        check($realtime == preamble_ns + cur_tick * 100.0,
              "observation instant is exactly preamble + k*100 ns");
        repeat (half_steps) begin
            #(dt_ns);
            u_ldo.step(dt_s);
        end
        clk = 1'b0;
        cap_ctrl_en = ctrl_en;
        cap_pgood   = pgood;
        record(cur_tick);
        apb_done_s  = apb_done;
        apb_rdata_s = apb_rdata;
        apb_err_s   = apb_err;
        repeat (half_steps) begin
            #(dt_ns);
            u_ldo.step(dt_s);
        end
    endtask

    // Take the next rising edge and observe the resulting tick. `load_hi` is the
    // only environment input the testbench still drives: `en` belongs to the CSR.
    task automatic advance_tick();
        if (cur_tick == ntick) return;
        load_hi  = env_lh((cur_tick + 1) * 100);
        clk      = 1'b1;
        cur_tick = cur_tick + 1;
        tick_body();
    endtask

    // ---- APB transfers ------------------------------------------------------
    // Upper bound on how long one transfer may take before the run is aborted.
    // This is a limit for this demo scenario, not an APB protocol limit.
    localparam int APB_MAX_TICKS = 32;

    // Advance one tick for an in-flight transfer, refusing to step past either the
    // per-transfer budget or the end of the scenario. Without this, a transfer that
    // never completes spins in zero time: advance_tick() returns without advancing
    // once cur_tick == ntick. The check runs before every step, including the first
    // one, so a response that lands on the last allowed tick is still accepted.
    task automatic apb_tick_or_fail(input int start_tick, input logic wr, input logic [2:0] addr);
        if (cur_tick + 1 - start_tick > APB_MAX_TICKS || cur_tick + 1 > ntick) begin
            $fatal(1, "APB_TIMEOUT: %s addr=%0d start_tick=%0d cur_tick=%0d budget_ticks=%0d ntick=%0d, no apb_done",
                   wr ? "write" : "read", addr, start_tick, cur_tick, APB_MAX_TICKS, ntick);
        end
        advance_tick();
    endtask

    task automatic apb_op(input logic wr, input logic [2:0] addr, input logic [31:0] wdata,
                          output logic [31:0] rdata, output logic err);
        int start_tick;
        start_tick = cur_tick;
        apb_write = wr;
        apb_addr  = addr;
        apb_wdata = wdata;
        apb_start = 1'b1;
        apb_tick_or_fail(start_tick, wr, addr); // edge: the master leaves IDLE
        apb_start = 1'b0;
        while (!apb_done_s) begin              // SETUP -> ACCESS -> pready
            apb_tick_or_fail(start_tick, wr, addr);
            // A write can take effect one edge before `pready` completes, so latch
            // the first tick at which the CSR output is high instead of assuming it.
            if (k_ctrl_en_high < 0 && cap_ctrl_en === 1'b1) k_ctrl_en_high = cur_tick;
        end
        rdata = apb_rdata_s;
        err   = apb_err_s;
        apb_ops = apb_ops + 1;
        if (err) apb_errors = apb_errors + 1;
    endtask

    task automatic apb_write_reg(input logic [2:0] addr, input logic [31:0] data);
        logic [31:0] rdata;
        logic        err;
        apb_op(1'b1, addr, data, rdata, err);
        check(err === 1'b0, $sformatf("APB write addr=%0d completes without slave error", addr));
    endtask

    task automatic apb_read_reg(input logic [2:0] addr, output logic [31:0] data);
        logic err;
        apb_op(1'b0, addr, '0, data, err);
        check(err === 1'b0, $sformatf("APB read addr=%0d completes without slave error", addr));
    endtask

    // ---- bounded, event-driven waits (a failure cannot hang the run) --------
    task automatic wait_ctrl_en(input logic level);
        while (cap_ctrl_en !== level && cur_tick < limit_tick) advance_tick();
    endtask

    task automatic wait_pg_cmp(input logic level);
        while (cap_pg_cmp !== level && cur_tick < limit_tick) advance_tick();
    endtask

    task automatic wait_pgood(input logic level);
        while (cap_pgood !== level && cur_tick < limit_tick) advance_tick();
    endtask

    // ---- run ----------------------------------------------------------------
    logic [31:0] rd;
    int          en_write_tick;

    initial begin
        get_plusargs();
        dt_ns = dt_ps / 1000.0;
        dt_s  = dt_ps * 1e-12;
        steps_per_tick = 100000 / dt_ps;
        half_steps     = steps_per_tick / 2;
        ntick          = end_ns / 100;
        preamble_ns    = PREAMBLE_TICKS * 100.0;
        limit_tick     = ntick - 10;
        en_write_tick  = (en_rise_ns - apb_lead_ns) / 100;

        $display("APB_SYSTEM: dt_ps=%0d steps_per_tick=%0d ntick=%0d preamble_ns=%0.0f",
                 dt_ps, steps_per_tick, ntick, preamble_ns);
        $display("APB_SYSTEM: scenario en_rise=%0d load_rise=%0d load_fall=%0d apb_write_tick=%0d",
                 en_rise_ns, load_rise_ns, load_fall_ns, en_write_tick);
        check(steps_per_tick % 2 == 0, "steps per tick splits into two halves");
        check(en_write_tick > 0, "APB write is scheduled after the reset preamble");

        fd = $fopen(csv_path, "w");
        check(fd != 0, "CSV opened for writing");
        $fwrite(fd, "tick,time_ns,ctrl_en,load_hi,pg_cmp,pgood,state,vout\n");

        // ---- analog cold start + reset preamble -----------------------------
        u_ldo.rst_state();
        rst     = 1'b1;
        load_hi = 1'b0;
        clk     = 1'b0;
        repeat (PREAMBLE_TICKS) begin
            #(CLK_HALF_NS) clk = 1'b1;
            #(CLK_HALF_NS) clk = 1'b0;
        end
        rst = 1'b0;
        check(state === ST_OFF && pgood === 1'b0,
              "supervisor reaches OFF/pgood=0 after the reset preamble");
        check(ctrl_en === 1'b0, "o_ctrl_en is 0 after reset (CTRL.EN reset value)");

        // tick 0: pure initial observation, no rising edge yet
        capture();
        record(0);
        repeat (steps_per_tick) begin
            #(dt_ns);
            u_ldo.step(dt_s);
        end
        advance_tick();                        // first rising edge -> tick 1

        // ---- CTRL.EN = 0 after reset, through the real APB path --------------
        apb_read_reg(CTRL_ADDR, rd);
        check(rd[0] === 1'b0, "APB read of CTRL.EN returns 0 after reset");

        // ---- run disabled up to the APB write --------------------------------
        while (cur_tick < en_write_tick) advance_tick();
        check(cap_ctrl_en === 1'b0, "CTRL.EN is still 0 before the APB write");
        check(cap_vout < 0.01, "vout stays near 0 while CTRL.EN is 0");
        check(cap_pgood === 1'b0, "PGOOD stays 0 while CTRL.EN is 0");
        check(cap_pg_cmp === 1'b0, "pg_cmp stays 0 while CTRL.EN is 0");

        // ---- APB write CTRL.EN = 1 ------------------------------------------
        // `k_ctrl_en_high` is latched by apb_op while the transfer is running, so
        // the reported latency is the first tick the CSR output was high rather
        // than the tick the transfer happened to finish on.
        k_write_started = cur_tick;
        apb_write_reg(CTRL_ADDR, 32'h1);

        wait_ctrl_en(1'b1);
        check(cap_ctrl_en === 1'b1, "APB write CTRL.EN=1 drives o_ctrl_en high");

        // ---- startup only through that CSR output ----------------------------
        wait_pg_cmp(1'b1);
        check(cap_pg_cmp === 1'b1, "pg_cmp rises after the CSR-enabled startup");
        k_pg_cmp_first_high = cur_tick;
        check(cap_vout > 0.87, "vout reached the comparator upper threshold through the CSR output");

        // ---- PGOOD, read back through APB -----------------------------------
        wait_pgood(1'b1);
        check(cap_pgood === 1'b1, "PGOOD asserted after the CSR-enabled startup");
        k_pgood_first_high = cur_tick;
        apb_read_reg(STATUS_ADDR, rd);
        check(rd[0] === 1'b1, "APB read of STATUS.PGOOD returns 1 after startup");

        // ---- load transient: PGOOD must drop, visible through APB ------------
        while (load_hi !== 1'b1 && cur_tick < limit_tick) advance_tick();
        check(load_hi === 1'b1, "heavy-load stimulus asserted at the scenario time");
        wait_pg_cmp(1'b0);
        check(cap_pg_cmp === 1'b0, "pg_cmp fell after the heavy-load step");
        wait_pgood(1'b0);
        check(cap_pgood === 1'b0, "PGOOD dropped after the heavy-load step");
        apb_read_reg(STATUS_ADDR, rd);
        check(rd[0] === 1'b0, "APB read of STATUS.PGOOD returns 0 after the load step");

        // ---- requalification after the comparator recovers -------------------
        wait_pg_cmp(1'b1);
        wait_pgood(1'b1);
        check(cap_pgood === 1'b1, "PGOOD requalified once the comparator was High again");
        apb_read_reg(STATUS_ADDR, rd);
        check(rd[0] === 1'b1, "APB read of STATUS.PGOOD returns 1 after requalification");

        // ---- load released: PGOOD stays up ----------------------------------
        while (cur_tick * 100 < load_fall_ns + 2000 && cur_tick < limit_tick) advance_tick();
        check(cap_load_hi === 1'b0, "heavy-load stimulus released at the scenario time");
        check(cap_pgood === 1'b1, "PGOOD stays high after the load is released");
        apb_read_reg(STATUS_ADDR, rd);
        check(rd[0] === 1'b1, "APB read of STATUS.PGOOD returns 1 after the load was released");

        // ---- run out the scenario -------------------------------------------
        while (cur_tick < ntick) advance_tick();
        check(cap_ctrl_en === 1'b1, "CTRL.EN stays 1 for the rest of the run");
        check(cap_pgood === 1'b1, "PGOOD is 1 at the end of the scenario");

        $fclose(fd);

        $display("APB_SYSTEM: apb_ops=%0d apb_errors=%0d write_tick=%0d ctrl_en_high_tick=%0d pg_cmp_first_high_tick=%0d pgood_first_high_tick=%0d",
                 apb_ops, apb_errors, k_write_started, k_ctrl_en_high,
                 k_pg_cmp_first_high, k_pgood_first_high);
        $display("APB_SYSTEM: en_latency_after_apb_write_ticks=%0d qualification_intervals=%0d (want 20)",
                 k_ctrl_en_high - k_write_started, k_pgood_first_high - k_pg_cmp_first_high);
        check(k_ctrl_en_high - k_write_started >= 1,
              "o_ctrl_en follows the APB write by at least one clock edge (real CSR latency)");
        check(k_pgood_first_high - k_pg_cmp_first_high == 20,
              "PGOOD follows the first High observation by 20 intervals");

        $display("APB_SYSTEM: nan_or_inf=%0d bound_low=%0d boundary_violations=%0d bad_state=%0d",
                 nan_or_inf, bound_low, bound_high, bad_state);
        check(nan_or_inf == 0, "no NaN/Inf in vout");
        check(bound_low == 0,  "vout never below -1 uV");
        check(bound_high == 0, "vout always below 1.1 V");
        check(bad_state == 0,  "state stayed in {OFF, WAIT, ON}");

        if (errors != 0) $fatal(1, "APB_SYSTEM_FAIL errors=%0d", errors);
        $display("APB_SYSTEM_PASS");
        $finish;
    end
endmodule
