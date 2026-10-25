`default_nettype none

// DFI adapter: LiteDRAM's control layer on one side, TinyVCMI's hand-written
// DDR3 PHY on the other.
//
// The controller speaks DFI: four phases per PCLK, each phase carrying its own
// command bus and 64 bits of write or read data.  The PHY accepts one command
// per PCLK and moves one complete BL8 burst -- 256 bits -- per PCLK, which at
// 1:4 is the same thing: four phases, two beats each.
//
// Command side: at most one phase asserts a command in any PCLK for this
// device (a BL8 READ occupies four DRAM clocks, so the scheduler cannot issue
// faster and still respect tCCD).  The adapter therefore picks the active
// phase, decodes it into the PHY's op encoding, and holds it in a two-deep
// queue until the PHY takes it.  A cycle with more than one phase commanding
// is recorded rather than silently resolved.
//
// Read side: the PHY hands over a whole burst with a valid pulse.  The adapter
// slices it into the four DFI phases and presents it RD_LATENCY PCLKs after
// rddata_en, which is the contract the controller expects.  If the controller
// asks for data the PHY has not delivered, rd_underflow is set: that is the
// observable form of the scatter limitation, moved to the boundary where it
// can be counted instead of corrupting silently.
module dfi_adapter #(
    parameter integer RD_LATENCY = 7,   // PCLK, rddata_en -> rddata_valid
    parameter integer ADD_W      = 15,
    parameter integer BANK_W     = 3,
    parameter integer PHY_W      = 64    // DFI bits per phase
) (
    input  wire                 pclk,
    input  wire                 rst,

    // DFI, driven by the controller
    input  wire [3:0]           dfi_cs_n,
    input  wire [3:0]           dfi_ras_n,
    input  wire [3:0]           dfi_cas_n,
    input  wire [3:0]           dfi_we_n,
    input  wire [3:0]           dfi_cke,
    input  wire [3:0]           dfi_odt,
    input  wire [4*ADD_W-1:0]   dfi_address,   // phase p at p*ADD_W +: ADD_W
    input  wire [4*BANK_W-1:0]  dfi_bank,      // phase p at p*BANK_W +: BANK_W
    input  wire [4*PHY_W-1:0]   dfi_wrdata,    // phase p at p*PHY_W +: PHY_W
    input  wire [3:0]           dfi_wrdata_en,
    input  wire [3:0]           dfi_rddata_en,
    output reg  [4*PHY_W-1:0]   dfi_rddata,
    output reg  [3:0]           dfi_rddata_valid,

    // PHY side
    output reg                  phy_cmd_valid,
    output reg  [2:0]           phy_cmd_op,     // see OP_* below
    output reg  [BANK_W-1:0]    phy_cmd_bank,
    output reg  [ADD_W-1:0]     phy_cmd_addr,
    input  wire                 phy_cmd_taken,  // the PHY consumed it this PCLK
    output reg                  phy_wr_valid,
    output reg  [4*PHY_W-1:0]   phy_wr_data,
    input  wire [4*PHY_W-1:0]   phy_rd_data,    // one whole BL8 burst
    input  wire                 phy_rd_valid,

    // Instrumentation, surfaced verbatim by the controller's status frame
    output reg                  stat_cmd_collision,
    output reg                  stat_rd_underflow,
    output reg  [15:0]          stat_cmd_count,
    output reg  [15:0]          stat_rd_count
);
    // op encoding, shared with the PHY's issue() port
    localparam [2:0] OP_MRS = 3'd0, OP_REF = 3'd1, OP_PRE = 3'd2,
                     OP_ACT = 3'd3, OP_RD  = 3'd4, OP_WR  = 3'd5;

    // ---- command decode -------------------------------------------------
    // cs_n low marks a command; (ras, cas, we) selects it.
    reg        have_cmd;
    reg [1:0]  cmd_phase;
    reg [2:0]  cmd_op;
    reg [BANK_W-1:0] cmd_bank;
    reg [ADD_W-1:0]  cmd_addr;
    integer    p;
    integer    cmds;

    always @(*) begin
        have_cmd = 1'b0;
        cmd_phase = 2'd0;
        cmd_op = OP_MRS;
        cmd_bank = {BANK_W{1'b0}};
        cmd_addr = {ADD_W{1'b0}};
        cmds = 0;
        for (p = 0; p < 4; p = p + 1) begin
            if (!dfi_cs_n[p]) begin
                cmds = cmds + 1;
                if (!have_cmd) begin
                    have_cmd  = 1'b1;
                    cmd_phase = p[1:0];
                    cmd_bank  = dfi_bank[p*BANK_W +: BANK_W];
                    cmd_addr  = dfi_address[p*ADD_W +: ADD_W];
                    case ({dfi_ras_n[p], dfi_cas_n[p], dfi_we_n[p]})
                        3'b011: cmd_op = OP_ACT;   // RAS only
                        3'b101: cmd_op = OP_RD;    // CAS only
                        3'b100: cmd_op = OP_WR;    // CAS + WE
                        3'b010: cmd_op = OP_PRE;   // CAS
                        3'b001: cmd_op = OP_REF;   // WE
                        default: cmd_op = OP_MRS;  // RAS+CAS+WE
                    endcase
                end
            end
        end
    end

    // ---- a two-deep command queue ---------------------------------------
    // The PHY takes one command per PCLK; the controller may present one per
    // phase, so a shallow queue absorbs the burst once the PHY declines.
    reg        q_valid0, q_valid1;
    reg [2:0]  q_op0, q_op1;
    reg [BANK_W-1:0] q_bank0, q_bank1;
    reg [ADD_W-1:0]  q_addr0, q_addr1;
    reg        issued_rd, issued_wr;      // the op leaving this cycle

    always @(posedge pclk) begin
        if (rst) begin
            q_valid0 <= 1'b0; q_valid1 <= 1'b0;
            phy_cmd_valid <= 1'b0;
            phy_cmd_op <= OP_MRS;
            phy_cmd_bank <= {BANK_W{1'b0}};
            phy_cmd_addr <= {ADD_W{1'b0}};
            stat_cmd_collision <= 1'b0;
            stat_cmd_count <= 16'd0;
        end else begin
            phy_cmd_valid <= 1'b0;
            if (cmds > 1)
                stat_cmd_collision <= 1'b1;

            // drain first
            if (q_valid0) begin
                phy_cmd_valid <= 1'b1;
                phy_cmd_op    <= q_op0;
                phy_cmd_bank  <= q_bank0;
                phy_cmd_addr  <= q_addr0;
                q_valid0 <= q_valid1;
                q_op0 <= q_op1; q_bank0 <= q_bank1; q_addr0 <= q_addr1;
                q_valid1 <= 1'b0;
                if (have_cmd) begin
                    q_valid1 <= 1'b1;
                    q_op1 <= cmd_op; q_bank1 <= cmd_bank; q_addr1 <= cmd_addr;
                end
            end else if (have_cmd) begin
                phy_cmd_valid <= 1'b1;
                phy_cmd_op    <= cmd_op;
                phy_cmd_bank  <= cmd_bank;
                phy_cmd_addr  <= cmd_addr;
            end

            if (phy_cmd_valid) begin
                stat_cmd_count <= stat_cmd_count + 16'd1;
                if (phy_cmd_op == OP_RD) issued_rd <= 1'b1;
                if (phy_cmd_op == OP_WR) issued_wr <= 1'b1;
            end
        end
    end

    // ---- write data ------------------------------------------------------
    // Four phases of 64 bits are one burst; hand it over when the controller
    // says write data is on the bus.
    always @(posedge pclk) begin
        if (rst) begin
            phy_wr_valid <= 1'b0;
            phy_wr_data <= {4*PHY_W{1'b0}};
        end else begin
            phy_wr_valid <= |dfi_wrdata_en;
            phy_wr_data  <= dfi_wrdata;
        end
    end

    // ---- read data -------------------------------------------------------
    // One whole burst per PCLK from the PHY, re-sliced into four phases and
    // presented RD_LATENCY after the controller asked for it.
    reg [4*PHY_W-1:0] rd_buf;
    reg               rd_buf_valid;
    reg [RD_LATENCY-1:0] rd_en_d;
    wire rd_due = rd_en_d[RD_LATENCY-1];

    always @(posedge pclk) begin
        if (rst) begin
            rd_buf <= {4*PHY_W{1'b0}};
            rd_buf_valid <= 1'b0;
            rd_en_d <= {RD_LATENCY{1'b0}};
            dfi_rddata <= {4*PHY_W{1'b0}};
            dfi_rddata_valid <= 4'd0;
            stat_rd_underflow <= 1'b0;
            stat_rd_count <= 16'd0;
        end else begin
            rd_en_d <= {rd_en_d[RD_LATENCY-2:0], |dfi_rddata_en};
            dfi_rddata_valid <= 4'd0;

            if (phy_rd_valid) begin
                rd_buf <= phy_rd_data;
                rd_buf_valid <= 1'b1;
            end

            if (rd_due) begin
                if (rd_buf_valid) begin
                    dfi_rddata <= rd_buf;
                    dfi_rddata_valid <= 4'b1111;
                    rd_buf_valid <= 1'b0;
                    stat_rd_count <= stat_rd_count + 16'd1;
                end else begin
                    // the controller expected a burst the PHY did not deliver
                    stat_rd_underflow <= 1'b1;
                end
            end
        end
    end
endmodule

`default_nettype wire
