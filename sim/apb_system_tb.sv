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

    task automatic record_digital(input int tick);
        $fwrite(digital_fd, "%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d\n",
                tick, tick * CLK_NS, rst, ctrl_en, cap_pg_cmp, state, pgood, load_hi);
    endtask

    initial begin
        analog_fd = $fopen("analog.csv", "w");
        digital_fd = $fopen("digital.csv", "w");
        $fwrite(analog_fd, "time_ns,vout,vfb,vctrl,ipass,pg_cmp,en,load_hi\n");
        $fwrite(digital_fd, "tick,time_ns,rst,en,pg_cmp,state,pgood,load_hi\n");

        // Reset before scenario time zero, without advancing analog state.
        u_ldo.rst_state();
        rst = 1'b1;
        repeat (2) begin
            #50 clk = 1'b1;
            #50 clk = 1'b0;
        end
        rst = 1'b0;

        // Include both analog endpoints and the final digital half-clock sample.
        for (int t_ns = 0; t_ns <= END_NS + CLK_NS / 2; t_ns += DT_NS) begin
            if (t_ns > 0) begin
                #DT_NS;
                u_ldo.step(DT_NS * 1e-9);
            end
            if (t_ns % CLK_NS == 0) begin
                load_hi = (t_ns >= 25000 && t_ns < 35000);
                cap_pg_cmp = pg_cmp;
                if (t_ns == 0) record_digital(0);
                else clk = 1'b1;
            end
            if (t_ns % CLK_NS == CLK_NS / 2) begin
                clk = 1'b0;
                if (t_ns >= CLK_NS) record_digital(t_ns / CLK_NS);
                if (apb_done && !apb_write) begin
                    if (apb_rdata[0] !== pgood)
                        $fatal(1, "APB_SYSTEM_FAIL: STATUS.PGOOD does not match pgood");
                    $display("APB_SYSTEM: STATUS.PGOOD read matches pgood=%0d", pgood);
                    status_read = 1'b1;
                end
                // Issue after tick 18 so APB setup + access raise CTRL.EN at tick 20.
                apb_start = (t_ns / CLK_NS == 18 || t_ns / CLK_NS == 200);
                case (t_ns / CLK_NS)
                    18: begin
                        apb_write = 1'b1;
                        apb_addr = 3'h0; // CTRL.EN
                        apb_wdata = 32'h1;
                    end
                    200: begin
                        if (ctrl_en !== 1'b1 || vout < 0.87 || pgood !== 1'b1)
                            $fatal(1, "APB_SYSTEM_FAIL: CTRL.EN write did not enable the LDO");
                        $display("APB_SYSTEM: CTRL.EN write enabled the LDO and PGOOD");
                        apb_write = 1'b0;
                        apb_addr = 3'h4; // STATUS.PGOOD
                    end
                endcase
            end
            // Log after NBA updates and real-port propagation, at the same instant.
            sample_ns = t_ns;
            if (t_ns <= END_NS)
                $fstrobe(analog_fd, "%0d,%.17g,%.17g,%.17g,%.17g,%0d,%0d,%0d",
                         sample_ns, vout, vfb, vctrl, ipass, pg_cmp, ctrl_en, load_hi);
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
