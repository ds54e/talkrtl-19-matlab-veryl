// Synchronous reset preamble initializes the supervisor without advancing analog time.
// One initial process owns clock, stimulus, and analog stepping.
module system_nominal_tb;
    timeunit 1ns;
    timeprecision 1ps;

    localparam int  CLK_HALF_NS       = 50;
    localparam int  PREAMBLE_TICKS    = 2;   // reset periods, excluded from compare
    localparam logic [1:0] ST_OFF  = 2'd0;
    localparam logic [1:0] ST_WAIT = 2'd1;
    localparam logic [1:0] ST_ON   = 2'd2;

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
    int  bad_state  = 0;

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
        if (cond !== 1'b1) begin
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

    task automatic record(input int tick);
        if (state !== ST_OFF && state !== ST_WAIT && state !== ST_ON) bad_state = bad_state + 1;
        $fwrite(fd, "%0d,%0d,%0d,%0d,%0d,%0d,%s,%0d,%.17g,%.17g,%.17g,%.17g,%0d,%.17g\n",
                tick, tick*100, rst, cap_en, cap_pg_cmp, state, state_name(state), pgood,
                cap_vout, cap_vfb, cap_vctrl, cap_ipass, cap_load_hi, $realtime);
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

        en      = env_en(0);
        load_hi = env_lh(0);
        capture();
        record(0);

        repeat (steps_per_tick) begin
            #(dt_ns);
            u_ldo.step(dt_s);
        end
        en      = env_en(100);
        load_hi = env_lh(100);
        clk     = 1'b1;

        for (int k = 1; k <= ntick; k++) begin
            capture();
            check($realtime == preamble_ns + k*100.0,
                  "observation instant is exactly preamble + k*100 ns");

            // Advance time before stepping so always_ff samples pg_cmp at T_k.
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

        check(bad_state == 0,  "state stayed in {OFF, WAIT, ON}");

        if (errors != 0) $fatal(1, "SYSTEM_NOMINAL_FAIL errors=%0d", errors);
        $display("SYSTEM_NOMINAL_PASS");
        $finish;
    end
endmodule
