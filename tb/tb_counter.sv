// -----------------------------------------------------------------------------
// tb_counter - testbench self-checking untuk modul counter
//
// Menetapkan pola testbench repo ini:
//   - SystemVerilog prosedural (tanpa class, randomize, covergroup, atau SVA)
//   - self-checking: setiap skenario membandingkan hasil dengan nilai harapan
//   - keluar dengan $fatal bila ada kegagalan, supaya CI menandainya merah
// -----------------------------------------------------------------------------
`timescale 1ns / 1ps

module tb_counter;

    localparam int WIDTH    = 4;
    localparam int MAX_VAL  = (1 << WIDTH) - 1;
    localparam time TCLK    = 10ns;

    logic             clk = 1'b0;
    logic             rst = 1'b1;
    logic             en  = 1'b0;
    logic [WIDTH-1:0] count;
    logic             tc;

    int errors = 0;

    counter #(.WIDTH(WIDTH)) dut (
        .clk   (clk),
        .rst   (rst),
        .en    (en),
        .count (count),
        .tc    (tc)
    );

    always #(TCLK/2) clk = ~clk;

    task automatic check_eq(input int got, input int exp, input string what);
        if (got !== exp) begin
            errors++;
            $error("%s: dapat %0d, harusnya %0d", what, got, exp);
        end
    endtask

    initial begin
        // --- Skenario 1: reset memaksa cacahan ke nol ---
        en = 1'b0;
        repeat (2) @(posedge clk);
        #1 check_eq(count, 0, "reset");

        // --- Skenario 2: tidak mencacah saat en rendah ---
        rst = 1'b0;
        repeat (3) @(posedge clk);
        #1 check_eq(count, 0, "en rendah menahan cacahan");

        // --- Skenario 3: mencacah naik saat en tinggi ---
        en = 1'b1;
        repeat (5) @(posedge clk);
        #1 check_eq(count, 5, "cacah naik 5 siklus");

        // --- Skenario 4: terminal count muncul tepat di nilai penuh ---
        repeat (MAX_VAL - 5) @(posedge clk);
        #1 check_eq(count, MAX_VAL, "mencapai nilai penuh");
        #1 check_eq(tc, 1'b1, "tc aktif di nilai penuh");

        // --- Skenario 5: berputar kembali ke nol ---
        @(posedge clk);
        #1 check_eq(count, 0, "wrap ke nol");
        #1 check_eq(tc, 1'b0, "tc nonaktif setelah wrap");

        // --- Skenario 6: reset di tengah jalan ---
        repeat (3) @(posedge clk);
        rst = 1'b1;
        @(posedge clk);
        #1 check_eq(count, 0, "reset di tengah pencacahan");

        if (errors == 0) begin
            $display("[PASS] tb_counter - seluruh skenario lolos");
            $finish;
        end else begin
            $fatal(1, "[FAIL] tb_counter - %0d kegagalan", errors);
        end
    end

endmodule
