module pgood_supervisor (
    input  var logic         clk   ,
    input  var logic         rst   ,
    input  var logic         en    ,
    input  var logic         pg_cmp,
    output var logic         pgood ,
    output var logic [2-1:0] state 
);
    // Keep debug state encoding stable in generated SystemVerilog.
    typedef enum logic [2-1:0] {
        State_OFF = $bits(logic [2-1:0])'(2'd0),
        State_WAIT = $bits(logic [2-1:0])'(2'd1),
        State_ON = $bits(logic [2-1:0])'(2'd2)
    } State;

    // Assert 20 clock intervals after k0, i.e. on the 21st consecutive High sample.
    localparam logic [5-1:0] PG_STABLE_CYCLES = 5'd20;

    // high_cnt: 0 = no High yet, 1 at k0, n+1 at k0+n.
    localparam logic [5-1:0] CNT_CLEAR = 5'd0;
    localparam logic [5-1:0] CNT_STEP  = 5'd1;
    localparam logic [5-1:0] CNT_K0    = 5'd1;

    State         state_q ;
    logic         pgood_q ;
    logic [5-1:0] high_cnt;

    always_comb pgood = pgood_q;
    always_comb state = state_q;

    // Priority: rst, en==0, pg_cmp==0, qualification, ON hold.
    always_ff @ (posedge clk) begin
        if (rst) begin
            state_q  <= State_OFF;
            pgood_q  <= 0;
            high_cnt <= CNT_CLEAR;
        end else begin
            if ((!en)) begin
                state_q  <= State_OFF;
                pgood_q  <= 0;
                high_cnt <= CNT_CLEAR;
            end else if ((!pg_cmp)) begin
                state_q  <= State_WAIT;
                pgood_q  <= 0;
                high_cnt <= CNT_CLEAR;
            end else if ((state_q == State_ON)) begin
                state_q <= State_ON;
                pgood_q <= 1;
            end else if ((high_cnt == CNT_CLEAR)) begin
                // First High sample is k0: high_cnt = 1.
                state_q  <= State_WAIT;
                pgood_q  <= 0;
                high_cnt <= CNT_K0;
            end else if ((high_cnt >= PG_STABLE_CYCLES)) begin
                // Assert at k0+20, the 21st consecutive High sample.
                state_q  <= State_ON;
                pgood_q  <= 1;
                high_cnt <= high_cnt + CNT_STEP;
            end else begin
                state_q  <= State_WAIT;
                pgood_q  <= 0;
                high_cnt <= high_cnt + CNT_STEP;
            end
        end
    end
endmodule
//# sourceMappingURL=pgood_supervisor.sv.map
