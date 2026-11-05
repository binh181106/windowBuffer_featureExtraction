`timescale 1ns / 1ps

module tb_control_fsm;

    reg clk;
    reg rst_n;
    reg start;
    reg feat_valid;
    reg apb_enable;
    reg window_ready;
    reg mlp_done;
    reg soft_reset;

    wire fsm_idle;
    wire window_en;
    wire done;
    wire [3:0] current_state;
    wire feature_start;
    wire [8:0] read_addr;

    // Latch bắt pulse feature_start (pulse 1 chu kỳ, tránh race đọc)
    reg fs_seen;
    initial fs_seen = 1'b0;
    always @(posedge clk) if (feature_start) fs_seen <= 1'b1;

    control_fsm dut (
        .clk(clk), .rst_n(rst_n),
        .start(start), .feat_valid(feat_valid), .apb_enable(apb_enable),
        .window_ready(window_ready), .mlp_done(mlp_done),
        .soft_reset(soft_reset),
        .fsm_idle(fsm_idle), .window_en(window_en),
        .feature_start(feature_start),
        .done(done), .current_state(current_state),
        .feature_read_en(), .mlp_start(), .mlp_valid(), .uart_send(),
        .read_addr(read_addr), .next_state_debug()
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
        window_ready = 0;
        mlp_done = 0;
        soft_reset = 0;

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

        // (fix v3.0) LOAD chờ window_ready -> phát feature_start (pulse 1 chu kỳ,
        // được latch bởi fs_seen), rồi chờ feat_valid -> NORMALIZE
        @(posedge clk);
        window_ready = 1;
        timeout = 0;
        while (!fs_seen && timeout < 100) begin
            @(posedge clk);
            timeout = timeout + 1;
        end
        window_ready = 0;
        if (fs_seen) $display("feature_start pulsed on window_ready");
        else         $display("FAILED to get feature_start (timeout)");

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
