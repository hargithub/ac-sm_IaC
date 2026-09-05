# =============================================================================
# ac-sm_IaC - build system
#
# Dua lapis:
#   lint / sim  -> tool open-source, jalan di GitHub Actions
#   synth       -> Vivado, hanya di mesin yang punya Vivado terpasang
#
# Satu filelist dipakai bertiga: Verilator memakai -f, Icarus memakai -c,
# Vivado membacanya lewat scripts/build.tcl.
# =============================================================================

TOP       ?= counter
TB        ?= tb_counter
PART      ?= xc7a35tcpg236-1

RTL_F     := rtl/files.f
TB_F      := tb/files.f
SIM_DIR   := sim

IVERILOG  := iverilog
VVP       := vvp
VERILATOR := verilator
VIVADO    := vivado

.PHONY: all lint sim wave synth clean help
.DEFAULT_GOAL := help

help:
	@echo "Target yang tersedia:"
	@echo "  make lint              - lint RTL dengan Verilator (TOP=$(TOP))"
	@echo "  make sim               - jalankan testbench dengan Icarus (TB=$(TB))"
	@echo "  make sim TB=tb_lain    - jalankan testbench tertentu"
	@echo "  make wave              - simulasi lalu buka gelombang di GTKWave"
	@echo "  make synth             - sintesis Vivado (butuh Vivado terpasang)"
	@echo "  make clean             - hapus hasil build"
	@echo ""
	@echo "Ganti target FPGA lewat PART, saat ini: $(PART)"

all: lint sim

# --- Lint ---------------------------------------------------------------------
# -Wall menyalakan seluruh peringatan gaya. DECLFILENAME dimatikan karena repo
# ini membolehkan lebih dari satu modul kecil per berkas bila memang berkaitan.
lint:
	@echo "==> Verilator lint, top-module $(TOP)"
	$(VERILATOR) --lint-only -Wall -Wno-DECLFILENAME -f $(RTL_F) --top-module $(TOP)
	@echo "==> Lint bersih"

# --- Simulasi -----------------------------------------------------------------
# Direktori sim dibuat di dalam resep, bukan sebagai target tersendiri:
# nama target "sim" akan bentrok dengan nama direktori $(SIM_DIR).
sim:
	@mkdir -p $(SIM_DIR)
	@echo "==> Kompilasi $(TB) dengan Icarus"
	$(IVERILOG) -g2012 -Wall -o $(SIM_DIR)/$(TB).out -s $(TB) -c $(RTL_F) -c $(TB_F)
	@echo "==> Jalankan $(TB)"
	@cd $(SIM_DIR) && $(VVP) $(TB).out

wave: sim
	@gtkwave $(SIM_DIR)/$(TB).vcd &

# --- Sintesis -----------------------------------------------------------------
# Non-project mode: tidak ada .xpr yang masuk git.
synth:
	@command -v $(VIVADO) >/dev/null 2>&1 || { \
		echo "Vivado tidak ditemukan. Target ini hanya jalan di mesin ber-Vivado,"; \
		echo "bukan di runner GitHub Actions."; exit 1; }
	$(VIVADO) -mode batch -source scripts/build.tcl -tclargs $(PART) $(TOP)

clean:
	rm -rf $(SIM_DIR) vivado*.log vivado*.jou .Xil build
