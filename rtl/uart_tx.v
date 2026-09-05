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
    localparam integer DIV   = CLK_HZ / BAUD;
    localparam integer CNT_W = (DIV <= 1) ? 1 : $clog2(DIV);
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
