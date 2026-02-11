PRJ_DIR = $(shell pwd)
SRC_DIR = $(PRJ_DIR)/src
TB_DIR = $(PRJ_DIR)/testbenches

# Toolchain
VERILATOR = verilator
VCS = vcs
VVP = vvp
WAVE = surfer

DESIGN_FILES = \
  top/SystolicMesh.sv \
  top/SystolicArray.sv \
  mem/RowInputQueue.sv \
  mem/ColumnInputQueue.sv \
  mem/OutputSram.sv \
  mem/MeshOutputSram.sv \
  engine/PEMesh.sv \
  engine/ProcessingElement.sv \
  engine/AccumulationUnit.sv \
  engine/MAC.sv \
  ../ArithmeticLibrary/Multipliers/FP32/src/R4Booth.sv \
  ../ArithmeticLibrary/Multipliers/FP32/src/karatsubaUnsigned.sv \
	../ArithmeticLibrary/Multipliers/FP32/src/fp32Multiplier.sv \
  ../ArithmeticLibrary/Adders/FP32/src/LZC.sv \
  ../ArithmeticLibrary/Adders/FP32/src/fp32Adder.sv

TOP_MODULE = TB_SystolicMesh
TESTBENCH = $(TOP_MODULE).sv

VERILATOR_DIR = $(PRJ_DIR)/Verilator
VCS_DIR = $(PRJ_DIR)/VCS

VERILATOR_FLAGS = \
	--trace \
	--timing \
	--top-module $(TOP_MODULE) \
	--threads 8 \
	--sv \
	-I$(SRC_DIR) \
	-I$(TB_DIR) \
	--Mdir $(VERILATOR_DIR) \
	--Wno-WIDTHTRUNC \
	--Wno-WIDTHEXPAND \
	--Wno-WIDTHCONCAT

VCS_FLAGS = \
	-full64 \
	-sverilog \
	-debug_all \
	-timescale=1ns/1ps \
	-Mdir=$(VCS_DIR) \
	+v2k \
	+incdir+$(SRC_DIR) \
	+incdir+$(TB_DIR) \
	+define+VCS

default: verilator

verilator:
	@echo "=== Verilator simulation for Systolic Array ==="
	@mkdir -p $(VERILATOR_DIR)
	$(VERILATOR) --binary \
		$(VERILATOR_FLAGS) \
		$(addprefix $(SRC_DIR)/,$(DESIGN_FILES)) \
		$(TB_DIR)/$(TESTBENCH) \
		-o $(TOP_MODULE)_sim
	@echo "-- Compiling Verilator simulation"
	make -C $(VERILATOR_DIR) -f V$(TOP_MODULE).mk
	@echo "-- Copying test files"
		@if ls $(TB_DIR)/stimulus/*.mem 1> /dev/null 2>&1; then \
		cp $(TB_DIR)/stimulus/*.mem $(VERILATOR_DIR); \
		fi
	@echo "-- Running Verilator simulation"
	cd $(VERILATOR_DIR) && ./$(TOP_MODULE)_sim
	@echo "-- Verilator simulation complete"
	@echo "-- Trace file: $(VERILATOR_DIR)/dump.vcd"

vcs:
	@echo "=== VCS simulation for Systolic Array ==="
	@mkdir -p $(VCS_DIR)
	$(VCS) $(VCS_FLAGS) \
		-o $(VCS_DIR)/$(TOP_MODULE)_sim \
		$(addprefix $(SRC_DIR)/,$(DESIGN_FILES)) \
		$(TB_DIR)/$(TESTBENCH)
	@echo "-- Running VCS simulation"
	cd $(VCS_DIR) && ./$(TOP_MODULE)_sim
	@echo "-- VCS simulation complete"

wave:
	@if [ -f $(VERILATOR_DIR)/$(TOP_MODULE).vcd ]; then \
		echo "-- Opening WAVE"; \
		$(WAVE) $(VERILATOR_DIR)/$(TOP_MODULE).vcd; \
	else \
		echo "-- No waveform dumps found"; \
	fi

lint:
	@echo "=== Linting Systolic Array with Verilator ==="
	@mkdir -p $(VERILATOR_DIR)
	$(VERILATOR) --lint-only \
		$(VERILATOR_FLAGS) \
		$(addprefix $(SRC_DIR)/,$(DESIGN_FILES)) \
		$(TB_DIR)/$(TESTBENCH)
	@echo "-- Lint check complete"

debug: VERILATOR_FLAGS += --debug --gdbbt
debug: IVERILOG_FLAGS += -g
debug: verilator

perf: VERILATOR_FLAGS += --stats --profile-cfuncs
perf: verilator

clean:
	@echo "-- Cleaning simulation artifacts"
	-rm -rf $(VERILATOR_DIR) $(IVERILOG_DIR) $(VCS_DIR)
	-rm -f *.vpd *.vcd *.wlf *.log
	-rm -f csrc simv simv.daidir
	-rm -f *.key DVEfiles
	@echo "-- Clean complete"

.PHONY: default verilator vcs wave lint debug perf clean
