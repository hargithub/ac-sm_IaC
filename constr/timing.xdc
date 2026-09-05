# Constraint dasar untuk modul contoh.
#
# Pin assignment sengaja dikosongkan karena bergantung papan yang dipakai.
# Tambahkan set_property PACKAGE_PIN / IOSTANDARD saat papan sudah ditentukan.

# Clock 100 MHz pada port clk
create_clock -period 10.000 -name clk -waveform {0.000 5.000} [get_ports clk]
