// -----------------------------------------------------------------------------
// counter - pencacah biner dengan enable dan terminal count
//
// Modul contoh yang menetapkan pola untuk seluruh RTL di repo ini:
//   - Verilog-2001, sintesis murni
//   - reset SINKRON, ACTIVE-HIGH (sesuai flip-flop Xilinx)
//   - `default_nettype none untuk menangkap salah ketik nama sinyal
//   - tanpa primitif vendor, portabel antar seri FPGA
// -----------------------------------------------------------------------------
`timescale 1ns / 1ps
`default_nettype none

module counter #(
    parameter integer WIDTH = 8
) (
    input  wire             clk,    // clock domain tunggal
    input  wire             rst,    // reset sinkron, active-high
    input  wire             en,     // enable cacah
    output reg  [WIDTH-1:0] count,  // nilai cacahan
    output wire             tc      // terminal count: 1 saat cacahan penuh dan en aktif
);

    localparam [WIDTH-1:0] COUNT_MAX = {WIDTH{1'b1}};

    // Sekuensial: non-blocking, reset sinkron di cabang pertama.
    always @(posedge clk) begin
        if (rst) begin
            count <= {WIDTH{1'b0}};
        end else if (en) begin
            count <= count + {{(WIDTH-1){1'b0}}, 1'b1};
        end
    end

    // Kombinasional murni, tanpa latch.
    assign tc = en && (count == COUNT_MAX);

endmodule

`default_nettype wire
