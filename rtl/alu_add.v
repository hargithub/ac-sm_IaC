// -----------------------------------------------------------------------------
// alu_add - penjumlah 32-bit kombinasional (operasi ADD RV32I)
//
// Mengikuti pola yang ditetapkan rtl/counter.v:
//   - Verilog-2001, sintesis murni
//   - `default_nettype none untuk menangkap salah ketik nama sinyal
//   - tanpa primitif vendor, portabel antar seri FPGA
//   - tanpa latch (murni assign, tidak ada always)
//
// KONTAK ANTARMUKA (wajib dibaca integrator):
//   - Modul ini COMBINATIONAL murni: tidak ada clk, rst, enable, atau handshake.
//     result berubah mengikuti a/b tanpa menunggu tepi clock. Integrator yang
//     butuh nilai terdaftar wajib menambahkan register di luar modul ini; jangan
//     memasang logika sekuensial di dalamnya.
//   - result = (a + b) mod 2^WIDTH. Carry-out di luar bit ke-(WIDTH-1) DIBUANG
//     secara eksplisit oleh lebar output, bukan dengan pemotongan implisit.
//     Ini persis semantik ADD pada RV32I (XLEN = 32).
//   - Bit-pattern hasil identik untuk interpretasi unsigned maupun signed
//     (two's complement); modul ini tidak menghasilkan flag overflow.
//   - WIDTH default 32 (RV32I). Parameter disediakan agar modul bisa dipakai
//     ulang oleh varian XLEN lain (mis. RV64I) tanpa mengubah berkas ini.
// -----------------------------------------------------------------------------
`timescale 1ns / 1ps
`default_nettype none

module alu_add #(
    parameter integer WIDTH = 32
) (
    input  wire [WIDTH-1:0] a,      // operand pertama (RV32I: rs1)
    input  wire [WIDTH-1:0] b,      // operand kedua  (RV32I: rs2)
    output wire [WIDTH-1:0] result  // (a + b) mod 2^WIDTH, carry-out dibuang
);

    // Ekspresi self-determined: kedua operand sudah selebar WIDTH, jadi hasil
    // penjumlahan juga WIDTH bit dan bit carry di atas bit ke-(WIDTH-1) hilang
    // sebelum sampai ke result. Tidak ada truncation/extension implisit.
    assign result = a + b;

endmodule

`default_nettype wire
