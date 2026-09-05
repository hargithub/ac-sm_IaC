// -----------------------------------------------------------------------------
// uart_tx - transmitter UART 8N1 tanpa parity
//
// Mengikuti pola yang ditetapkan rtl/counter.v:
//   - Verilog-2001, sintesis murni
//   - reset SINKRON, ACTIVE-HIGH (sesuai flip-flop Xilinx)
//   - `default_nettype none untuk menangkap salah ketik nama sinyal
//   - tanpa primitif vendor, portabel antar seri FPGA
//
// Format 8N1: 1 start bit rendah, 8 bit data (LSB lebih dulu), 1 stop bit tinggi.
// Baris idle = 1 (mark). FSM terdiri dari tepat 4 state: IDLE, START, DATA, STOP.
//
// KONTAK ANTARMUKA (wajib dibaca integrator):
//   - Domain clock tunggal: clk, rst, tx_start, dan tx_data HARUS sinkron ke
//     clock yang sama. Bila tx_start/tx_data berasal dari domain clock lain,
//     sinkronkan dulu di luar modul ini (2-flop untuk tx_start; handshake/FIFO
//     untuk tx_data) sebelum masuk ke sini.
//   - tx_data wajib stabil (hold) minimal 1 siklus clk SETELAH tx_start naik:
//     shift mencupliknya pada tepi naik yang sama dengan transisi ke START.
//   - Ketepatan baud: pembagi integer DIV = CLK_HZ/BAUD dibulatkan ke integer
//     terdekat (round-to-nearest, bukan floor), sehingga galat kuantisasi per
//     bit paling besar ~0,5 clock. Untuk 8N1, RX mencuplik di tengah tiap bit,
//     toleransi praktis ~±2% per bit (~±5% terakumulasi per frame 10 bit).
//     Pasangan umum aman: 100 MHz/115200 -> DIV 868, galat 0,006%;
//     50 MHz/115200 -> DIV 434, galat 0,006%. Integrator wajib memilih
//     CLK_HZ/BAUD yang memenuhi |1 - DIV*BAUD/CLK_HZ| <= 2%.
//   - CLK_HZ wajib >= 2*BAUD; bila tidak, guard DIV_RAW men-jepit DIV ke 2 agar
//     elaborasi selalu sukses. FSM tetap berjalan, tapi tiap bit berdurasi 2 clk
//     (baud aktual = CLK_HZ/2), jauh dari nilai diminta.
// -----------------------------------------------------------------------------
`timescale 1ns / 1ps
`default_nettype none

module uart_tx #(
    parameter integer CLK_HZ = 100_000_000, // 100 MHz default
    parameter integer BAUD   = 115200       // 115200 baud default
) (
    input  wire       clk,        // clock domain tunggal
    input  wire       rst,        // reset sinkron, active-high
    input  wire       tx_start,   // pulse 1 siklus; diabaikan saat tx_busy tinggi
    input  wire [7:0] tx_data,    // data yang dikirim, LSB lebih dulu
    output reg        tx_busy,    // tinggi sepanjang pengiriman, rendah saat IDLE
    output reg        tx_serial   // jalur serial; idle = 1
);

    // Pembagi baud: satu periode bit = DIV siklus clock.
    // 100e6 / 115200 = 868,055 -> dibulatkan 868 (galat 0,006%, < 2% toleransi UART).
    // Guard: dengan round-to-nearest, DIV_RAW < 2 terjadi saat CLK_HZ < 1,5*BAUD
    // (DIV_RAW = 0 atau 1), yang membuat CNT_W/$clog2 tidak valid; DIV dijepit ke
    // minimal 2 agar elaborasi selalu sukses. Catatan: pada 1,5*BAUD <= CLK_HZ < 2*BAUD
    // pembulatan sudah menghasilkan DIV_RAW = 2 (jepitan tidak aktif), namun baud aktual
    // = CLK_HZ/2 tetap jauh dari nilai diminta (kontrak header: CLK_HZ wajib >= 2*BAUD).
    localparam integer DIV_RAW  = (CLK_HZ + BAUD/2) / BAUD;  // round-to-nearest
    localparam integer DIV      = (DIV_RAW >= 2) ? DIV_RAW : 2;
    localparam integer CNT_W    = (DIV <= 1) ? 1 : $clog2(DIV);
    // DIV_M1 dipart-select ke CNT_W bit saat dipakai supaya kedua sisi == sama lebar.
    localparam integer DIV_M1 = DIV - 1;

    // Tepat 4 state sesuai rencana yang disetujui.
    localparam [1:0] IDLE  = 2'd0,
                     START = 2'd1,
                     DATA  = 2'd2,
                     STOP  = 2'd3;

    reg [1:0]       state;
    reg [CNT_W-1:0] bit_cnt;    // periode bit saat ini
    reg [2:0]       bit_idx;    // bit data ke-berapa (0..7), LSB lebih dulu
    reg [7:0]       shift;      // register geser data yang sedang dikirim

    wire bit_done = (bit_cnt == DIV_M1[CNT_W-1:0]);  // satu periode bit selesai

    always @(posedge clk) begin
        if (rst) begin
            state     <= IDLE;
            bit_cnt   <= {CNT_W{1'b0}};
            bit_idx   <= 3'd0;
            shift     <= 8'd0;
            tx_serial <= 1'b1;
            tx_busy   <= 1'b0;
        end else begin
            case (state)
                IDLE: begin
                    tx_serial <= 1'b1;   // idle line = mark
                    tx_busy   <= 1'b0;
                    bit_cnt   <= {CNT_W{1'b0}};
                    bit_idx   <= 3'd0;
                    // Mulai kirim bila diminta; tx_start diabaikan saat busy.
                    if (tx_start) begin
                        shift   <= tx_data;
                        state   <= START;
                        tx_serial <= 1'b0;   // start bit rendah
                        tx_busy   <= 1'b1;
                    end
                end

                START: begin
                    if (bit_done) begin
                        bit_cnt   <= {CNT_W{1'b0}};
                        // Mulai geser bit LSB keluar.
                        tx_serial <= shift[0];
                        state     <= DATA;
                    end else begin
                        bit_cnt   <= bit_cnt + {{(CNT_W-1){1'b0}}, 1'b1};
                    end
                end

                DATA: begin
                    if (bit_done) begin
                        bit_cnt <= {CNT_W{1'b0}};
                        if (bit_idx == 3'd7) begin
                            tx_serial <= 1'b1;   // stop bit tinggi
                            state     <= STOP;
                        end else begin
                            bit_idx   <= bit_idx + 3'd1;
                            tx_serial <= shift[bit_idx + 3'd1];
                        end
                    end else begin
                        bit_cnt <= bit_cnt + {{(CNT_W-1){1'b0}}, 1'b1};
                    end
                end

                STOP: begin
                    if (bit_done) begin
                        bit_cnt   <= {CNT_W{1'b0}};
                        bit_idx   <= 3'd0;
                        tx_serial <= 1'b1;   // idle mark
                        tx_busy   <= 1'b0;
                        state     <= IDLE;
                    end else begin
                        bit_cnt <= bit_cnt + {{(CNT_W-1){1'b0}}, 1'b1};
                    end
                end

                // FSM tak terduga -> kembali ke IDLE aman.
                default: begin
                    state     <= IDLE;
                    tx_serial <= 1'b1;
                    tx_busy   <= 1'b0;
                    bit_cnt   <= {CNT_W{1'b0}};
                    bit_idx   <= 3'd0;
                end
            endcase
        end
    end

endmodule

`default_nettype wire
