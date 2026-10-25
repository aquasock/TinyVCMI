`default_nettype none

// Command-bus arbitration: the JEDEC power-up owns the DDR3 command pins until
// it is done, then the controller's DFI adapter does.
//
// The two sides speak different shapes -- ddr3_init drives the raw pin levels,
// the adapter presents an op code -- so this module is also where the op code
// becomes pin levels, using exactly the encoding the proven core uses:
// {cs, ras, cas, we} = MRS 0000, REF 0001, PRE 0010, ACT 0011, WR 0100,
// RD 0101, ZQ 0110.  Any disagreement here is a wrong command on the bus, so
// init wins unconditionally until it says it is finished, and a command is one
// cycle wide.
module ddr3_cmdmux (
    input  wire        pclk,
    input  wire        init_done,     // from ddr3_init
    input  wire        train_done,    // from ddr3_rotlatch: training has frozen

    // power-up side: raw pin levels, held or pulsed by the sequencer
    input  wire        i_cs_n,
    input  wire        i_ras_n,
    input  wire        i_cas_n,
    input  wire        i_we_n,
    input  wire [2:0]  i_ba,
    input  wire [15:0] i_addr,

    // training side: the boot pattern pass, op code one cycle wide
    input  wire        t_valid,
    input  wire [2:0]  t_op,
    input  wire [2:0]  t_ba,
    input  wire [15:0] t_addr,

    // controller side: the DFI adapter's op code, one cycle wide
    input  wire        a_valid,
    input  wire [2:0]  a_op,
    input  wire [2:0]  a_ba,
    input  wire [15:0] a_addr,

    // the PHY's command pins
    output reg         cs_n,
    output reg         ras_n,
    output reg         cas_n,
    output reg         we_n,
    output reg  [2:0]  ba,
    output reg  [15:0] addr
);
    localparam [2:0] OP_MRS = 3'd0, OP_REF = 3'd1, OP_PRE = 3'd2,
                     OP_ACT = 3'd3, OP_RD  = 3'd4, OP_WR  = 3'd5;

    reg [3:0] pins;   // from the adapter's op
    reg [3:0] tpins;  // from the training pass's op

    always @(*) begin
        case (t_op)
            OP_MRS: tpins = 4'b0000;
            OP_REF: tpins = 4'b0001;
            OP_PRE: tpins = 4'b0010;
            OP_ACT: tpins = 4'b0011;
            OP_WR:  tpins = 4'b0100;
            OP_RD:  tpins = 4'b0101;
            default: tpins = 4'b0110;
        endcase
    end

    always @(*) begin
        case (a_op)
            OP_MRS: pins = 4'b0000;
            OP_REF: pins = 4'b0001;
            OP_PRE: pins = 4'b0010;
            OP_ACT: pins = 4'b0011;
            OP_WR:  pins = 4'b0100;
            OP_RD:  pins = 4'b0101;
            default: pins = 4'b0110;      // ZQ, unused by the adapter
        endcase
    end

    // Three tiers: the power-up owns the bus until it is done, the training
    // pass owns it until the rotations are frozen, and only then does the
    // controller.  A tier never sees the bus before its predecessor finishes.
    always @(posedge pclk) begin
        if (!init_done) begin
            cs_n  <= i_cs_n;
            ras_n <= i_ras_n;
            cas_n <= i_cas_n;
            we_n  <= i_we_n;
            ba    <= i_ba;
            addr  <= i_addr;
        end else if (!train_done) begin
            if (t_valid) begin
                {cs_n, ras_n, cas_n, we_n} <= tpins;
                ba   <= t_ba;
                addr <= t_addr;
            end else begin
                cs_n <= 1'b1; ras_n <= 1'b1; cas_n <= 1'b1; we_n <= 1'b1;
            end
        end else if (a_valid) begin
            {cs_n, ras_n, cas_n, we_n} <= pins;
            ba   <= a_ba;
            addr <= a_addr;
        end else begin
            // deselect between commands, as the proven core does
            cs_n <= 1'b1;
            ras_n <= 1'b1;
            cas_n <= 1'b1;
            we_n <= 1'b1;
        end
    end
endmodule

`default_nettype wire
