`default_nettype none

module openflow_smoke (
    input  wire sys_clk,
    input  wire uart_rx,
    output wire uart_tx,
    output wire heartbeat
);
    reg [25:0] divider = 26'd0;
    wire rx_valid;
    wire [7:0] rx_data;
    reg tx_send = 1'b0;
    reg [7:0] tx_data = 8'h00;
    wire tx_ready;
    reg [2:0] request_state = 3'd0;
    reg response_active = 1'b0;
    reg [2:0] response_index = 3'd0;

    always @(posedge sys_clk)
        divider <= divider + 1'b1;

    assign heartbeat = divider[25];

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

    // TinyTang core-ID request: AA 00 01 01.
    always @(posedge sys_clk) begin
        tx_send <= 1'b0;

        if (rx_valid) begin
            case (request_state)
                3'd0: request_state <= rx_data == 8'haa ? 3'd1 : 3'd0;
                3'd1: request_state <= rx_data == 8'h00 ? 3'd2 :
                                             rx_data == 8'haa ? 3'd1 : 3'd0;
                3'd2: request_state <= rx_data == 8'h01 ? 3'd3 :
                                             rx_data == 8'haa ? 3'd1 : 3'd0;
                3'd3: begin
                    request_state <= 3'd0;
                    if (rx_data == 8'h01 && !response_active) begin
                        response_active <= 1'b1;
                        response_index <= 3'd0;
                    end
                end
                default: request_state <= 3'd0;
            endcase
        end

        if (response_active && tx_ready && !tx_send) begin
            case (response_index)
                3'd0: tx_data <= 8'haa;
                3'd1: tx_data <= 8'h00;
                3'd2: tx_data <= 8'h02;
                3'd3: tx_data <= 8'h01;
                default: tx_data <= 8'h56; // "V" for TinyVCMI.
            endcase
            tx_send <= 1'b1;
            if (response_index == 3'd4)
                response_active <= 1'b0;
            else
                response_index <= response_index + 1'b1;
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
