module apb_system_tb;
    timeunit 1ns;
    timeprecision 1ps;

    localparam int DT_NS = 10;
    localparam int CLK_NS = 100;
    localparam int END_NS = 50000;

    logic clk = 1'b0;
    logic rst = 1'b0;
    wire rst_n = ~rst;
    logic load_hi = 1'b0;
    real vout, vfb, vctrl, ipass;
    logic pg_cmp, pgood, ctrl_en, cap_pg_cmp;
    logic [1:0] state;
    int analog_fd, digital_fd, sample_ns;
    bit status_read = 1'b0;

    rggen_apb_if #(3, 32) apb_if ();
    logic apb_start = 1'b0;
    logic apb_write = 1'b0;
    logic [2:0] apb_addr = '0;
    logic [31:0] apb_wdata = '0;
    logic [31:0] apb_rdata;
    logic apb_done;

    apb_master_bfm u_apb_master (
        .clk (clk), .rst_n (rst_n), .apb_bus (apb_if.master),
        .apb_start (apb_start), .apb_write (apb_write),
        .apb_addr (apb_addr), .apb_wdata (apb_wdata),
        .apb_rdata (apb_rdata), .apb_err (), .apb_done (apb_done)
    );
    ldo_csr u_csr (
        .i_clk (clk), .i_rst_n (rst_n), .apb_if (apb_if.slave),
        .o_ctrl_en (ctrl_en), .i_status_pgood (pgood)
    );
    ldo_rnm u_ldo (
        .en (ctrl_en), .load_hi (load_hi), .vout (vout), .vfb (vfb),
        .vctrl (vctrl), .ipass (ipass), .pg_cmp (pg_cmp)
    );
    // The supervisor samples CTRL.EN one clock later; the reference mirrors
    // this with its en_reg Unit Delay.
    pgood_supervisor u_sup (
        .clk (clk), .rst (rst), .en (ctrl_en), .pg_cmp (pg_cmp),
        .pgood (pgood), .state (state)
    );

    task automatic record_digital(input int n);
        $fwrite(digital_fd, "%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d\n",
                n, n * CLK_NS, rst, ctrl_en, cap_pg_cmp, state, pgood, load_hi);
    endtask

    // Active-region model/comparator work settles before NBA clock/load changes;
    // the supervisor then samples pg_cmp, and CSR NBAs affect the next step.
    initial begin
        repeat (2) begin
            #50 clk <= 1'b1;
            #50 clk <= 1'b0;
        end
        #50;
        forever #50 clk <= ~clk;
    end

    always @(posedge clk) cap_pg_cmp = pg_cmp;

    // Clock edges since scenario time zero (the end of reset).
    int tick = 0;
    always @(posedge clk) if (!rst) tick <= tick + 1;

    // Wait for the falling edge in the middle of tick n.
    task automatic mid_tick(input int n);
        wait (tick == n);
        @(negedge clk);
    endtask

    initial begin
        rst <= 1'b1;
        #200 rst <= 1'b0; // Scenario time zero; en=0 keeps analog derivatives zero.

        // APB setup + access phases raise CTRL.EN at tick 20 (2 us).
        mid_tick(18);
        apb_start = 1'b1;
        apb_write = 1'b1;
        apb_addr = 3'h0; // CTRL.EN
        apb_wdata = 32'h1;
        @(negedge clk) apb_start = 1'b0;

        mid_tick(200);
        if (ctrl_en !== 1'b1 || vout < 0.87 || pgood !== 1'b1)
            $fatal(1, "APB_SYSTEM_FAIL: CTRL.EN write did not enable the LDO");
        $display("APB_SYSTEM: CTRL.EN write enabled the LDO and PGOOD");
        apb_start = 1'b1;
        apb_write = 1'b0;
        apb_addr = 3'h4; // STATUS.PGOOD
        @(negedge clk) apb_start = 1'b0;
    end

    initial begin
        #200;
        #25000 load_hi <= 1'b1;
        #10000 load_hi <= 1'b0;
    end

    always @(negedge clk) begin
        if (apb_done && !apb_write) begin
            if (apb_rdata[0] !== pgood)
                $fatal(1, "APB_SYSTEM_FAIL: STATUS.PGOOD does not match pgood");
            $display("APB_SYSTEM: STATUS.PGOOD read matches pgood=%0d", pgood);
            status_read = 1'b1;
        end
    end

    initial begin
        analog_fd = $fopen("analog.csv", "w");
        $fwrite(analog_fd, "time_ns,vout,vfb,vctrl,ipass,pg_cmp,en,load_hi\n");
        #200;
        for (int t_ns = 0; t_ns <= END_NS; t_ns += DT_NS) begin
            sample_ns = t_ns;
            $fstrobe(analog_fd, "%0d,%.17g,%.17g,%.17g,%.17g,%0d,%0d,%0d",
                     sample_ns, vout, vfb, vctrl, ipass, pg_cmp, ctrl_en, load_hi);
            #DT_NS;
        end
    end

    initial begin
        digital_fd = $fopen("digital.csv", "w");
        $fwrite(digital_fd, "tick,time_ns,rst,en,pg_cmp,state,pgood,load_hi\n");
        @(negedge rst);
        record_digital(0);
        #150;
        for (int n = 1; n <= END_NS / CLK_NS; n++) begin
            record_digital(n);
            if (n < END_NS / CLK_NS) #CLK_NS;
        end

        $fclose(analog_fd);
        $fclose(digital_fd);
        if (!status_read)
            $fatal(1, "APB_SYSTEM_FAIL: STATUS.PGOOD read never completed");
        $display("APB_SYSTEM: reached tick %0d (50 us)", END_NS / CLK_NS);
        $display("APB_SYSTEM_PASS");
        $finish;
    end
endmodule
