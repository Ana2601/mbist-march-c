// BIST collar: multiplexes the memory pins between functional logic and the
// MBIST controller. In a real flow the SRAM macro sits behind this wrapper.
module mbist_wrapper #(
    parameter integer AW = 8,
    parameter integer DW = 8
) (
    input  wire          clk,
    input  wire          rst_n,

    // test control
    input  wire          bist_start,
    output wire          bist_busy,
    output wire          bist_done,
    output wire          bist_fail,
    output wire [AW-1:0] bist_fail_addr,
    output wire [DW-1:0] bist_fail_exp,
    output wire [DW-1:0] bist_fail_got,
    output wire [2:0]    bist_fail_elem,
    output wire [15:0]   bist_fail_count,

    // functional port
    input  wire          fn_ce,
    input  wire          fn_we,
    input  wire [AW-1:0] fn_addr,
    input  wire [DW-1:0] fn_wdata,
    output wire [DW-1:0] fn_rdata,

    // to the SRAM macro
    output wire          ram_ce,
    output wire          ram_we,
    output wire [AW-1:0] ram_addr,
    output wire [DW-1:0] ram_wdata,
    input  wire [DW-1:0] ram_rdata
);
    wire          b_ce, b_we;
    wire [AW-1:0] b_addr;
    wire [DW-1:0] b_wdata;

    mbist_ctrl #(.AW(AW), .DW(DW)) u_ctrl (
        .clk(clk), .rst_n(rst_n), .start(bist_start),
        .busy(bist_busy), .done(bist_done), .fail(bist_fail),
        .fail_addr(bist_fail_addr), .fail_exp(bist_fail_exp), .fail_got(bist_fail_got),
        .fail_elem(bist_fail_elem), .fail_count(bist_fail_count),
        .mem_ce(b_ce), .mem_we(b_we), .mem_addr(b_addr), .mem_wdata(b_wdata), .mem_rdata(ram_rdata)
    );

    assign ram_ce    = bist_busy ? b_ce    : fn_ce;
    assign ram_we    = bist_busy ? b_we    : fn_we;
    assign ram_addr  = bist_busy ? b_addr  : fn_addr;
    assign ram_wdata = bist_busy ? b_wdata : fn_wdata;
    assign fn_rdata  = ram_rdata;
endmodule
