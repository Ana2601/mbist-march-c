`timescale 1ns/1ps
// Fault-injection campaign for the MBIST controller.
//  1. fault-free memory must pass, and functional access must work afterwards
//  2. for every fault class, inject many random single faults and count how
//     many the march test detects  ->  fault-coverage table
module tb_mbist;
    localparam integer AW = 6, DW = 8, DEPTH = 1 << AW, N_PER_CLASS = 150;

    reg clk = 0, rst_n = 0;
    always #5 clk = ~clk;

    reg           bist_start = 0;
    wire          bist_busy, bist_done, bist_fail;
    wire [AW-1:0] bist_fail_addr;
    wire [DW-1:0] bist_fail_exp, bist_fail_got;
    wire [2:0]    bist_fail_elem;
    wire [15:0]   bist_fail_count;
    reg           fn_ce = 0, fn_we = 0;
    reg  [AW-1:0] fn_addr = 0;
    reg  [DW-1:0] fn_wdata = 0;
    wire [DW-1:0] fn_rdata;
    wire          ram_ce, ram_we;
    wire [AW-1:0] ram_addr;
    wire [DW-1:0] ram_wdata, ram_rdata;

    mbist_wrapper #(.AW(AW), .DW(DW)) dut (.*);
    faulty_sram   #(.AW(AW), .DW(DW)) ram (.clk(clk), .ce(ram_ce), .we(ram_we), .addr(ram_addr),
                                           .wdata(ram_wdata), .rdata(ram_rdata));

    integer cycles;
    task automatic run_bist;
        begin
            @(posedge clk); bist_start <= 1;
            @(posedge clk); bist_start <= 0;
            cycles = 0;
            @(posedge clk);
            while (!bist_done) begin @(posedge clk); cycles = cycles + 1; end
        end
    endtask

    integer k, n, i, errors = 0, det, total_det = 0, total_inj = 0, same_word;
    integer elem_hist [0:5];
    string  names [1:9];

    initial begin
        names[1] = "stuck-at-0";            names[2] = "stuck-at-1";
        names[3] = "transition 0->1";       names[4] = "transition 1->0";
        names[5] = "coupling (inversion)";  names[6] = "coupling (idempotent, rise)";
        names[7] = "coupling (idempotent, fall)"; names[8] = "address decoder";
        names[9] = "coupling (state)";
        for (i = 0; i < 6; i = i + 1) elem_hist[i] = 0;
        for (i = 0; i < DEPTH; i = i + 1) ram.mem[i] = $urandom;
        repeat (4) @(posedge clk);
        rst_n = 1;

        // ---- 1. fault-free run
        run_bist;
        $display("fault-free: fail=%b, %0d cycles (expected NBG*11*2^AW = %0d)", bist_fail, cycles, 4 * 11 * DEPTH);
        if (bist_fail) begin errors = errors + 1; $display("ERROR: good memory failed BIST"); end
        if (cycles > 4 * 11 * DEPTH + 4) begin errors = errors + 1; $display("ERROR: test longer than expected"); end

        // functional port is transparent when BIST is idle
        for (i = 0; i < DEPTH; i = i + 1) begin
            @(posedge clk); fn_ce <= 1; fn_we <= 1; fn_addr <= i[AW-1:0]; fn_wdata <= 8'(i * 7 + 3);
        end
        for (i = 0; i <= DEPTH; i = i + 1) begin
            @(posedge clk); fn_we <= 0; fn_addr <= i[AW-1:0];
            if (i > 0) begin
                #1;
                if (fn_rdata !== 8'((i - 1) * 7 + 3)) begin
                    errors = errors + 1;
                    if (errors < 5) $display("ERROR: functional read %0d got %h", i - 1, fn_rdata);
                end
            end
        end
        fn_ce <= 0;

        // ---- 2. fault-injection campaign
        $display("\n  fault class                    injected  detected  coverage");
        for (k = 1; k <= 9; k = k + 1) begin
            det = 0;
            for (n = 0; n < N_PER_CLASS; n = n + 1) begin
                ram.kind = k;
                ram.a1 = $urandom_range(0, DEPTH - 1);  ram.b1 = $urandom_range(0, DW - 1);
                // half of the coupling faults are between two bits of the same word
                same_word = (k != 8) && ($urandom_range(0, 1) == 1);
                ram.a2 = same_word ? ram.a1 : $urandom_range(0, DEPTH - 1);
                ram.b2 = $urandom_range(0, DW - 1);
                if (ram.a2 == ram.a1 && (k == 8 || ram.b2 == ram.b1)) begin
                    if (k == 8) ram.a2 = (ram.a1 + 1 + $urandom_range(0, DEPTH - 2)) % DEPTH;
                    else        ram.b2 = (ram.b1 + 1 + $urandom_range(0, DW - 2)) % DW;
                end
                ram.val = $urandom_range(0, 1);
                run_bist;
                if (bist_fail) begin
                    det = det + 1;
                    elem_hist[bist_fail_elem] = elem_hist[bist_fail_elem] + 1;
                    if (bist_fail_exp === bist_fail_got || bist_fail_count == 0) begin
                        errors = errors + 1; $display("ERROR: inconsistent failure report");
                    end
                end else if (errors < 10)
                    $display("    escape: %s victim=(%0d,%0d) aggressor=(%0d,%0d) val=%b",
                             names[k], ram.a1, ram.b1, ram.a2, ram.b2, ram.val);
            end
            $display("  %-30s %8d  %8d  %7.1f%%", names[k], N_PER_CLASS, det, 100.0 * det / N_PER_CLASS);
            total_det = total_det + det; total_inj = total_inj + N_PER_CLASS;
        end
        ram.kind = 0;
        $display("  %-30s %8d  %8d  %7.1f%%", "TOTAL", total_inj, total_det, 100.0 * total_det / total_inj);
        $display("  first detection by march element: M1=%0d M2=%0d M3=%0d M4=%0d M5=%0d",
                 elem_hist[1], elem_hist[2], elem_hist[3], elem_hist[4], elem_hist[5]);

        if (errors != 0 || total_det != total_inj) $fatal(1, "TEST FAILED");
        $display("TEST PASSED");
        $finish;
    end
endmodule
