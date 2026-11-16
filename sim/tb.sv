module tb;
    timeunit 1ns; timeprecision 1ps;

    localparam int T0 = 200;        // scenario time zero, after reset
    localparam int DT_NS = 10;      // CSV sample interval
    localparam int CLK_NS = 100;
    localparam int END_NS = 50000;

    logic clk = 1'b1;
    logic rst = 1'b0;
    wire rst_n = ~rst;
    logic load_hi = 1'b0;
    logic pg_cmp, pgood, ctrl_en;
    logic [1:0] state;
    import udn_pkg::enet;
    enet vin, vout, sw;
    int fd;
    bit status_read = 1'b0;

    localparam logic [2:0] CTRL = 3'h0, STATUS = 3'h4;
    rggen_apb_if #(3, 32) apb_if ();

    ldo_csr u_csr (
        .i_clk (clk), .i_rst_n (rst_n), .apb_if (apb_if.slave),
        .o_ctrl_en (ctrl_en), .i_status_pgood (pgood)
    );
    ldo u_ldo (.vin (vin), .vout (vout), .en (ctrl_en), .pg_cmp (pg_cmp));
    // The supervisor samples CTRL.EN one clock later; the reference mirrors
    // this with its en_reg Unit Delay.
    pgood_supervisor u_sup (
        .clk (clk), .rst (rst), .en (ctrl_en), .pg_cmp (pg_cmp),
        .pgood (pgood), .state (state)
    );

    // Board: the 1.2 V supply, Cout and the load. While load_hi, Rheavy is in
    // parallel with Rload: 1.8 k || 360 = 300 ohm.
    vsrc  #(.V(1.2))                      supply (.p(vin));
    cap_g #(.C(10.0e-9))                  cout   (.p(vout));
    res_g #(.R(1.8e3))                    rload  (.p(vout));
    res   #(.R(360.0))                    rheavy (.p(vout), .n(sw));
    sw_g  #(.RON(1.0e-6), .GOFF(1.0e-12)) swh    (.on(load_hi), .p(sw));

    // Rising edges at every multiple of CLK_NS.
    always #(CLK_NS / 2) clk <= ~clk;

    // Wait for the middle of clock period n of the scenario.
    task automatic mid_tick(input int n);
        #(T0 + CLK_NS * n + CLK_NS / 2 - $time);
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
        #150 rst <= 1'b0; // After the reset edge at 100 ns.

        // The APB setup and access phases raise CTRL.EN at tick 20 (2 us).
        mid_tick(18);
        apb_access(1'b1, CTRL, 32'h1, rdata);

        mid_tick(200);
        if (ctrl_en !== 1'b1 || vout.V < 0.87 || pgood !== 1'b1)
            $fatal(1, "TB_FAIL: CTRL.EN write did not enable the LDO");
        $display("TB: CTRL.EN write enabled the LDO and PGOOD");
        apb_access(1'b0, STATUS, '0, rdata);
        if (rdata[0] !== pgood)
            $fatal(1, "TB_FAIL: STATUS.PGOOD does not match pgood");
        $display("TB: STATUS.PGOOD read matches pgood=%0d", pgood);
        status_read = 1'b1;
    end

    initial begin
        #(T0 + 25000) load_hi <= 1'b1;
        #10000 load_hi <= 1'b0;
    end

    // Every signal every 10 ns, written at the end of the time slot; vfb,
    // vctrl and ipass are inside the chip.
    initial begin
        fd = $fopen("signals.csv", "w");
        $fwrite(fd, "time_ns,vout,vfb,vctrl,ipass,pg_cmp,en,load_hi,rst,state,pgood\n");
        #T0;
        repeat (END_NS / DT_NS + 1) begin
            $fstrobe(fd, "%0d,%.17g,%.17g,%.17g,%.17g,%0d,%0d,%0d,%0d,%0d,%0d", $time - T0,
                     vout.V, u_ldo.vfb, u_ldo.vctrl, u_ldo.ipass, pg_cmp, ctrl_en, load_hi, rst, state, pgood);
            #DT_NS;
        end
        $fclose(fd);
        if (!status_read)
            $fatal(1, "TB_FAIL: STATUS.PGOOD read never completed");
        $display("TB: reached %0d us", END_NS / 1000);
        $display("TB_PASS");
        $finish;
    end
endmodule
