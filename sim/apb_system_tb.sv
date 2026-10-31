// Generated CSR drives en through the real APB path; CSR latency is not time-shifted away.
// One initial process owns clock, environment, and analog stepping.
module apb_system_tb;
    timeunit 1ns;
    timeprecision 1ps;

    localparam int  CLK_HALF_NS    = 50;
    localparam int  PREAMBLE_TICKS = 2;
    // CONTRACT APBレジスタ
    localparam logic [2:0] CTRL_ADDR   = 3'h0;   // 0x00 CTRL.EN[0]      RW
    localparam logic [2:0] STATUS_ADDR = 3'h4;   // 0x04 STATUS.PGOOD[0] RO, live

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
    int k_write_started     = -1;
    int k_ctrl_en_high      = -1;

    // captured at the observation instant
    real  cap_vout;
    logic cap_pg_cmp;
    logic cap_pgood;
    logic cap_ctrl_en;
    logic cap_load_hi;

    rggen_apb_if #(3, 32) apb_if ();

    logic        apb_start = 1'b0;
    logic        apb_write = 1'b0;
    logic [2:0]  apb_addr  = '0;
    logic [31:0] apb_wdata = '0;

    logic [31:0] apb_rdata;
    logic        apb_err;
    logic        apb_done;
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

    ldo_csr u_csr (
        .i_clk          (clk),
        .i_rst_n        (rst_n),
        .i_psel         (apb_if.psel),
        .i_penable      (apb_if.penable),
        .i_paddr        (apb_if.paddr),
        .i_pprot        (apb_if.pprot),
        .i_pwrite       (apb_if.pwrite),
        .i_pstrb        (apb_if.pstrb),
        .i_pwdata       (apb_if.pwdata),
        .o_pready       (apb_if.pready),
        .o_prdata       (apb_if.prdata),
        .o_pslverr      (apb_if.pslverr),
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

    function automatic logic env_lh(input int t_ns);
        return (t_ns >= load_rise_ns && t_ns < load_fall_ns);
    endfunction

    task automatic check(input logic cond, input string what);
        if (cond !== 1'b1) begin
            errors = errors + 1;
            $display("APB_SYSTEM_FAIL: %s", what);
        end
    endtask

    // Sample clocked outputs mid-tick so NBA updates from the rising edge are visible.
    task automatic capture();
        cap_vout    = vout;
        cap_pg_cmp  = pg_cmp;
        cap_load_hi = load_hi;
    endtask

    task automatic record(input int tick);
        $fwrite(fd, "%0d,%0d,%0d,%0d,%0d,%0d,%0d,%.17g\n",
                tick, tick * 100, cap_ctrl_en, cap_load_hi, cap_pg_cmp, pgood, state, cap_vout);
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

    task automatic tick_body();
        capture();
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

    task automatic advance_tick();
        if (cur_tick == ntick) return;
        load_hi  = env_lh((cur_tick + 1) * 100);
        clk      = 1'b1;
        cur_tick = cur_tick + 1;
        tick_body();
    endtask

    localparam int APB_MAX_TICKS = 32;

    // Bound each APB wait so a missing response cannot spin forever at the final tick.
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
            // Latch the first ctrl_en-high tick; it may precede pready completion.
            if (k_ctrl_en_high < 0 && cap_ctrl_en === 1'b1) k_ctrl_en_high = cur_tick;
        end
        rdata = apb_rdata_s;
        err   = apb_err_s;
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

    task automatic wait_ctrl_en(input logic level);
        while (cap_ctrl_en !== level && cur_tick < limit_tick) advance_tick();
    endtask

    task automatic wait_pgood(input logic level);
        while (cap_pgood !== level && cur_tick < limit_tick) advance_tick();
    endtask

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

        u_ldo.rst_state();
        rst     = 1'b1;
        load_hi = 1'b0;
        clk     = 1'b0;
        repeat (PREAMBLE_TICKS) begin
            #(CLK_HALF_NS) clk = 1'b1;
            #(CLK_HALF_NS) clk = 1'b0;
        end
        rst = 1'b0;
        check(ctrl_en === 1'b0, "o_ctrl_en is 0 after reset (CTRL.EN reset value)");

        // tick 0: pure initial observation, no rising edge yet
        capture();
        cap_ctrl_en = ctrl_en;
        cap_pgood = pgood;
        record(0);
        repeat (steps_per_tick) begin
            #(dt_ns);
            u_ldo.step(dt_s);
        end
        advance_tick();                        // first rising edge -> tick 1

        apb_read_reg(CTRL_ADDR, rd);
        check(rd[0] === 1'b0, "APB read of CTRL.EN returns 0 after reset");

        while (cur_tick < en_write_tick) advance_tick();

        k_write_started = cur_tick;
        apb_write_reg(CTRL_ADDR, 32'h1);

        wait_ctrl_en(1'b1);
        check(cap_ctrl_en === 1'b1, "APB write CTRL.EN=1 drives o_ctrl_en high");

        wait_pgood(1'b1);
        check(cap_pgood === 1'b1, "PGOOD asserted after the CSR-enabled startup");
        apb_read_reg(STATUS_ADDR, rd);
        check(rd[0] === 1'b1, "APB read of STATUS.PGOOD returns 1 after startup");

        while (load_hi !== 1'b1 && cur_tick < limit_tick) advance_tick();
        wait_pgood(1'b0);
        check(cap_pgood === 1'b0, "PGOOD dropped after the heavy-load step");
        apb_read_reg(STATUS_ADDR, rd);
        check(rd[0] === 1'b0, "APB read of STATUS.PGOOD returns 0 after the load step");

        wait_pgood(1'b1);
        check(cap_pgood === 1'b1, "PGOOD requalified once the comparator was High again");
        apb_read_reg(STATUS_ADDR, rd);
        check(rd[0] === 1'b1, "APB read of STATUS.PGOOD returns 1 after requalification");

        while (cur_tick < ntick) advance_tick();
        $fclose(fd);

        $display("APB_SYSTEM: write_tick=%0d ctrl_en_high_tick=%0d",
                 k_write_started, k_ctrl_en_high);
        check(k_ctrl_en_high - k_write_started >= 1,
              "o_ctrl_en follows the APB write by at least one clock edge (real CSR latency)");


        if (errors != 0) $fatal(1, "APB_SYSTEM_FAIL errors=%0d", errors);
        $display("APB_SYSTEM_PASS");
        $finish;
    end
endmodule
