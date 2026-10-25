`timescale 1ns/1ps
`default_nettype none

// Unit simulation of the boot-training sequencer.
//
// Two scenarios, because both are hardware-plausible: a training that
// converges, which must stop on the first all-four-trained report and leave
// `done` set with the drive released, and one that never converges, which must
// end in `failed` rather than hanging on the bus.
module tb_ddr3_train;
    reg pclk = 1'b0, rst = 1'b1, init_done = 1'b0;
    reg [3:0] trained = 0;
    wire cmd_valid, dq_drive, read_en, stream, done, failed;
    wire [2:0] cmd_op, cmd_bank;
    wire [14:0] cmd_addr;
    wire [7:0] dq_pat;

    always #5 pclk = ~pclk;

    ddr3_train #(.WRITES(4), .SPACING(4), .TRAIN_LIMIT(64)) dut (
        .pclk(pclk), .rst(rst), .init_done(init_done), .trained(trained),
        .cmd_valid(cmd_valid), .cmd_op(cmd_op), .cmd_bank(cmd_bank),
        .cmd_addr(cmd_addr), .dq_pat(dq_pat), .dq_drive(dq_drive),
        .read_en(read_en), .stream(stream), .done(done), .failed(failed));

    integer errors = 0;
    task fail(input [8*72-1:0] msg);
        begin
            if (errors < 20) $display("FAIL  t=%0t %0s", $time, msg);
            errors = errors + 1;
        end
    endtask

    // count what actually went out
    integer acts = 0, wrs = 0, rds = 0;
    reg seen_drive = 1'b0, seen_read_en = 1'b0, seen_stream = 1'b0;
    always @(posedge pclk) begin
        if (cmd_valid) begin
            if (cmd_op == 3'd3) acts = acts + 1;
            if (cmd_op == 3'd5) wrs = wrs + 1;
            if (cmd_op == 3'd4) rds = rds + 1;
        end
        if (dq_drive) seen_drive <= 1'b1;
        if (read_en)  seen_read_en <= 1'b1;
        if (stream)   seen_stream <= 1'b1;
    end

    initial begin
        repeat (2) @(posedge pclk);
        rst <= 1'b0;
        repeat (2) @(posedge pclk);
        if (cmd_valid) fail("the trainer commanded before the power-up finished");

        init_done <= 1'b1;
        // converge after some READs
        repeat (40) @(posedge pclk);
        trained <= 4'b1111;
        wait (done === 1'b1 || failed === 1'b1);
        repeat (2) @(posedge pclk);

        if (failed) fail("a converging training reported failure");
        if (!done) fail("training did not report done");
        if (acts != 1) fail("the trainer did not issue exactly one ACTIVATE");
        if (wrs != 4) begin
            fail("the trainer did not write the configured number of bursts");
            $display("      wrote %0d", wrs);
        end
        if (rds < 4) fail("the trainer issued too few READs to train on");
        if (!seen_drive) fail("the pattern was never driven onto DQ");
        if (!seen_read_en || !seen_stream)
            fail("the gate or the training stream was never asserted");
        if (dq_drive !== 1'b0) fail("the drive stayed on after training");

        if (errors == 0)
            $display("PASS  one ACTIVATE, the configured WRITEs, READs that train, then done with the drive released");
        else
            $display("FAIL  %0d error(s)", errors);
        $finish;
    end
endmodule

`default_nettype wire
