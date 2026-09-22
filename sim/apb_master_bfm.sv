module apb_master_bfm (
    input  logic        clk,
    input  logic        rst_n,
    rggen_apb_if.master apb_bus,
    input  logic        apb_start,
    input  logic        apb_write,
    input  logic [2:0]  apb_addr,
    input  logic [31:0] apb_wdata,
    output logic [31:0] apb_rdata,
    output logic        apb_err,
    output logic        apb_done
);
    typedef enum logic [1:0] {APB_IDLE, APB_SETUP, APB_ACCESS} apb_phase_t;
    apb_phase_t apb_phase = APB_IDLE;

    always_ff @(posedge clk) begin
        apb_done <= 1'b0;
        if (!rst_n) begin
            apb_bus.psel    <= 1'b0;
            apb_bus.penable <= 1'b0;
            apb_bus.pwrite  <= 1'b0;
            apb_bus.paddr   <= '0;
            apb_bus.pwdata  <= '0;
            apb_bus.pstrb   <= '0;
            apb_bus.pprot   <= 3'b000;
            apb_phase       <= APB_IDLE;
        end
        else begin
            case (apb_phase)
                APB_IDLE: if (apb_start) begin
                    apb_bus.psel    <= 1'b1;
                    apb_bus.penable <= 1'b0;
                    apb_bus.pwrite  <= apb_write;
                    apb_bus.paddr   <= apb_addr;
                    apb_bus.pwdata  <= apb_wdata;
                    apb_bus.pstrb   <= '1;
                    apb_bus.pprot   <= 3'b000;
                    apb_phase       <= APB_SETUP;
                end
                APB_SETUP: begin
                    apb_bus.penable <= 1'b1;
                    apb_phase       <= APB_ACCESS;
                end
                APB_ACCESS: if (apb_bus.pready) begin
                    apb_rdata       <= apb_bus.prdata;
                    apb_err         <= apb_bus.pslverr;
                    apb_bus.psel    <= 1'b0;
                    apb_bus.penable <= 1'b0;
                    apb_done        <= 1'b1;
                    apb_phase       <= APB_IDLE;
                end
                default: apb_phase <= APB_IDLE;
            endcase
        end
    end
endmodule
