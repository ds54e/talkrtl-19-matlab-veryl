// pgood_supervisor -- digital PGOOD supervisor.
//
// CONTRACT.md §4. Regulation is done by the analog loop; this module only
// time-qualifies `pg_cmp` into `pgood`.
//
// interface: clk rst en pg_cmp -> pgood, debug state
// clock: posedge, 100 ns period (10 MHz) nominal
// reset: synchronous, active high (Veryl.toml reset_type = "sync_high")
//
// `state` is a debug observation only. It is never exposed to the product CSR.
module pgood_supervisor (
    input  var logic         clk   ,
    input  var logic         rst   ,
    input  var logic         en    ,
    input  var logic         pg_cmp,
    output var logic         pgood ,
    output var logic [2-1:0] state 
);
    // Debug state encoding is fixed explicitly (OFF=0, WAIT=1, ON=2) so the
    // generated SystemVerilog shows the numbers rather than a tool-chosen encoding.
    localparam logic [2-1:0] OFF  = 2'd0;
    localparam logic [2-1:0] WAIT = 2'd1;
    localparam logic [2-1:0] ON   = 2'd2;

    // `PG_STABLE_CYCLES = 20` is the number of elapsed observation intervals, not
    // the number of High samples already seen. See the qualification block below.
    localparam logic [5-1:0] PG_STABLE_CYCLES = 5'd20;

    // high_cnt == 0 means "no qualification timing is in progress"; the counter is
    // discarded by rst, by en==0 and by pg_cmp==0. Otherwise high_cnt holds the
    // number of elapsed intervals since the first High observation k0 of the
    // current run, with k0 itself being 0 elapsed intervals.
    localparam logic [5-1:0] CNT_CLEAR = 5'd0;
    localparam logic [5-1:0] CNT_STEP  = 5'd1;
    localparam logic [5-1:0] CNT_K0    = 5'd1;

    logic [2-1:0] state_q ;
    logic         pgood_q ;
    logic [5-1:0] high_cnt;

    always_comb pgood = pgood_q;
    always_comb state = state_q;

    // Sampled priority on every tick (CONTRACT §4):
    //   1. rst              -> OFF, pgood=0, discard timing
    //   2. en == 0          -> OFF, pgood=0, discard timing
    //   3. pg_cmp == 0      -> WAIT, pgood=0, discard timing
    //   4. qualification    -> WAIT, or ON once k - k0 >= 20
    //   5. ON hold
    //
    // Priority 1 is `if_reset`: with reset_type = "sync_high" Veryl emits
    // `always_ff @ (posedge clk) if (rst) ... else ...`, i.e. a synchronous
    // active-high reset taking precedence over everything below.
    always_ff @ (posedge clk) begin
        if (rst) begin
            state_q  <= OFF;
            pgood_q  <= 0;
            high_cnt <= CNT_CLEAR;
        end else begin
            if ((!en)) begin
                state_q  <= OFF;
                pgood_q  <= 0;
                high_cnt <= CNT_CLEAR;
            end else if ((!pg_cmp)) begin
                // A Low observed while ON deasserts in this same tick's processed
                // output and returns to WAIT; the timing never carries over.
                state_q  <= WAIT;
                pgood_q  <= 0;
                high_cnt <= CNT_CLEAR;
            end else if ((state_q == ON)) begin
                state_q <= ON;
                pgood_q <= 1;
            end else if ((high_cnt == CNT_CLEAR)) begin
                // This observation is the first High of the run, i.e. k0.
                // k0 is 0 elapsed intervals, so pgood stays 0 even at k0.
                state_q  <= WAIT;
                pgood_q  <= 0;
                high_cnt <= CNT_K0;
            end else if ((high_cnt >= PG_STABLE_CYCLES)) begin
                // k - k0 >= 20: the 21st consecutive High observation asserts.
                // At k0+19 high_cnt is 19, so pgood is still 0 there.
                state_q  <= ON;
                pgood_q  <= 1;
                high_cnt <= high_cnt + CNT_STEP;
            end else begin
                state_q  <= WAIT;
                pgood_q  <= 0;
                high_cnt <= high_cnt + CNT_STEP;
            end
        end
    end
endmodule
//# sourceMappingURL=pgood_supervisor.sv.map
