// -----------------------------------------------------------------------------
// tb_shift_alu - testbench self-checking untuk modul shift_alu
//
// Mengikuti pola tb/tb_counter.sv:
//   - SystemVerilog prosedural (tanpa class, randomize, covergroup, atau SVA)
//   - self-checking: setiap skenario membandingkan hasil dengan nilai harapan
//   - keluar dengan $fatal bila ada kegagalan, supaya CI menandainya merah
//
// CATATAN PENTING soal clock dan reset:
//   shift_alu adalah modul KOMBINASIONAL murni: tidak ada port clk dan tidak ada
//   port rst (sesuai acceptance criteria dan kontrak modul). Karena itu:
//     - Testbench ini tidak membangkitkan clock sama sekali, dan tidak ada satu
//       pun pemeriksaan yang menunggu tepi clock.
//     - Skenario "verifikasi reset" pada rencana tidak dapat dijalankan: tidak
//       ada state yang bisa direset, karena result adalah fungsi murni dari
//       input. Sebagai gantinya, Skenario 1 membuktikan sifat kombinasional itu
//       secara langsung -- result berubah segera setelah input berubah, tanpa
//       tepi clock. Kegagalan reset tidak mungkin terjadi pada modul tanpa state.
//
// Nilai harapan dihitung oleh ref_shift(), model referensi yang bekerja BIT PER
// BIT memakai indeks dan mask, BUKAN memakai operator <<, >>, atau >>>. Jadi
// model ini tidak ikut salah bila RTL salah memakai operator.
// -----------------------------------------------------------------------------
`timescale 1ns / 1ps

module tb_shift_alu;

    // Kode operasi, disalin dari kontrak modul (bukan diambil dari RTL).
    localparam logic [1:0] SLL     = 2'b00;
    localparam logic [1:0] SRL     = 2'b01;
    localparam logic [1:0] SRA     = 2'b10;
    localparam logic [1:0] INVALID = 2'b11;

    logic [31:0] a;       // operand
    logic [4:0]  shamt;   // jumlah geser
    logic [1:0]  op;      // kode operasi
    logic [31:0] result;  // keluaran DUT

    int errors = 0;

    shift_alu dut (
        .a      (a),
        .shamt  (shamt),
        .op     (op),
        .result (result)
    );

    // Model referensi bit-per-bit. r diinisialisasi nol, sehingga bit yang
    // "kosong" otomatis terisi nol untuk SLL dan SRL (zero-fill). Untuk SRA,
    // bit yang kosong diisi ulang dengan bit tanda a[31] pada loop kedua.
    // op tak dikenal jatuh ke default dan meninggalkan r = 0.
    function automatic logic [31:0] ref_shift(input logic [31:0] av,
                                              input logic [4:0]  shv,
                                              input logic [1:0]  opv);
        logic [31:0] r;
        int          sh_i;
        int          dst;
        begin
            r    = 32'd0;
            sh_i = int'(shv);

            case (opv)
                SLL: begin
                    // a[i] pindah ke bit (i + sh).
                    for (int i = 0; i < 32; i++) begin
                        dst = i + sh_i;
                        if (dst < 32) r[dst] = av[i];
                    end
                end

                SRL: begin
                    // a[i] pindah ke bit (i - sh); sisanya tetap nol.
                    for (int i = 0; i < 32; i++) begin
                        dst = i - sh_i;
                        if (dst >= 0) r[dst] = av[i];
                    end
                end

                SRA: begin
                    // Sama seperti SRL, lalu bit tertinggi diisi bit tanda.
                    // Saat sh = 0 loop kedua tidak menulis apa pun.
                    for (int i = 0; i < 32; i++) begin
                        dst = i - sh_i;
                        if (dst >= 0) r[dst] = av[i];
                    end
                    for (int j = 0; j < 32; j++) begin
                        if (j >= 32 - sh_i) r[j] = av[31];
                    end
                end

                default: r = 32'd0;
            endcase

            return r;
        end
    endfunction

    // Set input, beri waktu logika kombinasional menetap, lalu bandingkan
    // result terhadap model referensi. Tidak ada tepi clock di sini.
    task automatic check_shift(input logic [31:0] a_v,
                               input logic [4:0]  sh_v,
                               input logic [1:0]  op_v,
                               input string       what);
        logic [31:0] exp;
        begin
            a     = a_v;
            shamt = sh_v;
            op    = op_v;
            #1;
            exp = ref_shift(a_v, sh_v, op_v);
            if (result !== exp) begin
                errors++;
                $error("%s: a=%08h shamt=%0d op=%02b -> result=%08h, harusnya %08h",
                       what, a_v, sh_v, op_v, result, exp);
            end
        end
    endtask

    initial begin
        // --- Skenario 1: modul kombinasional, hasil ikut input tanpa clk ---
        // Tidak ada posedge di seluruh testbench ini. Bila result ternyata
        // ter-register, seluruh pemeriksaan berikutnya pasti gagal.
        check_shift(32'h0000_0000, 5'd0, SLL, "nilai awal: a=0 -> result=0");
        check_shift(32'hFFFF_FFFF, 5'd0, SLL, "a berubah -> result ikut berubah");

        // --- Skenario 2: SLL (logical left shift) ---
        check_shift(32'h0000_0001, 5'd0,  SLL, "SLL shamt=0 tidak menggeser");
        check_shift(32'h0000_0001, 5'd4,  SLL, "SLL 1 << 4");
        check_shift(32'h0000_0001, 5'd1,  SLL, "SLL 1 << 1");
        check_shift(32'hFFFF_FFFF, 5'd31, SLL, "SLL batas: 0xFFFFFFFF << 31");
        check_shift(32'h0000_0001, 5'd31, SLL, "SLL 1 << 31 (bit pindah ke MSB)");
        check_shift(32'h8000_0000, 5'd1,  SLL, "SLL MSB keluar dari batas");
        check_shift(32'h0000_0000, 5'd31, SLL, "SLL operand nol");

        // --- Skenario 3: SRL (logical right shift, zero-fill) ---
        check_shift(32'h8000_0000, 5'd0,  SRL, "SRL shamt=0 tidak menggeser");
        check_shift(32'h8000_0000, 5'd1,  SRL, "SRL MSB=1 diisi nol, bukan tanda");
        check_shift(32'h8000_0000, 5'd4,  SRL, "SRL 0x80000000 >> 4");
        check_shift(32'hFFFF_FFFF, 5'd31, SRL, "SRL batas: 0xFFFFFFFF >> 31");
        check_shift(32'hFFFF_FFFF, 5'd1,  SRL, "SRL 0xFFFFFFFF >> 1 (MSB jadi 0)");
        check_shift(32'h0000_0000, 5'd31, SRL, "SRL operand nol");

        // --- Skenario 4: SRA (arithmetic right shift, sign extension) ---
        check_shift(32'h4000_0000, 5'd2,  SRA, "SRA operan positif >> 2");
        check_shift(32'h8000_0000, 5'd0,  SRA, "SRA shamt=0 tidak menggeser");
        check_shift(32'h8000_0000, 5'd1,  SRA, "SRA MSB=1: sign extension");
        check_shift(32'h8000_0000, 5'd4,  SRA, "SRA negatif >> 4");
        check_shift(32'h8000_0000, 5'd31, SRA, "SRA batas: negatif >> 31 = semua 1");
        check_shift(32'hFFFF_FFFF, 5'd31, SRA, "SRA 0xFFFFFFFF >> 31 tetap 0xFFFFFFFF");
        check_shift(32'h7FFF_FFFF, 5'd31, SRA, "SRA 0x7FFFFFFF >> 31 = 0");
        check_shift(32'h0000_0000, 5'd31, SRA, "SRA operand nol");

        // --- Skenario 5: opcode tidak dikenal -> result = 32'b0 ---
        check_shift(32'h1234_5678, 5'd5,  INVALID, "opcode 2'b11 -> 0");
        check_shift(32'hFFFF_FFFF, 5'd0,  INVALID, "opcode 2'b11, shamt=0 -> 0");
        check_shift(32'hFFFF_FFFF, 5'd31, INVALID, "opcode 2'b11, shamt=31 -> 0");
        check_shift(32'h0000_0000, 5'd0,  INVALID, "opcode 2'b11, operand 0 -> 0");

        // --- Skenario 6: seluruh nilai shamt 0..31 untuk tiap operasi ---
        // Acceptance criteria menuntut shamt[4:0] terpakai penuh (0 sampai 31).
        // Operand dipilih yang punya MSB=1 dan pola bit berselang-seling supaya
        // sign extension dan zero-fill sama-sama terlihat.
        for (int s = 0; s < 32; s++) begin
            for (int o = 0; o < 4; o++) begin
                check_shift(32'hA5A5_5A5A, s[4:0], o[1:0], "sweep shamt 0..31 pola A5A55A5A");
                check_shift(32'h8000_0001, s[4:0], o[1:0], "sweep shamt 0..31 pola 80000001");
                check_shift(32'hFFFF_FFFF, s[4:0], o[1:0], "sweep shamt 0..31 pola FFFFFFFF");
                check_shift(32'h0000_0000, s[4:0], o[1:0], "sweep shamt 0..31 pola 00000000");
            end
        end

        if (errors == 0) begin
            $display("[PASS] tb_shift_alu - seluruh skenario lolos");
            $finish;
        end else begin
            $fatal(1, "[FAIL] tb_shift_alu - %0d kegagalan", errors);
        end
    end

endmodule
