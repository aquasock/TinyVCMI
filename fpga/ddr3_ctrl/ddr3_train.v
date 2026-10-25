`default_nettype none

// Boot training: write the pattern, read it back, and let rd_align find the
// frame.
//
// The controller cannot calibrate on arbitrary data, so the first thing it does
// after the power-up is a pattern pass: ACTIVATE row 0 of bank 0, stream WRITEs
// of a known pattern at write spacing, then stream READs with the DQS gate open
// and `stream` asserted, which is the condition rd_align trains under.  When it
// reports all four lanes trained, ddr3_rotlatch freezes the rotations and the
// write path may leave pattern mode.
//
// A timeout ends the attempt rather than hanging: `failed` means the training
// never converged, which is a hardware fact to be seen in the status frame, not
// a reason to leave the bus mid-sequence.
module ddr3_train #(
    parameter integer WRITES      = 8,     // pattern bursts to write
    parameter integer SPACING     = 8,     // PCLK between commands
    parameter integer TRAIN_LIMIT = 4096   // PCLK of READs before giving up
) (
    input  wire        pclk,
    input  wire        rst,          // hold while the PHY is not ready
    input  wire        init_done,    // the power-up owns the bus until this
    input  wire [3:0]  trained,      // from rd_align

    output reg         cmd_valid = 1'b0,
    output reg  [2:0]  cmd_op = 3'd0,
    output reg  [2:0]  cmd_bank = 3'd0,
    output reg  [14:0] cmd_addr = 15'd0,
    output reg  [7:0]  dq_pat = 8'h1d,   // the training pattern
    output reg         dq_drive = 1'b0,  // drive the pattern onto DQ
    output reg         read_en = 1'b0,   // DQS gate open
    output reg         stream = 1'b0,    // rd_align's training condition
    output reg         done = 1'b0,      // all four lanes trained
    output reg         failed = 1'b0     // the attempt timed out
);
    localparam [2:0] OP_ACT = 3'd3, OP_RD = 3'd4, OP_WR = 3'd5;

    localparam [2:0] T_IDLE = 3'd0, T_ACT = 3'd1, T_WR = 3'd2,
                     T_RD = 3'd3, T_DONE = 3'd4, T_FAIL = 3'd5;

    reg [2:0]  state = T_IDLE;
    reg [15:0] wait_cnt = 16'd0;
    reg [7:0]  writes = 8'd0;
    reg [15:0] rd_cnt = 16'd0;

    always @(posedge pclk) begin
        cmd_valid <= 1'b0;
        if (rst || !init_done) begin
            state <= T_IDLE;
            wait_cnt <= 16'd0;
            writes <= 8'd0;
            rd_cnt <= 16'd0;
            dq_drive <= 1'b0;
            read_en <= 1'b0;
            stream <= 1'b0;
            done <= 1'b0;
            failed <= 1'b0;
        end else begin
            case (state)
                // ACTIVATE bank 0, row 0 -- the row the pattern goes into
                T_IDLE: begin
                    cmd_valid <= 1'b1;
                    cmd_op <= OP_ACT;
                    cmd_bank <= 3'd0;
                    cmd_addr <= 15'd0;
                    dq_drive <= 1'b1;
                    state <= T_WR;
                    wait_cnt <= SPACING - 1;
                    writes <= 8'd0;
                end
                // stream the pattern in at the chosen spacing
                T_WR: begin
                    if (wait_cnt == 16'd0) begin
                        if (writes == WRITES - 1) begin
                            state <= T_RD;
                            rd_cnt <= 16'd0;
                        end else begin
                            writes <= writes + 8'd1;
                            wait_cnt <= SPACING - 1;
                        end
                        cmd_valid <= 1'b1;
                        cmd_op <= OP_WR;
                        cmd_bank <= 3'd0;
                        cmd_addr <= {5'd0, writes, 3'b000};  // BL8 bursts
                    end else begin
                        wait_cnt <= wait_cnt - 16'd1;
                    end
                end
                // reads with the gate open: this is what rd_align trains on
                T_RD: begin
                    read_en <= 1'b1;
                    stream <= 1'b1;
                    if (trained == 4'b1111) begin
                        state <= T_DONE;
                        stream <= 1'b0;
                        done <= 1'b1;
                    end else if (rd_cnt >= TRAIN_LIMIT) begin
                        state <= T_FAIL;
                        stream <= 1'b0;
                        failed <= 1'b1;
                    end else begin
                        rd_cnt <= rd_cnt + 16'd1;
                        if (wait_cnt == 16'd0) begin
                            wait_cnt <= SPACING - 1;
                            cmd_valid <= 1'b1;
                            cmd_op <= OP_RD;
                            cmd_bank <= 3'd0;
                            cmd_addr <= {5'd0, rd_cnt[7:0], 3'b000};
                        end else begin
                            wait_cnt <= wait_cnt - 16'd1;
                        end
                    end
                end
                // trained: drop the drive and gate, keep the bus ours
                T_DONE: begin
                    dq_drive <= 1'b0;
                    read_en <= 1'b1;
                    stream <= 1'b1;
                end
                default: begin
                    dq_drive <= 1'b0;
                    read_en <= 1'b0;
                    stream <= 1'b0;
                end
            endcase
        end
    end
endmodule

`default_nettype wire
