// -----------------------------------------------------------------------------
// tb_uart_tx - testbench self-checking untuk modul uart_tx
//
// Mengikuti pola tb/tb_counter.sv:
//   - SystemVerilog prosedural (tanpa class, randomize, covergroup, atau SVA)
//   - self-checking: setiap skenario membandingkan hasil dengan nilai harapan
//   - keluar dengan $fatal bila ada kegagalan, supaya CI menandainya merah
//
// CLK_HZ di-override ke 1_152_000 sehingga DIV = 10 clock per bit (100 clock
// per karakter) — mempercepat simulasi. Nilai default modul tetap 100 MHz.
// -----------------------------------------------------------------------------
`timescale 1ns / 1ps

module tb_uart_tx;

    localparam int CLK_HZ = 1_152_000;      // override agar DIV = 10 clock/bit
    localparam int BAUD   = 115_200;
    localparam int DIV    = CLK_HZ / BAUD;  // 10 clock per periode bit
    localparam int BITS   = 10;             // 1 start + 8 data + 1 stop
    localparam time TCLK  = 10ns;

    logic             clk = 1'b0;
    logic             rst = 1'b1;
    logic             tx_start = 1'b0;
    logic [7:0]       tx_data = 8'd0;
    logic             tx_busy;
    logic             tx_serial;

    int errors = 0;

    uart_tx #(
        .CLK_HZ (CLK_HZ),
        .BAUD   (BAUD)
    ) dut (
        .clk       (clk),
        .rst       (rst),
        .tx_start  (tx_start),
        .tx_data   (tx_data),
        .tx_busy   (tx_busy),
        .tx_serial (tx_serial)
    );

    always #(TCLK/2) clk = ~clk;

    // Tunggu transmitter tidak sibuk. Mencuplik setelah #1 supaya tidak balapan
    // dengan pembaruan non-blocking di DUT. Dibatas-t waktu (timeout): bila tiap
    // frame normal hanya butuh BITS*DIV clock, sebuah frame yang lama ~BITS*DIV*2
    // pasti sudah macet (tx_busy macet tinggi) -> $fatal supaya CI tidak menggantung.
    task automatic wait_idle();
        int t = 0;
        while (tx_busy) begin
            if (t >= BITS * DIV * 2) begin
                $fatal(1, "[FAIL] wait_idle timeout: tx_busy tidak pernah turun sebelum skenario berikutnya mulai");
            end
            @(posedge clk);
            #1;
            t++;
        end
    endtask

    task automatic check_bit(input logic got, input logic exp, input string what);
        if (got !== exp) begin
            errors++;
            $error("%s: dapat %b, harusnya %b", what, got, exp);
        end
    endtask

    // Kirim satu byte lalu dekode dan periksa seluruh frame 10-bit.
    // inject=1: pulsakan tx_start di tengah frame untuk menguji ia diabaikan.
    task automatic send_and_check(input logic [7:0] d, input bit inject);
        logic [BITS-1:0] frame;
        int t;
        begin
            wait_idle();

            // E0: mulai transmisi — tx_start tinggi tepat satu siklus.
            tx_data = d;
            tx_start = 1'b1;
            @(posedge clk);
            #1;
            tx_start = 1'b0;
            #1;
            check_bit(tx_busy,  1'b1, "tx_busy naik saat mulai kirim");
            check_bit(tx_serial, 1'b0, "start bit rendah di awal frame");

            // Cemplung tx_serial di tengah tiap periode bit (DIV/2 setelah tepi
            // awal bit), mulai dari tengah start bit.
            frame = '0;
            for (int i = 0; i < BITS; i++) begin
                if (i == 0) repeat (DIV/2) @(posedge clk);
                else        repeat (DIV)   @(posedge clk);
                #1;
                frame[i] = tx_serial;

                // Suntik tx_start tepat setelah mencuplik bit data ke-4 (frame
                // index 4). DUT sedang sibuk, jadi pulse ini harus diabaikan.
                if (inject && i == 4) begin
                    tx_start = 1'b1;
                    @(posedge clk);
                    #1;
                    tx_start = 1'b0;
                    #1;
                    check_bit(tx_busy, 1'b1,
                              "tx_busy tetap tinggi saat tx_start disuntik");
                end
            end

            // Tunggu busy turun (stop bit selesai), dengan batas waktu.
            t = 0;
            while (tx_busy && t < BITS*DIV + 4) begin
                @(posedge clk);
                #1;
                t++;
            end
            // Bila batas waktu tercapai, check_bit di atas sudah menaikkan errors;
            // di sini tidak menaikkan errors lagi supaya satu kegagalan = satu hitungan.
            if (t >= BITS*DIV + 4)
                $error("tx_busy masih tinggi setelah %0d clock (watchdog timeout)", t);

            // Periksa frame: start 0, delapan bit data LSB lebih dulu, stop 1.
            check_bit(frame[0], 1'b0, "start bit = 0");
            for (int i = 0; i < 8; i++)
                check_bit(frame[1+i], d[i],
                          $sformatf("data bit %0d (LSB lebih dulu)", i));
            check_bit(frame[BITS-1], 1'b1, "stop bit = 1");

            // Setelah stop, jalur kembali idle (mark).
            #1;
            check_bit(tx_serial, 1'b1, "tx_serial idle = 1 setelah selesai");
            check_bit(tx_busy,   1'b0, "tx_busy = 0 setelah selesai");
        end
    endtask

    initial begin
        // --- Skenario 1: reset memaksa jalur idle dan tx_busy rendah ---
        rst = 1'b1;
        tx_start = 1'b0;
        repeat (3) @(posedge clk);
        #1;
        check_bit(tx_serial, 1'b1, "reset: tx_serial idle = 1");
        check_bit(tx_busy,   1'b0, "reset: tx_busy = 0");
        rst = 1'b0;
        @(posedge clk);

        // --- Skenario 2: kirim 8'h00 (start 0, semua data 0, stop 1) ---
        send_and_check(8'h00, 1'b0);

        // --- Skenario 3: kirim 8'hFF (semua data 1) ---
        send_and_check(8'hFF, 1'b0);

        // --- Skenario 4: kirim 8'h5A — memastikan urutan LSB lebih dulu ---
        send_and_check(8'h5A, 1'b0);

        // --- Skenario 5: tx_start diabaikan saat tx_busy tinggi ---
        send_and_check(8'hA5, 1'b1);

        // --- Skenario 6: tidak ada karakter kedua setelah frame selesai ---
        repeat (DIV*2) @(posedge clk);
        #1;
        check_bit(tx_busy,   1'b0, "tidak ada transmisi baru setelah selesai");
        check_bit(tx_serial, 1'b1, "jalur tetap idle setelah selesai");

        if (errors == 0) begin
            $display("[PASS] tb_uart_tx - seluruh skenario lolos");
            $finish;
        end else begin
            $fatal(1, "[FAIL] tb_uart_tx - %0d kegagalan", errors);
        end
    end

endmodule
