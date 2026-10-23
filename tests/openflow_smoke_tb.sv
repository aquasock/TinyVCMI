`timescale 1ns/1ps
`default_nettype none

module openflow_smoke_tb;
    reg clk = 1'b0;
    reg uart_rx = 1'b1;
    wire uart_tx;
    wire heartbeat;
    reg [7:0] received [0:4];
    integer i;

    always #10 clk = !clk;

    openflow_smoke dut (
        .sys_clk(clk),
        .uart_rx(uart_rx),
        .uart_tx(uart_tx),
        .heartbeat(heartbeat)
    );

    task send_byte(input [7:0] value);
        integer bit_number;
        begin
            uart_rx = 1'b0;
            #500;
            for (bit_number = 0; bit_number < 8; bit_number = bit_number + 1) begin
                uart_rx = value[bit_number];
                #500;
            end
            uart_rx = 1'b1;
            #500;
        end
    endtask

    task receive_byte(output [7:0] value);
        integer bit_number;
        begin
            @(negedge uart_tx);
            #750;
            for (bit_number = 0; bit_number < 8; bit_number = bit_number + 1) begin
                value[bit_number] = uart_tx;
                #500;
            end
            if (!uart_tx) begin
                $display("FAIL: missing UART stop bit");
                $fatal(1);
            end
            #250;
        end
    endtask

    initial begin
        #1000;
        fork
            begin
                send_byte(8'haa);
                send_byte(8'h00);
                send_byte(8'h01);
                send_byte(8'h01);
            end
            begin
                for (i = 0; i < 5; i = i + 1)
                    receive_byte(received[i]);
            end
        join

        if (received[0] !== 8'haa || received[1] !== 8'h00 ||
            received[2] !== 8'h02 || received[3] !== 8'h01 ||
            received[4] !== 8'h56) begin
            $display("FAIL: response %02x %02x %02x %02x %02x",
                     received[0], received[1], received[2], received[3],
                     received[4]);
            $fatal(1);
        end

        $display("PASS: TinyVCMI core-ID response");
        $finish;
    end

    initial begin
        #100000;
        $display("FAIL: timeout");
        $fatal(1);
    end
endmodule

`default_nettype wire
