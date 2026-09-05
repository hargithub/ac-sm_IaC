# CLAUDE.md — ac-sm_IaC

Panduan wajib untuk agent maupun manusia yang menulis kode di repo ini.
Aturan di berkas ini **menang** atas kebiasaan umum maupun default agent.

---

## 1. Apa repo ini

Proyek desain hardware (RTL) untuk FPGA. Nama repo mengandung "IaC" karena
alasan historis — isinya **bukan** infrastructure-as-code.

| | |
|---|---|
| Target FPGA | **Xilinx Artix-7**, part default `xc7a35tcpg236-1` |
| Bahasa desain | **Verilog-2001** (`.v`) |
| Bahasa testbench | **SystemVerilog prosedural** (`.sv`) |
| Simulator CI | Icarus Verilog 12 (`-g2012`) |
| Lint CI | Verilator 5.020 |
| Sintesis | Vivado non-project mode, `scripts/build.tcl` |

Ganti target FPGA cukup lewat variabel `PART` di `Makefile` — jangan sebar
nama part ke dalam RTL.

---

## 2. Struktur direktori

```
rtl/        desain Verilog (.v)          + rtl/files.f
tb/         testbench SystemVerilog (.sv) + tb/files.f
constr/     constraint Vivado (.xdc)
scripts/    build.tcl untuk Vivado
sim/        keluaran simulasi (di-gitignore)
docs/       dokumentasi
```

### Filelist itu wajib

`rtl/files.f` dan `tb/files.f` dibaca oleh **ketiga** tool: Verilator (`-f`),
Icarus (`-c`), dan Vivado (loop Tcl di `build.tcl`).

**Setiap berkas `.v` atau `.sv` baru HARUS didaftarkan di filelist yang sesuai.**
Berkas yang tidak terdaftar tidak ikut terbangun, dan kesalahannya baru ketahuan
jauh di belakang. Ini kesalahan nomor satu yang harus dihindari.

---

## 3. Perintah

```bash
make lint              # Verilator lint, top-module default: counter
make lint TOP=nama     # lint modul lain
make sim               # jalankan tb_counter
make sim TB=tb_nama    # jalankan testbench lain
make synth             # Vivado (hanya di mesin ber-Vivado, bukan di CI)
make clean
```

`make sim` keluar dengan kode bukan-nol bila testbench gagal, sehingga CI
menandainya merah. Jangan pernah membuat PR bila `make lint` atau `make sim`
masih gagal, dan **laporkan keluaran tool yang sebenarnya di badan PR** —
jangan mengarang hasil.

---

## 4. Aturan RTL (Verilog)

Modul contoh `rtl/counter.v` adalah pola rujukan. Ikuti gayanya.

1. **Reset: SINKRON, ACTIVE-HIGH**, bernama `rst`. Flip-flop Xilinx punya port
   set/reset sinkron di dalam slice, jadi reset sinkron tidak memakan LUT
   tambahan. Reset asinkron menyulitkan timing closure — jangan dipakai kecuali
   ada alasan yang ditulis di komentar. Logika yang tidak butuh nilai awal
   tertentu boleh tidak direset sama sekali; bitstream Xilinx sudah mengisi
   flip-flop saat konfigurasi.
2. **Sekuensial pakai non-blocking (`<=`)**, kombinasional pakai blocking (`=`).
   Jangan campur dalam satu blok.
3. **Hindari latch tak sengaja.** Di blok kombinasional, beri nilai default
   untuk setiap output di awal blok, atau pastikan `if`/`case` lengkap.
4. **Setiap `case` wajib punya `default`.**
5. **Clock domain crossing wajib lewat sinkronisator** — 2-flop untuk single-bit,
   handshake atau async FIFO untuk bus. Jangan pernah sampling langsung antar
   domain.
6. **Jangan pakai konstruksi non-sintesis di RTL**: delay (`#`), blok `initial`,
   `$display`, `$finish`, tipe `real`, `fork/join`. Itu hanya untuk testbench.
7. **Perhatikan lebar bit.** Hindari truncation atau extension implisit; lakukan
   secara eksplisit, misalnya `count + {{(WIDTH-1){1'b0}}, 1'b1}`.
8. **`` `default_nettype none ``** di awal berkas dan `` `default_nettype wire ``
   di akhir, supaya salah ketik nama sinyal tertangkap saat kompilasi.
9. **`` `timescale 1ns / 1ps ``** di awal setiap berkas.
10. **RTL harus portabel.** Jangan panggil primitif vendor (`BUFG`, `MMCM`,
    `IDDR`, `ISERDES`) langsung di dalam logika. Kurung di wrapper tipis
    tersendiri agar pindah seri FPGA tidak menyentuh desain.

---

## 5. Aturan testbench (SystemVerilog)

Modul contoh `tb/tb_counter.sv` adalah pola rujukan.

**Testbench wajib self-checking.** Bandingkan hasil dengan nilai harapan,
hitung kegagalan, lalu akhiri dengan `$fatal` bila ada yang gagal dan
`$display("[PASS] ...")` bila semua lolos. Testbench yang hanya membuang
waveform tanpa pemeriksaan dianggap belum selesai.

### Fitur SystemVerilog yang boleh dipakai

Daftar ini **diverifikasi langsung** terhadap Icarus Verilog 12.0 dengan
`-g2012`, bukan dari dokumentasi:

| Boleh | Tidak bisa |
|---|---|
| `logic`, `bit`, `int`, `string` | `constraint` dan `randomize()` |
| `always_ff`, `always_comb` | `covergroup` |
| `typedef`, `enum` (+`.name()`), packed `struct` | SVA konkuren (`property`, `sequence`) |
| `package` + `import` | UVM |
| `assert (...) else $error(...)` — immediate | |
| `foreach` pada array unpacked, `++`, `+=` | |
| `unique case`, `case` dengan `default` | |
| queue `[$]`, dynamic array, `interface` | |
| `class` dasar (tanpa `rand`) | |

Karena randomization dan coverage tidak tersedia di CI, tulis stimulus secara
**terarah**: daftar skenario eksplisit yang masing-masing menguji satu perilaku.
Bila nanti butuh UVM, jalankan di `xsim` Vivado pada mesin sendiri — bukan di
GitHub Actions.

---

## 6. Penamaan

| Hal | Aturan | Contoh |
|---|---|---|
| Modul dan berkas | `snake_case`, nama berkas = nama modul | `fifo_ctrl.v` |
| Testbench | awalan `tb_` | `tb_fifo_ctrl.sv` |
| Sinyal | `snake_case` | `wr_en`, `data_out` |
| Active-low | akhiran `_n` | `cs_n` |
| Parameter dan localparam | `UPPER_SNAKE` | `WIDTH`, `COUNT_MAX` |
| State enum | `UPPER_SNAKE` | `IDLE`, `RUN` |
| Clock dan reset | `clk`, `rst` | |

Tanpa akhiran arah (`_i` / `_o`) — arah sudah jelas dari deklarasi port.

---

## 7. Alur kerja agentic

Repo ini memakai loop agent GitHub Actions. Perencanaan dan pelaksanaan
dijalankan oleh dua workflow terpisah dengan model berbeda:

- `agent-plan.yml` — dipicu label `agent-task`, memakai model kuat, menghasilkan
  rencana rinci lalu memasang label `plan-posted`
- `agent-trigger.yml` — dipicu label `plan-approved`, memakai model murah, hanya
  menerjemahkan rencana menjadi kode

Setelah PR terbuka, review otomatis dan verifikasi acceptance criteria berjalan.

Selengkapnya di [docs/AGENTIC-WORKFLOW.md](docs/AGENTIC-WORKFLOW.md).

Yang perlu diingat saat mengimplementasi issue:

- Branch memakai pola `feat/acsm-issue-<nomor>`
- **Jangan** mengaktifkan auto-merge; merge dilakukan manusia
- Sertakan keluaran `make lint` dan `make sim` yang sebenarnya di badan PR
- Bila menyimpang dari rencana yang disetujui, tulis alasannya di bagian
  "Deviations from plan" pada badan PR
