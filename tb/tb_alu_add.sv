// -----------------------------------------------------------------------------
// tb_alu_add - testbench self-checking untuk modul alu_add
//
// Mengikuti pola tb/tb_counter.sv:
//   - SystemVerilog prosedural (tanpa class, randomize, covergroup, atau SVA)
//   - self-checking: setiap skenario membandingkan hasil dengan nilai harapan
//   - keluar dengan $fatal bila ada kegagalan, supaya CI menandainya merah
//
// DUT murni kombinasional (tanpa clk/rst), jadi stimulus diberikan langsung dan
// hasil dibaca setelah jeda #1 untuk melewati delay propagasi. Tidak ada clock.
//
// Nilai harapan TIDAK ditulis sebagai literal hasil, melainkan dihitung dengan
// penjumlahan SystemVerilog 32-bit yang sama. Yang diperiksa adalah bahwa DUT
// benar-benar membuang carry-out di luar bit ke-31 (wrap-around mod 2^32) dan
// tidak merambatkannya ke lebar yang lebih besar.
// -----------------------------------------------------------------------------
`timescale 1ns / 1ps

module tb_alu_add;

    localparam int WIDTH = 32;

    logic [WIDTH-1:0] a = '0;
    logic [WIDTH-1:0] b = '0;
    logic [WIDTH-1:0] result;

    int errors = 0;

    alu_add #(.WIDTH(WIDTH)) dut (
        .a      (a),
        .b      (b),
        .result (result)
    );

    // Tulis kedua operand, beri jeda propagasi, lalu periksa result.
    task automatic check_add(input logic [WIDTH-1:0] ta,
                             input logic [WIDTH-1:0] tb,
                             input logic [WIDTH-1:0] exp,
                             input string          what);
        begin
            a = ta;
            b = tb;
            #1;
            if (result !== exp) begin
                errors++;
                $error("%s: 0x%08h + 0x%08h -> dapat 0x%08h, harusnya 0x%08h",
                       what, ta, tb, result, exp);
            end
        end
    endtask

    // Pembungkus untuk kasus di mana nilai harapan ingin dihitung di sini
    // (bukan literal), dengan tetap memakai width 32 bit yang eksplisit.
    task automatic check_add_calc(input logic [WIDTH-1:0] ta,
                                  input logic [WIDTH-1:0] tb,
                                  input string          what);
        begin
            check_add(ta, tb, (ta + tb), what);
        end
    endtask

    initial begin
        // --- Skenario 1: zero + zero ---
        check_add(32'h00000000, 32'h00000000, 32'h00000000,
                  "TC1 zero + zero");

        // --- Skenario 2: penjumlahan nilai kecil ---
        check_add(32'h00000001, 32'h00000001, 32'h00000002,
                  "TC2 kecil + kecil");

        // --- Skenario 3: operand kedua bernilai nol ---
        check_add(32'h00000001, 32'h00000000, 32'h00000001,
                  "TC3 b = 0");

        // --- Skenario 4: operand pertama bernilai nol ---
        check_add(32'h00000000, 32'h00000001, 32'h00000001,
                  "TC4 a = 0");

        // --- Skenario 5: penjumlahan sederhana ---
        check_add(32'h0000000A, 32'h00000005, 32'h0000000F,
                  "TC5 10 + 5");

        // --- Skenario 6: operand non-trivial ---
        check_add(32'h12345678, 32'h11111111, 32'h23456789,
                  "TC6 non-trivial");

        // --- Skenario 7: nilai maksimum tanpa carry ---
        check_add(32'hFFFFFFFF, 32'h00000000, 32'hFFFFFFFF,
                  "TC7 maks + 0");

        // --- Skenario 8: carry-out dan wrap-around ---
        check_add_calc(32'hFFFFFFFF, 32'h00000001,
                       "TC8 carry-out & wrap-around");

        // --- Skenario 9: overflow pada MSB (bit sign) ---
        check_add(32'h80000000, 32'h80000000, 32'h00000000,
                  "TC9 overflow MSB");

        // --- Skenario 10: transisi bit sign ---
        check_add(32'h7FFFFFFF, 32'h00000001, 32'h80000000,
                  "TC10 transisi bit sign");

        // --- Skenario 11: pola bit komplementer ---
        check_add_calc(32'hAAAAAAAA, 32'h55555555,
                       "TC11 pola komplementer");

        // --- Skenario 12: carry-out maksimum ---
        check_add_calc(32'hFFFFFFFF, 32'hFFFFFFFF,
                       "TC12 carry-out maksimum");

        // --- Skenario 13: carry-out dibuang, bukan diperluas (anti-regresi) ---
        // Bila implementasi keliru memakai lebar >32 bit, hasil ini akan menjadi
        // 33-bit dan bit ke-32 akan tampak. Ekspresi di bawah dipaksa 32-bit.
        check_add(32'hFFFFFFFF, 32'hFFFFFFFF, 32'hFFFFFFFE,
                  "TC13 carry-out benar-benar dibuang");

        // --- Skenario 14: result tidak bergantung pada nilai lama (bukan latch) ---
        // Ubah a saja, b tetap; result harus ikut berubah seketika.
        a = 32'h00000001;
        b = 32'h00000002;
        #1;
        a = 32'h00000010;
        #1;
        if (result !== 32'h00000012) begin
            errors++;
            $error("TC14 result tidak responsif terhadap perubahan a: dapat 0x%08h",
                   result);
        end
        // Ubah b saja, a tetap.
        b = 32'h00000020;
        #1;
        if (result !== 32'h00000030) begin
            errors++;
            $error("TC14 result tidak responsif terhadap perubahan b: dapat 0x%08h",
                   result);
        end

        if (errors == 0) begin
            $display("[PASS] tb_alu_add - seluruh skenario lolos");
            $finish;
        end else begin
            $fatal(1, "[FAIL] tb_alu_add - %0d kegagalan", errors);
        end
    end

endmodule
