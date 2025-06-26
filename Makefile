# Project Structure
PRJ_DIR = $(shell pwd)
SRC_DIR = $(PRJ_DIR)/src
TB_DIR = $(PRJ_DIR)/testbenches

# Toolchain
VERILATOR = verilator
VCS = vcs
VVP = vvp
WAVE = surfer

# Design Files for SA Array
DESIGN_FILES = \
	SystolicArray.sv \
	RowInputQueue.sv \
	ColumnInputQueue.sv \
	Mesh.sv \
	ProcessingElement.sv \
	MAC/Adder_FP32.sv \
	MAC/LZC.sv \
	MAC/Multiplier_FP32 \
	MAC/UnSig_Karatsuba.sv \
	MAC/UnSig_R4Booth.sv \
	MAC/MAC.sv

# Top module
TOP_MODULE = TB_SystolicArray
# Testbench
TESTBENCH = $(TOP_MODULE).sv

# Directories
VERILATOR_DIR = $(PRJ_DIR)/Verilator
VCS_DIR = $(PRJ_DIR)/VCS

# Verilator Flags
VERILATOR_FLAGS = \
	--trace \
	--timing \
	--top-module $(TOP_MODULE) \
	--threads $(shell nproc) \
	--sv \
	-I$(SRC_DIR) \
	-I$(TB_DIR) \
	--Mdir $(VERILATOR_DIR) \
	--Wno-WIDTHTRUNC \
	--Wno-WIDTHEXPAND \
	--Wno-WIDTHCONCAT \
	--Wno-PINMISSING

# VCS Flags
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

# Default target
default: verilator

# Verilator Simulation
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
	@echo "-- Copying input files"
		@if ls $(SRC_DIR)/*.mem 1> /dev/null 2>&1; then \
		cp $(SRC_DIR)/*.mem $(VERILATOR_DIR); \
		fi
	@echo "-- Copying ouput files"
		@if ls $(TB_DIR)/*.mem 1> /dev/null 2>&1; then \
		cp $(TB_DIR)/*.mem $(VERILATOR_DIR); \
		fi
	@echo "-- Running Verilator simulation"
	cd $(VERILATOR_DIR) && ./$(TOP_MODULE)_sim
	@echo "-- Verilator simulation complete"
	@echo "-- Trace file: $(VERILATOR_DIR)/dump.vcd"

# VCS Simulation
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


# View Verilator Waveform
wave:
	@if [ -f $(VERILATOR_DIR)/$(TOP_MODULE).vcd ]; then \
		echo "-- Opening WAVE"; \
		$(WAVE) $(VERILATOR_DIR)/$(TOP_MODULE).vcd; \
	else \
		echo "-- No waveform dumps found"; \
	fi

# Lint check with Verilator (no simulation)
lint:
	@echo "=== Linting Systolic Array with Verilator ==="
	@mkdir -p $(VERILATOR_DIR)
	$(VERILATOR) --lint-only \
		$(VERILATOR_FLAGS) \
		$(addprefix $(SRC_DIR)/,$(DESIGN_FILES)) \
		$(TB_DIR)/$(TESTBENCH)
	@echo "-- Lint check complete"

# Debug build with extra information
debug: VERILATOR_FLAGS += --debug --gdbbt
debug: IVERILOG_FLAGS += -g
debug: verilator

# Performance analysis
perf: VERILATOR_FLAGS += --stats --profile-cfuncs
perf: verilator

# Clean all simulation artifacts
clean:
	@echo "-- Cleaning simulation artifacts"
	-rm -rf $(VERILATOR_DIR) $(IVERILOG_DIR) $(VCS_DIR)
	-rm -f *.vpd *.vcd *.wlf *.log
	-rm -f csrc simv simv.daidir
	-rm -f *.key DVEfiles
	@echo "-- Clean complete"

# Phony targets
.PHONY: default verilator vcs wave lint debug perf clean
