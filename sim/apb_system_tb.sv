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
    logic pg_cmp, pgood, ctrl_en;
    logic [1:0] state;
    int fd, sample_ns;
    bit status_read = 1'b0;

    localparam logic [2:0] CTRL = 3'h0, STATUS = 3'h4;
    rggen_apb_if #(3, 32) apb_if ();

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

    // Clock edges since scenario time zero (the end of reset).
    int tick = 0;
    always @(posedge clk) if (!rst) tick <= tick + 1;

    // Wait for the falling edge in the middle of tick n.
    task automatic mid_tick(input int n);
        wait (tick == n);
        @(negedge clk);
    endtask

    // One APB transfer: setup phase, then access phase until PREADY.
    task automatic apb_access(input logic write, input logic [2:0] addr,
                              input logic [31:0] wdata, output logic [31:0] rdata);
        @(posedge clk);
        apb_if.psel    <= 1'b1;
        apb_if.penable <= 1'b0;
        apb_if.pwrite  <= write;
        apb_if.paddr   <= addr;
        apb_if.pwdata  <= wdata;
        apb_if.pstrb   <= '1;
        apb_if.pprot   <= '0;
        @(posedge clk);
        apb_if.penable <= 1'b1;
        do @(posedge clk); while (!apb_if.pready);
        rdata = apb_if.prdata;
        apb_if.psel    <= 1'b0;
        apb_if.penable <= 1'b0;
    endtask

    initial begin
        logic [31:0] rdata;
        apb_if.psel = 1'b0;
        apb_if.penable = 1'b0;
        rst <= 1'b1;
        #200 rst <= 1'b0; // Scenario time zero; en=0 keeps analog derivatives zero.

        // The APB setup and access phases raise CTRL.EN at tick 20 (2 us).
        mid_tick(18);
        apb_access(1'b1, CTRL, 32'h1, rdata);

        mid_tick(200);
        if (ctrl_en !== 1'b1 || vout < 0.87 || pgood !== 1'b1)
            $fatal(1, "APB_SYSTEM_FAIL: CTRL.EN write did not enable the LDO");
        $display("APB_SYSTEM: CTRL.EN write enabled the LDO and PGOOD");
        apb_access(1'b0, STATUS, '0, rdata);
        if (rdata[0] !== pgood)
            $fatal(1, "APB_SYSTEM_FAIL: STATUS.PGOOD does not match pgood");
        $display("APB_SYSTEM: STATUS.PGOOD read matches pgood=%0d", pgood);
        status_read = 1'b1;
    end

    initial begin
        #200;
        #25000 load_hi <= 1'b1;
        #10000 load_hi <= 1'b0;
    end

    // Every signal every 10 ns, written at the end of the time slot.
    initial begin
        fd = $fopen("signals.csv", "w");
        $fwrite(fd, "time_ns,vout,vfb,vctrl,ipass,pg_cmp,en,load_hi,rst,state,pgood\n");
        #200;
        for (int t_ns = 0; t_ns <= END_NS; t_ns += DT_NS) begin
            sample_ns = t_ns;
            $fstrobe(fd, "%0d,%.17g,%.17g,%.17g,%.17g,%0d,%0d,%0d,%0d,%0d,%0d", sample_ns,
                     vout, vfb, vctrl, ipass, pg_cmp, ctrl_en, load_hi, rst, state, pgood);
            #DT_NS;
        end
        $fclose(fd);
        if (!status_read)
            $fatal(1, "APB_SYSTEM_FAIL: STATUS.PGOOD read never completed");
        $display("APB_SYSTEM: reached %0d us", END_NS / 1000);
        $display("APB_SYSTEM_PASS");
        $finish;
    end
endmodule
