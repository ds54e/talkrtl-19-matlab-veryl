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

    // ON on the 21st consecutive High sample of pg_cmp, 2 us after the first.
    localparam logic [5-1:0] PG_STABLE_CYCLES = 5'd20;

    State         state_q ;
    logic [5-1:0] high_cnt; // High samples seen so far in WAIT

    always_comb state = state_q;
    always_comb pgood = state_q == State_ON;

    // Priority: rst, en==0, pg_cmp==0, then counting in WAIT; ON holds otherwise.
    always_ff @ (posedge clk) begin
        if (rst) begin
            // Stateflow: WAIT/ON -> OFF [rst]
            state_q  <= State_OFF;
            high_cnt <= 0;
        end else begin
            if ((!en)) begin
                // Stateflow: WAIT/ON -> OFF [~en]
                state_q  <= State_OFF;
                high_cnt <= 0;
            end else if ((!pg_cmp)) begin
                // Stateflow: OFF -> WAIT [en && ~rst], ON -> WAIT [~pg_cmp]
                state_q  <= State_WAIT;
                high_cnt <= 0;
            end else if ((state_q != State_ON)) begin
                if ((high_cnt >= PG_STABLE_CYCLES)) begin
                    // Stateflow: WAIT -> ON [duration(pg_cmp, sec) >= 1.95e-06]
                    state_q <= State_ON;
                end else begin
                    state_q  <= State_WAIT;
                    high_cnt <= high_cnt + 1;
                end
            end
        end
    end
endmodule
