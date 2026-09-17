// -----------------------------------------------------------------------------
// shift_alu - ALU geser sederhana 32-bit
//
// Mengikuti pola yang ditetapkan rtl/counter.v:
//   - Verilog-2001, sintesis murni
//   - `default_nettype none untuk menangkap salah ketik nama sinyal
//   - tanpa primitif vendor, portabel antar seri FPGA
//   - gaya port mengikuti rtl/counter.v: lebar 32-bit dan 5-bit ditulis harfiah
//     (bukan parameter), supaya tabel port cocok persis dengan kontrak modul
//
// Modul ini KOMBINASIONAL murni: tidak ada clk, tidak ada rst, dan tidak ada
// state internal. Hasil berubah langsung mengikuti input tanpa menunggu tepi
// clock. Karena itu modul ini tidak melewati clock domain mana pun dan tidak
// memerlukan sinkronisator di dalamnya.
//
// KONTAK ANTARMUKA (wajib dibaca integrator):
//   - a, shamt, dan op adalah satu-satunya input. Tidak ada enable: setiap
//     perubahan input langsung tercermin di result.
//   - Bila a/shamt/op datang dari domain clock lain, sinyalnya harus dibuat
//     stabil lebih dulu (register di domain asal, atau handshake/FIFO untuk bus
//     multi-bit). Modul ini tidak menyediakan sinkronisator apa pun.
//   - shamt dipakai seluruh 5 bitnya, sehingga mendukung geser 0 sampai 31.
//   - op yang tidak dikenali (2'b11) menghasilkan result = 32'b0.
// -----------------------------------------------------------------------------
`timescale 1ns / 1ps
`default_nettype none

module shift_alu (
    input  wire [31:0] a,      // operand 32-bit
    input  wire [4:0]  shamt,  // jumlah geser, 0..31 (seluruh bit dipakai)
    input  wire [1:0]  op,     // kode operasi
    output reg  [31:0] result  // hasil geser
);

    // Kode operasi. UPPER_SNAKE sesuai konvensi penamaan CLAUDE.md bagian 6.
    localparam [1:0] SLL     = 2'b00,  // logical left shift
                     SRL     = 2'b01,  // logical right shift, isi nol
                     SRA     = 2'b10,  // arithmetic right shift, sign extension
                     INVALID = 2'b11;  // tak dikenal -> result = 0

    // Kombinasional murni. Nilai default diberikan di awal blok untuk setiap
    // output, sehingga tidak ada jalur yang menyisakan nilai lama (latch).
    always_comb begin
        result = 32'd0;

        case (op)
            // Geser kiri logis: 0 masuk dari kanan.
            SLL: result = a << shamt;

            // Geser kanan logis: 0 masuk dari kiri.
            SRL: result = a >> shamt;

            // Geser kanan aritmetika: bit tanda (a[31]) direplikasi dari kiri.
            // >>> pada nilai bertanda mengisi bit kosong dengan bit tanda.
            SRA: result = $signed(a) >>> shamt;

            // Opcode tak dikenal -> nol.
            INVALID: result = 32'd0;

            // Setiap case wajib punya default (CLAUDE.md bagian 4 butir 4).
            // Cabang ini menangkap nilai X/Z saat simulasi dan sisa kombinasi
            // yang tidak terduga, sehingga result tidak pernah menyisakan nilai
            // lama (tidak ada latch).
            default: result = 32'd0;
        endcase
    end

endmodule

`default_nettype wire
