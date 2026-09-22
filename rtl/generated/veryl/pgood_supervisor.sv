module pgood_supervisor (
    input  var logic         clk   ,
    input  var logic         rst   ,
    input  var logic         en    ,
    input  var logic         pg_cmp,
    output var logic         pgood ,
    output var logic [2-1:0] state 
);
    // Keep debug state encoding stable in generated SystemVerilog.
    localparam logic [2-1:0] OFF  = 2'd0;
    localparam logic [2-1:0] WAIT = 2'd1;
    localparam logic [2-1:0] ON   = 2'd2;

    // 20 means elapsed intervals after k0, not number of High samples.
    localparam logic [5-1:0] PG_STABLE_CYCLES = 5'd20;

    // high_cnt counts elapsed intervals since the first High sample k0.
    localparam logic [5-1:0] CNT_CLEAR = 5'd0;
    localparam logic [5-1:0] CNT_STEP  = 5'd1;
    localparam logic [5-1:0] CNT_K0    = 5'd1;

    logic [2-1:0] state_q ;
    logic         pgood_q ;
    logic [5-1:0] high_cnt;

    always_comb pgood = pgood_q;
    always_comb state = state_q;

    // Priority: rst, en==0, pg_cmp==0, qualification, ON hold.
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
                state_q  <= WAIT;
                pgood_q  <= 0;
                high_cnt <= CNT_CLEAR;
            end else if ((state_q == ON)) begin
                state_q <= ON;
                pgood_q <= 1;
            end else if ((high_cnt == CNT_CLEAR)) begin
                // First High is k0: zero elapsed intervals.
                state_q  <= WAIT;
                pgood_q  <= 0;
                high_cnt <= CNT_K0;
            end else if ((high_cnt >= PG_STABLE_CYCLES)) begin
                // Assert at k0+20, the 21st consecutive High sample.
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
