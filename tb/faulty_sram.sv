`timescale 1ns/1ps
// Behavioural SRAM with one injectable functional fault (test bench only).
//
//  kind 0  none
//       1  SA0   cell (a1,b1) stuck at 0
//       2  SA1   cell (a1,b1) stuck at 1
//       3  TFu   cell (a1,b1) cannot make a 0->1 transition
//       4  TFd   cell (a1,b1) cannot make a 1->0 transition
//       5  CFin  any transition of aggressor (a2,b2) inverts victim (a1,b1)
//       6  CFid  a 0->1 transition of the aggressor forces the victim to `val`
//       7  CFid  a 1->0 transition of the aggressor forces the victim to `val`
//       8  AF    address a1 is decoded as a2 (cell a1 is unreachable)
//       9  CFst  victim is forced to `val` while the aggressor holds 1
module faulty_sram #(
    parameter integer AW = 8,
    parameter integer DW = 8
) (
    input  wire          clk,
    input  wire          ce,
    input  wire          we,
    input  wire [AW-1:0] addr,
    input  wire [DW-1:0] wdata,
    output reg  [DW-1:0] rdata
);
    reg [DW-1:0] mem [0:(1<<AW)-1];

    integer kind = 0, a1 = 0, b1 = 0, a2 = 0, b2 = 0;
    reg     val = 0;

    wire [AW-1:0] eff = (kind == 8 && addr == a1[AW-1:0]) ? a2[AW-1:0] : addr;

    reg [DW-1:0] oldw, neww;
    reg          agg_old, agg_new;

    task automatic enforce;   // static faults that hold regardless of the operation
        begin
            if (kind == 1) mem[a1][b1] = 1'b0;
            if (kind == 2) mem[a1][b1] = 1'b1;
            if (kind == 9 && mem[a2][b2]) mem[a1][b1] = val;
        end
    endtask

    always @(posedge clk) if (ce) begin
        if (we) begin
            oldw = mem[eff];
            neww = wdata;
            if (kind == 3 && eff == a1 && !oldw[b1] &&  neww[b1]) neww[b1] = 1'b0;
            if (kind == 4 && eff == a1 &&  oldw[b1] && !neww[b1]) neww[b1] = 1'b1;
            mem[eff] = neww;
            if (kind >= 5 && kind <= 7 && eff == a2) begin
                agg_old = oldw[b2];
                agg_new = neww[b2];
                if (kind == 5 && agg_old !== agg_new)  mem[a1][b1] = ~mem[a1][b1];
                if (kind == 6 && !agg_old &&  agg_new) mem[a1][b1] = val;
                if (kind == 7 &&  agg_old && !agg_new) mem[a1][b1] = val;
            end
            enforce;
        end else begin
            enforce;
            rdata <= mem[eff];
        end
    end
endmodule
