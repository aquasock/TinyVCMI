`default_nettype none

`timescale 1ns/1ps
// Lockstep of ddr3_ctl against a reference version of itself (tools/sim_ddr3_lockstep.sh):
// the same random requests, with runs along a row, row changes in a bank and
// bank changes, drive both, and every output is compared every PCLK.
module tb_lock_ctl;
    reg pclk = 0; always #5 pclk = ~pclk;
    reg rst = 1;
    reg cmd_valid = 0, cmd_we = 0;
    reg [24:0] cmd_addr = 0;
    reg [255:0] cmd_wdata = 0;
    reg [255:0] dfi_rddata = 0;
    reg [3:0] dfi_rddata_valid = 0;
    wire r0, r1, v0, v1;
    wire [255:0] d0, d1, w0, w1;
    wire [3:0] cs0, cs1, ras0, ras1, cas0, cas1, we0, we1, wen0, wen1, ren0, ren1;
    wire [59:0] a0, a1; wire [11:0] b0, b1; wire [31:0] na0, na1, nr0, nr1;
    ddr3_ctl_ref o (.pclk(pclk), .rst(rst), .cmd_valid(cmd_valid), .cmd_ready(r0), .cmd_we(cmd_we),
        .cmd_addr(cmd_addr), .cmd_wdata(cmd_wdata), .rdata_valid(v0), .rdata(d0),
        .dfi_cs_n(cs0), .dfi_ras_n(ras0), .dfi_cas_n(cas0), .dfi_we_n(we0), .dfi_address(a0),
        .dfi_bank(b0), .dfi_wrdata(w0), .dfi_wrdata_en(wen0), .dfi_rddata_en(ren0),
        .dfi_rddata(dfi_rddata), .dfi_rddata_valid(dfi_rddata_valid), .n_act(na0), .n_ref(nr0));
    ddr3_ctl n (.pclk(pclk), .rst(rst), .cmd_valid(cmd_valid), .cmd_ready(r1), .cmd_we(cmd_we),
        .cmd_addr(cmd_addr), .cmd_wdata(cmd_wdata), .rdata_valid(v1), .rdata(d1),
        .dfi_cs_n(cs1), .dfi_ras_n(ras1), .dfi_cas_n(cas1), .dfi_we_n(we1), .dfi_address(a1),
        .dfi_bank(b1), .dfi_wrdata(w1), .dfi_wrdata_en(wen1), .dfi_rddata_en(ren1),
        .dfi_rddata(dfi_rddata), .dfi_rddata_valid(dfi_rddata_valid), .n_act(na1), .n_ref(nr1));
    integer cyc = 0, errs = 0, cmds = 0, acts = 0;
    reg [31:0] rnd;
    reg [24:0] last = 0;
    always @(posedge pclk) begin
        cyc <= cyc + 1;
        if (cyc == 20) rst <= 0;
        if (cyc > 20 && ({r0,v0,d0,cs0,ras0,cas0,we0,a0,b0,w0,wen0,ren0,na0,nr0} !==
                         {r1,v1,d1,cs1,ras1,cas1,we1,a1,b1,w1,wen1,ren1,na1,nr1})) begin
            errs = errs + 1;
            if (errs < 10) $display("MISMATCH cycle %0d: cs %b/%b ras %b/%b cas %b/%b we %b/%b a %h/%h b %h/%h ready %b/%b",
                cyc, cs0, cs1, ras0, ras1, cas0, cas1, we0, we1, a0[14:0], a1[14:0], b0[2:0], b1[2:0], r0, r1);
        end
        if (cs0[0] == 0) cmds = cmds + 1;
        // stimulus: hold a request until taken; mix same-row, same-bank-other-row, random
        rnd = $random;
        if (!cmd_valid || r0) begin
            cmd_valid <= (rnd[3:0] != 0) || (rnd[7:4] == 0);
            cmd_we <= rnd[8];
            case (rnd[11:9])
                0, 1, 2: cmd_addr <= {last[24:7], last[6:0] + 7'd1};          // same row, next burst
                3:       cmd_addr <= {last[24:10] + 15'd1, last[9:7], rnd[18:12]}; // same bank, another row
                4:       cmd_addr <= {last[24:10], rnd[14:12], rnd[21:15]};     // same row bits, other bank
                default: cmd_addr <= $random;
            endcase
            cmd_wdata <= {8{$random}};
        end
        if (cmd_valid && r0) last <= cmd_addr;
        dfi_rddata_valid <= {4{rnd[30]}};
        dfi_rddata <= {8{$random}};
        if (cyc == 4000000) begin
            if (errs == 0 && na0 > 1000 && nr0 > 100)
                $display("PASS  lockstep: %0d cycles, %0d commands, %0d ACTIVATEs, %0d REFRESHes, no output differs", cyc, cmds, na0, nr0);
            else
                $display("FAIL  lockstep: %0d mismatching cycles (%0d ACTIVATEs, %0d REFRESHes)", errs, na0, nr0);
            $finish;
        end
    end
endmodule

`default_nettype wire
