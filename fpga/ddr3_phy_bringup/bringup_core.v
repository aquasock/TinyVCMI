`default_nettype none

// DDR3 PHY bring-up: the control and readout half of the image.
//
// The PHY half -- PLL, CLKDIV, DDRDLL, the four DQS lanes, their serializers
// and every DDR3 pad -- is generated into top.v by
// tools/ddr3_phy_bringup.py.  This module sequences that PHY the way the
// hardware-proven controller does and reports it over the TinyTang link.
//
// The sequencer runs on the 50 MHz board clock, as the vendor IP's own DLL
// control does (its dll_rst and uddcntln flops are clocked by the IP's 50 MHz
// `clk` and preset by its reset):
//
//   RESET   DLL, CLKDIV and lanes in reset, UPDNCNTL high; wait for PLL lock
//   DLL     release the DLL; wait for LOCK, then 1024 cycles (timeout 42 ms)
//   UPDATE  UPDNCNTL low for 16 cycles, so STEP loads the tap code
//   PHY     release CLKDIV and the lanes; wait 256 cycles
//   LOAD    RLOADN and WLOADN low for 16 cycles
//   RUN     stay; a PLL lock loss or a restart request goes back to RESET
//
// The DDR3 device never leaves reset: top.v drives ddr_reset_n and ddr_cke
// low from constants and holds every DQ, DM and strobe output in tristate.
// Nothing here can change that.
//
// Requests, framed AA 00 <cmd> <arg>, at 2 Mbaud on the TinyTang link:
//
//   AA 00 01 01  ->  AA 00 02 01 56          core ID, so `fpga` still works
//   AA 00 03 01  ->  AA 00 04 12 <18 bytes>  status
//   AA 00 05 01  ->  AA 00 04 12 <18 bytes>  status, then restart the sequence
//
// Status bytes:
//    0  {state[2:0], 1'b0, lock_timeout, lock_seen, dll_lock, pll_lock}
//    1  DDRDLL STEP
//    2  50 MHz counter, low       3  high
//    4  PCLK counter, low         5  high
//    6+2n  lane n {4'b0, RVALID, RBURST, RFLAG, WFLAG}
//    7+2n  lane n {2'b0, RPOINT[2:0], WPOINT[2:0]}
//   14+n  lane n IDES8_MEM parity, the XOR of its eight serializers' outputs
//
// Every multi-bit value crosses into the 50 MHz domain through two flops and
// is only ever read as a level or as "is it moving", so a torn sample is
// harmless.
module bringup_core (
    input  wire        sys_clk,
    input  wire        uart_rx,
    output wire        uart_tx,

    input  wire        pll_lock,
    input  wire        dll_lock,
    input  wire [7:0]  step,
    input  wire        pclk,
    input  wire [3:0]  rvalid,
    input  wire [3:0]  rburst,
    input  wire [3:0]  rflag,
    input  wire [3:0]  wflag,
    input  wire [11:0] rpoint,
    input  wire [11:0] wpoint,
    input  wire [31:0] ides_parity,

    output reg         dll_rst = 1'b1,
    output reg         updncntl = 1'b1,
    output reg         phy_rst = 1'b1,
    output reg         loadn = 1'b1
);
    localparam [2:0] S_RESET  = 3'd0,
                     S_DLL    = 3'd1,
                     S_UPDATE = 3'd2,
                     S_PHY    = 3'd3,
                     S_LOAD   = 3'd4,
                     S_RUN    = 3'd5;

    // PCLK heartbeat: stops while the CLKDIV is held in reset.
    reg [15:0] pclk_cnt = 16'd0;
    always @(posedge pclk)
        pclk_cnt <= pclk_cnt + 16'd1;

    // Into the 50 MHz domain.
    reg [1:0] pll_s = 2'b00, lock_s = 2'b00;
    reg [7:0] step_s1 = 8'h00, step_s2 = 8'h00;
    reg [15:0] pclk_s1 = 16'd0, pclk_s2 = 16'd0;
    reg [39:0] lane_s1 = 40'd0, lane_s2 = 40'd0;
    reg [31:0] par_s1 = 32'd0, par_s2 = 32'd0;
    wire [39:0] lane_now = {rvalid, rburst, rflag, wflag, rpoint, wpoint};

    always @(posedge sys_clk) begin
        pll_s <= {pll_s[0], pll_lock};
        lock_s <= {lock_s[0], dll_lock};
        step_s1 <= step;
        step_s2 <= step_s1;
        pclk_s1 <= pclk_cnt;
        pclk_s2 <= pclk_s1;
        lane_s1 <= lane_now;
        lane_s2 <= lane_s1;
        par_s1 <= ides_parity;
        par_s2 <= par_s1;
    end

    wire pll_ok = pll_s[1];
    wire lock_ok = lock_s[1];

    reg [2:0] state = S_RESET;
    reg [20:0] timer = 21'd0;
    reg [10:0] settle = 11'd0;
    reg lock_seen = 1'b0;
    reg lock_timeout = 1'b0;
    reg restart = 1'b0;

    always @(posedge sys_clk) begin
        timer <= timer + 21'd1;
        if (lock_ok)
            lock_seen <= 1'b1;

        if (restart || (!pll_ok && state != S_RESET)) begin
            state <= S_RESET;
            timer <= 21'd0;
        end else begin
            case (state)
                S_RESET: begin
                    dll_rst <= 1'b1;
                    phy_rst <= 1'b1;
                    updncntl <= 1'b1;
                    loadn <= 1'b1;
                    lock_seen <= 1'b0;
                    lock_timeout <= 1'b0;
                    settle <= 11'd0;
                    if (!pll_ok)
                        timer <= 21'd0;
                    else if (timer == 21'd1023) begin
                        state <= S_DLL;
                        timer <= 21'd0;
                    end
                end
                S_DLL: begin
                    dll_rst <= 1'b0;
                    settle <= lock_ok ? settle + 11'd1 : 11'd0;
                    if (settle == 11'd1023 || &timer) begin
                        lock_timeout <= !lock_ok;
                        state <= S_UPDATE;
                        timer <= 21'd0;
                    end
                end
                S_UPDATE: begin
                    updncntl <= (timer >= 21'd16);
                    if (timer == 21'd16) begin
                        state <= S_PHY;
                        timer <= 21'd0;
                    end
                end
                S_PHY: begin
                    phy_rst <= 1'b0;
                    if (timer == 21'd255) begin
                        state <= S_LOAD;
                        timer <= 21'd0;
                    end
                end
                S_LOAD: begin
                    loadn <= (timer >= 21'd16);
                    if (timer == 21'd16)
                        state <= S_RUN;
                end
                default: state <= S_RUN;
            endcase
        end
    end

    reg [15:0] free_cnt = 16'd0;
    always @(posedge sys_clk)
        free_cnt <= free_cnt + 16'd1;

    // Lane n's two status bytes, from the synchronized vector.
    function [15:0] lane_bytes;
        input [39:0] v;
        input integer n;
        begin
            lane_bytes = {2'b00, v[12 + 3 * n +: 3], v[3 * n +: 3],
                          4'b0000, v[36 + n], v[32 + n], v[28 + n], v[24 + n]};
        end
    endfunction

    wire [143:0] status = {
        par_s2,
        lane_bytes(lane_s2, 3), lane_bytes(lane_s2, 2),
        lane_bytes(lane_s2, 1), lane_bytes(lane_s2, 0),
        pclk_s2, free_cnt, step_s2,
        state, 1'b0, lock_timeout, lock_seen, lock_ok, pll_ok
    };

    wire rx_valid;
    wire [7:0] rx_data;
    wire tx_ready;
    reg tx_send = 1'b0;
    reg [7:0] tx_data = 8'h00;

    uart_rx_2mbaud rx (.clk(sys_clk), .rx(uart_rx), .valid(rx_valid), .data(rx_data));
    uart_tx_2mbaud tx (.clk(sys_clk), .send(tx_send), .data(tx_data),
                       .ready(tx_ready), .tx(uart_tx));

    reg [1:0] request_state = 2'd0;
    reg [7:0] cmd_byte = 8'h00;
    reg response_active = 1'b0;
    reg response_is_status = 1'b0;
    reg [4:0] response_index = 5'd0;
    reg [143:0] snap = 144'd0;

    always @(posedge sys_clk) begin
        tx_send <= 1'b0;
        restart <= 1'b0;

        if (rx_valid) begin
            case (request_state)
                2'd0: request_state <= (rx_data == 8'haa) ? 2'd1 : 2'd0;
                2'd1: request_state <= (rx_data == 8'h00) ? 2'd2 :
                                       (rx_data == 8'haa) ? 2'd1 : 2'd0;
                2'd2: begin
                    if (rx_data == 8'h01 || rx_data == 8'h03 || rx_data == 8'h05) begin
                        cmd_byte <= rx_data;
                        request_state <= 2'd3;
                    end else begin
                        request_state <= (rx_data == 8'haa) ? 2'd1 : 2'd0;
                    end
                end
                default: begin
                    request_state <= 2'd0;
                    if (rx_data == 8'h01 && !response_active) begin
                        response_active <= 1'b1;
                        response_is_status <= (cmd_byte != 8'h01);
                        response_index <= 5'd0;
                        snap <= status;
                        restart <= (cmd_byte == 8'h05);
                    end
                end
            endcase
        end

        if (response_active && tx_ready && !tx_send) begin
            if (response_is_status) begin
                case (response_index)
                    5'd0: tx_data <= 8'haa;
                    5'd1: tx_data <= 8'h00;
                    5'd2: tx_data <= 8'h04;
                    5'd3: tx_data <= 8'h12;
                    default: begin
                        tx_data <= snap[7:0];
                        snap <= snap >> 8;
                    end
                endcase
            end else begin
                case (response_index)
                    5'd0: tx_data <= 8'haa;
                    5'd1: tx_data <= 8'h00;
                    5'd2: tx_data <= 8'h02;
                    5'd3: tx_data <= 8'h01;
                    default: tx_data <= 8'h56; // "V" for TinyVCMI.
                endcase
            end
            tx_send <= 1'b1;
            if (response_index == (response_is_status ? 5'd21 : 5'd4))
                response_active <= 1'b0;
            else
                response_index <= response_index + 5'd1;
        end
    end
endmodule

// The 2 Mbaud link of fpga/ddrdll_liveness, unchanged.
module uart_rx_2mbaud (
    input  wire clk,
    input  wire rx,
    output reg  valid = 1'b0,
    output reg  [7:0] data = 8'h00
);
    reg rx_meta = 1'b1;
    reg rx_sync = 1'b1;
    reg busy = 1'b0;
    reg [4:0] ticks = 5'd0;
    reg [3:0] bit_index = 4'd0;
    reg [7:0] shift = 8'h00;

    always @(posedge clk) begin
        rx_meta <= rx;
        rx_sync <= rx_meta;
        valid <= 1'b0;

        if (!busy) begin
            if (!rx_sync) begin
                busy <= 1'b1;
                ticks <= 5'd11;
                bit_index <= 4'd0;
            end
        end else if (ticks != 0) begin
            ticks <= ticks - 1'b1;
        end else if (bit_index == 0) begin
            if (!rx_sync) begin
                bit_index <= 4'd1;
                ticks <= 5'd24;
            end else begin
                busy <= 1'b0;
            end
        end else if (bit_index <= 8) begin
            shift[bit_index - 1'b1] <= rx_sync;
            bit_index <= bit_index + 1'b1;
            ticks <= 5'd24;
        end else begin
            busy <= 1'b0;
            if (rx_sync) begin
                data <= shift;
                valid <= 1'b1;
            end
        end
    end
endmodule

module uart_tx_2mbaud (
    input  wire clk,
    input  wire send,
    input  wire [7:0] data,
    output wire ready,
    output wire tx
);
    reg busy = 1'b0;
    reg [4:0] ticks = 5'd0;
    reg [3:0] bit_index = 4'd0;
    reg [9:0] shift = 10'h3ff;

    assign ready = !busy;
    assign tx = busy ? shift[0] : 1'b1;

    always @(posedge clk) begin
        if (!busy) begin
            if (send) begin
                busy <= 1'b1;
                ticks <= 5'd24;
                bit_index <= 4'd0;
                shift <= {1'b1, data, 1'b0};
            end
        end else if (ticks != 0) begin
            ticks <= ticks - 1'b1;
        end else if (bit_index == 4'd9) begin
            busy <= 1'b0;
        end else begin
            ticks <= 5'd24;
            bit_index <= bit_index + 1'b1;
            shift <= {1'b1, shift[9:1]};
        end
    end
endmodule

`default_nettype wire
