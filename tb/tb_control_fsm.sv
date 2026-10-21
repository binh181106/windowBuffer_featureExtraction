`timescale 1ns / 1ps

module tb_control_fsm;

    reg clk;
    reg rst_n;
    reg start;
    reg feat_valid;
    reg apb_enable;

    wire fsm_idle;
    wire window_en;
    wire done;
    wire [3:0] current_state;

    control_fsm dut (
        .clk(clk), .rst_n(rst_n),
        .start(start), .feat_valid(feat_valid), .apb_enable(apb_enable),
        .fsm_idle(fsm_idle), .window_en(window_en),
        .done(done), .current_state(current_state)
    );

    initial begin
        clk = 0;
        forever #9.92 clk = ~clk;  // 19.84ns period = 50.4MHz
    end

    integer timeout;

    initial begin
        $display("Control FSM Test");
        $dumpfile("tb_control_fsm.vcd");
        $dumpvars(0, tb_control_fsm);

        rst_n = 0;
        start = 0;
        feat_valid = 0;
        apb_enable = 0;

        #100;
        rst_n = 1;
        #100;

        $display("Starting classification...");
        apb_enable = 1;
        start = 1;
        @(posedge clk);
        start = 0;

        // Check IDLE -> LOAD transition
        wait(current_state == 1);
        $display("Reached LOAD state");

        // Assert feat_valid and wait
        feat_valid = 1;
        timeout = 0;
        while (current_state != 2 && timeout < 1000) begin
            @(posedge clk);
            timeout = timeout + 1;
        end

        if (current_state == 2) begin
            $display("Reached NORMALIZE state");
            feat_valid = 0;
        end else begin
            $display("FAILED to reach NORMALIZE (timeout), state=%d", current_state);
        end

        $finish;
    end

endmodule
