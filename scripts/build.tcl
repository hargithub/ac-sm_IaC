# =============================================================================
# Sintesis dan implementasi Vivado - NON-PROJECT MODE
#
# Sengaja tidak memakai .xpr: berkas proyek Vivado berupa XML yang berubah
# setiap kali GUI dibuka, menghasilkan diff berisik dan konflik merge.
#
# Pemakaian:
#   vivado -mode batch -source scripts/build.tcl -tclargs <part> <top>
#
# Skrip ini TIDAK bisa jalan di runner GitHub Actions - Vivado terlalu besar
# dan berlisensi. Jalankan di mesin yang punya Vivado terpasang.
# =============================================================================

set part [lindex $argv 0]
set top  [lindex $argv 1]
if {$part eq ""} { set part xc7a35tcpg236-1 }
if {$top  eq ""} { set top  counter }

set outdir build
file mkdir $outdir
puts "INFO: part=$part top=$top outdir=$outdir"

# --- Baca filelist RTL yang sama dengan yang dipakai lint dan simulasi -------
set fh [open rtl/files.f r]
set src [split [read $fh] "\n"]
close $fh
foreach line $src {
    set line [string trim $line]
    if {$line eq "" || [string index $line 0] eq "#"} { continue }
    puts "INFO: read_verilog $line"
    read_verilog $line
}

# --- Constraint (opsional) ---------------------------------------------------
foreach xdc [glob -nocomplain constr/*.xdc] {
    puts "INFO: read_xdc $xdc"
    read_xdc $xdc
}

# --- Sintesis ----------------------------------------------------------------
synth_design -top $top -part $part
write_checkpoint      -force $outdir/post_synth.dcp
report_utilization    -file  $outdir/utilization.rpt
report_timing_summary -file  $outdir/timing_post_synth.rpt

# --- Implementasi ------------------------------------------------------------
opt_design
place_design
route_design
write_checkpoint      -force $outdir/post_route.dcp
report_utilization    -file  $outdir/utilization_post_route.rpt
report_timing_summary -file  $outdir/timing_post_route.rpt

write_bitstream -force $outdir/$top.bit
puts "INFO: selesai, bitstream di $outdir/$top.bit"
