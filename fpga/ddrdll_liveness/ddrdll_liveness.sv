`default_nettype none

// DDRDLL liveness probe, readable from the host with no test equipment.
//
// The question is unchanged: does the primitive produce a tap code with
// exactly the fuses this project packs, or does it sit at zero because one of
// the six vendor-default corner bits is an enable we have not identified?
// What changed is the readout. TinyTang's console cannot see a pin, so the
// core answers two requests on the same 2 Mbaud link the recorded smoke core
// already proved on this board:
//
//   AA 00 01 01  ->  AA 00 02 01 56        core ID, kept so `fpga` works
//   AA 00 03 01  ->  AA 00 04 03 <step> <cnt_lo> <cnt_hi>
//
// The counter is in the reply on purpose: it separates a dead DDRDLL from a
// dead link. If the counter advances between two queries, the clock, the
// fabric and the UART are all running and the `step` byte means what it says.
//
// `LOCK` is deliberately unconnected -- it leaves the primitive on a dedicated
// path with no configurable bit, so the open flow has no honest pin for it.
//
// Expected behaviour comes from Gowin's model of the primitive,
// `IDE/simlib/gw5a/prim_sim.v`, not from a guess:
//   * `RESET` is active high: the model's `reset_sig = RESET | ~GSRO`.
//   * `STEP` loads its tap value only while `UPDNCNTL` is low; held high,
//     `step_reg_sig` never updates and `STEP` stays 0.
//   * with `SCAL_EN="FALSE"` the tap value is `clkin_period/0.025/360*90`,
//     which at 50 MHz is 200 = 0xC8.
//   * `LOCK` rises once the settle counter reaches 33600 clocks, 0.67 ms here.
//
// The DDRDLL is clocked at 400 MHz from the on-die PLL, the rate the
// qualified DDR3 controller uses, because the first version clocked it at the
// 50 MHz board input and both this project's image and the vendor's own build
// reported no tap code there. The 50 MHz input still runs the link and the slow
// counter. The reply also carries PLL lock and a 400 MHz-domain counter: if
// that counter never moves the PLL or its clock routing is the problem and the
// STEP reading says nothing about the DLL.
module top #(
    // Levels the probe drives, so one build sweep can move them without
    // editing the datapath.  Defaults are the model's "run" case.
    parameter STOP_LEVEL = 1'b0,
    parameter UPDN_LEVEL = 1'b0
) (
    input  wire sys_clk,   // V22, 50 MHz
    input  wire uart_rx,   // V14, TinyTang link
    output wire uart_tx    // U15, TinyTang link
);
    reg [24:0] div = 25'd0;
    reg [31:0] free_cnt = 32'd0;

    always @(posedge sys_clk) begin
        div <= div + 25'd1;
        free_cnt <= free_cnt + 32'd1;
    end

    // 50 MHz * 14 = 700 MHz VCO, CLKOUT0 / 2 = 350 MHz. The target was 400 MHz,
    // the DDR3-800 memory clock, but the router closes this design at 371 MHz:
    // the path from the primitive's own pins dominates, and it does not improve
    // when the fast-domain counter shrinks. 350 MHz still tests the clock-period
    // hypothesis at seven times the original clock, and it meets timing rather
    // than shipping an 8 percent miss.
    wire pll_clk;
    wire pll_locked;

    PLL #(
        .FCLKIN("50"),
        .IDIV_SEL(1),
        .FBDIV_SEL(1),
        .MDIV_SEL(14),
        .ODIV0_SEL(2),
        .CLKOUT0_EN("TRUE")
    ) ddr_pll (
        .CLKIN(sys_clk),
        .CLKFB(1'b0),
        .RESET(1'b0),
        .PLLPWD(1'b0),
        .RESET_I(1'b0),
        .RESET_O(1'b0),
        .FBDSEL(6'b0),
        .IDSEL(6'b0),
        .MDSEL(7'b0),
        .MDSEL_FRAC(3'b0),
        .ODSEL0(7'b0),
        .ODSEL0_FRAC(3'b0),
        .ODSEL1(7'b0),
        .ODSEL2(7'b0),
        .ODSEL3(7'b0),
        .ODSEL4(7'b0),
        .ODSEL5(7'b0),
        .ODSEL6(7'b0),
        .DT0(4'b0),
        .DT1(4'b0),
        .DT2(4'b0),
        .DT3(4'b0),
        .ICPSEL(6'b0),
        .LPFRES(3'b0),
        .LPFCAP(2'b0),
        .PSSEL(3'b0),
        .PSDIR(1'b0),
        .PSPULSE(1'b0),
        .ENCLK0(1'b1),
        .ENCLK1(1'b0),
        .ENCLK2(1'b0),
        .ENCLK3(1'b0),
        .ENCLK4(1'b0),
        .ENCLK5(1'b0),
        .ENCLK6(1'b0),
        .SSCPOL(1'b0),
        .SSCON(1'b0),
        .SSCMDSEL(7'b0),
        .SSCMDSEL_FRAC(3'b0),
        .LOCK(pll_locked),
        .CLKOUT0(pll_clk)
    );

    // 400 MHz domain: the primitive under test and the counter that proves the
    // clock actually arrived. This domain is deliberately as shallow as it can
    // be -- one 16-bit counter -- because the first version put 24- and 32-bit
    // counters here and closed at 363 MHz against a 400 MHz constraint. The
    // reset pulse comes from the 50 MHz domain instead of a comparator here.
    reg [15:0] fast_cnt = 16'd0;
    wire [7:0] step;

    // 16-clock reset pulse every 2^25 slow clocks, about 0.67 s, so the tap
    // value collapses and reloads instead of settling once and hiding.
    wire acquire = (div[24:0] < 25'd16);

    always @(posedge pll_clk)
        fast_cnt <= fast_cnt + 16'd1;

    DDRDLL #(
        .DLL_FORCE("FALSE"),
        .CODESCAL("111"),
        .SCAL_EN("FALSE"),
        .DIV_SEL(1'b0)
    ) dll (
        .CLKIN(pll_clk),
        .STOP(STOP_LEVEL),
        .UPDNCNTL(UPDN_LEVEL),
        .RESET(acquire),
        .STEP(step)
    );

    // Snapshots into the 50 MHz domain. These values are only ever read as
    // "is it moving", so a torn multi-bit sample is harmless.
    reg [7:0] step_s1 = 8'h00, step_s2 = 8'h00;
    reg [15:0] fast_s1 = 16'h0000, fast_s2 = 16'h0000;
    reg lock_s1 = 1'b0, lock_s2 = 1'b0;

    always @(posedge sys_clk) begin
        step_s1 <= step;
        step_s2 <= step_s1;
        fast_s1 <= fast_cnt;
        fast_s2 <= fast_s1;
        lock_s1 <= pll_locked;
        lock_s2 <= lock_s1;
    end

    wire rx_valid;
    wire [7:0] rx_data;
    wire tx_ready;
    reg tx_send = 1'b0;
    reg [7:0] tx_data = 8'h00;

    uart_rx_2mbaud rx (
        .clk(sys_clk),
        .rx(uart_rx),
        .valid(rx_valid),
        .data(rx_data)
    );

    uart_tx_2mbaud tx (
        .clk(sys_clk),
        .send(tx_send),
        .data(tx_data),
        .ready(tx_ready),
        .tx(uart_tx)
    );

    // Request framing: AA 00 <cmd> <arg>.
    reg [2:0] request_state = 3'd0;
    reg response_active = 1'b0;
    reg [3:0] response_index = 4'd0;
    reg response_is_query = 1'b0;
    reg [7:0] cmd_byte = 8'h00;
    reg [7:0] step_latched = 8'h00;
    reg [7:0] lock_latched = 8'h00;
    reg [15:0] cnt_latched = 16'd0;
    reg [15:0] fast_latched = 16'd0;

    always @(posedge sys_clk) begin
        tx_send <= 1'b0;

        if (rx_valid) begin
            case (request_state)
                3'd0: request_state <= (rx_data == 8'haa) ? 3'd1 : 3'd0;
                3'd1: request_state <= (rx_data == 8'h00) ? 3'd2 :
                                      (rx_data == 8'haa) ? 3'd1 : 3'd0;
                3'd2: begin
                    if (rx_data == 8'h01 || rx_data == 8'h03) begin
                        cmd_byte <= rx_data;
                        request_state <= 3'd3;
                    end else begin
                        request_state <= (rx_data == 8'haa) ? 3'd1 : 3'd0;
                    end
                end
                3'd3: begin
                    request_state <= 3'd0;
                    if (rx_data == 8'h01 && !response_active) begin
                        response_is_query <= (cmd_byte == 8'h03);
                        response_active <= 1'b1;
                        response_index <= 4'd0;
                        step_latched <= step_s2;
                        lock_latched <= {7'b0, lock_s2};
                        cnt_latched <= free_cnt[15:0];
                        fast_latched <= fast_s2;
                    end
                end
                default: request_state <= 3'd0;
            endcase
        end

        if (response_active && tx_ready && !tx_send) begin
            if (response_is_query) begin
                case (response_index)
                    4'd0: tx_data <= 8'haa;
                    4'd1: tx_data <= 8'h00;
                    4'd2: tx_data <= 8'h04;
                    4'd3: tx_data <= 8'h06;
                    4'd4: tx_data <= step_latched;
                    4'd5: tx_data <= lock_latched;
                    4'd6: tx_data <= cnt_latched[7:0];
                    4'd7: tx_data <= cnt_latched[15:8];
                    4'd8: tx_data <= fast_latched[7:0];
                    default: tx_data <= fast_latched[15:8];
                endcase
            end else begin
                case (response_index)
                    4'd0: tx_data <= 8'haa;
                    4'd1: tx_data <= 8'h00;
                    4'd2: tx_data <= 8'h02;
                    4'd3: tx_data <= 8'h01;
                    default: tx_data <= 8'h56; // "V" for TinyVCMI.
                endcase
            end
            tx_send <= 1'b1;
            if (response_index == (response_is_query ? 4'd9 : 4'd4))
                response_active <= 1'b0;
            else
                response_index <= response_index + 4'd1;
        end
    end
endmodule

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
