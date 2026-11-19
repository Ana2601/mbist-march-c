// Memory BIST controller implementing the March C- algorithm:
//
//   M0 any(w0); M1 up(r0,w1); M2 up(r1,w0); M3 down(r0,w1); M4 down(r1,w0); M5 any(r0)
//
// The whole march is repeated for NBG data backgrounds (solid, 0101.., 0011..,
// 00001111.., ...) so coupling faults between bits of the same word are also
// sensitised. "0" is the background word, "1" its complement.
//
// Targets a synchronous single-port SRAM with one cycle of read latency.
// Test length: NBG * 11 * 2^AW cycles (a read and a write of the same cell
// share two cycles).
module mbist_ctrl #(
    parameter integer AW  = 8,
    parameter integer DW  = 8,
    parameter integer NBG = $clog2(DW) + 1
) (
    input  wire          clk,
    input  wire          rst_n,
    input  wire          start,
    output reg           busy,
    output reg           done,          // stays high until the next start
    output reg           fail,          // valid with done
    output reg  [AW-1:0] fail_addr,     // first failing address
    output reg  [DW-1:0] fail_exp,
    output reg  [DW-1:0] fail_got,
    output reg  [2:0]    fail_elem,     // march element (0..5) that caught it
    output reg  [15:0]   fail_count,    // saturating count of miscompares

    output reg           mem_ce,
    output reg           mem_we,
    output reg  [AW-1:0] mem_addr,
    output reg  [DW-1:0] mem_wdata,
    input  wire [DW-1:0] mem_rdata
);
    localparam [1:0] S_IDLE = 2'd0, S_RD = 2'd1, S_CMP = 2'd2, S_WR = 2'd3;
    localparam integer BW = (NBG > 1) ? $clog2(NBG) : 1;

    reg [1:0]    st;
    reg [2:0]    elem;
    reg [AW-1:0] cnt;                    // position within the element
    reg [BW-1:0] bg;

    // data background: bit i is bit (bg-1) of i, e.g. bg=1 -> 0101.., bg=2 -> 0011..
    function automatic [DW-1:0] background(input [BW-1:0] n);
        integer i;
        begin
            for (i = 0; i < DW; i = i + 1)
                background[i] = (n == 0) ? 1'b0 : ((i >> (n - 1)) & 1) != 0;
        end
    endfunction

    // march element decode
    wire elem_down  = (elem == 3'd3) || (elem == 3'd4);
    wire elem_read  = (elem != 3'd0);
    wire elem_write = (elem != 3'd5);
    wire rd_one     = (elem == 3'd2) || (elem == 3'd4);          // expect "1"
    wire wr_one     = (elem == 3'd1) || (elem == 3'd3);          // write "1"

    wire [DW-1:0] bg_word = background(bg);
    wire [DW-1:0] exp     = rd_one ? ~bg_word : bg_word;
    wire [DW-1:0] wval    = wr_one ? ~bg_word : bg_word;
    wire [AW-1:0] addr    = elem_down ? ~cnt : cnt;
    wire          last_addr = (cnt == {AW{1'b1}});
    wire          miscompare = (mem_rdata != exp);

    task automatic advance;
        begin
            cnt <= cnt + 1'b1;
            if (last_addr) begin
                if (elem == 3'd5) begin
                    elem <= 3'd0;
                    if (bg == BW'(NBG - 1)) begin
                        st <= S_IDLE; busy <= 1'b0; done <= 1'b1;
                    end else begin
                        bg <= bg + 1'b1; st <= S_WR;
                    end
                end else begin
                    elem <= elem + 3'd1;
                    st   <= S_RD;               // elements 1..5 all start with a read
                end
            end else begin
                st <= elem_read ? S_RD : S_WR;
            end
        end
    endtask

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st <= S_IDLE; elem <= 3'd0; cnt <= {AW{1'b0}}; bg <= {BW{1'b0}};
            busy <= 1'b0; done <= 1'b0; fail <= 1'b0;
            fail_addr <= {AW{1'b0}}; fail_exp <= {DW{1'b0}}; fail_got <= {DW{1'b0}};
            fail_elem <= 3'd0; fail_count <= 16'd0;
        end else begin
            case (st)
                S_IDLE: if (start) begin
                    busy <= 1'b1; done <= 1'b0; fail <= 1'b0; fail_count <= 16'd0;
                    elem <= 3'd0; cnt <= {AW{1'b0}}; bg <= {BW{1'b0}};
                    st   <= S_WR;
                end

                S_WR: advance;                  // write-only element (M0)

                S_RD: st <= S_CMP;              // read issued, data arrives next cycle

                default: begin                  // S_CMP: check, and write the same cell
                    if (miscompare) begin
                        if (!fail) begin
                            fail <= 1'b1; fail_addr <= addr; fail_exp <= exp;
                            fail_got <= mem_rdata; fail_elem <= elem;
                        end
                        if (fail_count != 16'hFFFF) fail_count <= fail_count + 16'd1;
                    end
                    advance;
                end
            endcase
        end
    end

    // memory port (combinational from the FSM state)
    always @* begin
        mem_addr  = addr;
        mem_wdata = wval;
        mem_ce    = 1'b0;
        mem_we    = 1'b0;
        case (st)
            S_WR:    begin mem_ce = 1'b1; mem_we = 1'b1; end
            S_RD:    begin mem_ce = 1'b1; end
            S_CMP:   begin mem_ce = elem_write; mem_we = elem_write; end
            default: ;
        endcase
    end
endmodule
