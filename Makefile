# Makefile for FuseSoC project
export TESTCASE

CORE   ?= hasunosora:arith:fpmul_pipe:0.1a0
TARGET ?= sim
TOOL   ?= xcelium
MODULE ?= hsf2_wrapper_test

FUSESOC      = fusesoc
FUSESOC_ARGS = run --target $(TARGET) --build --tool $(TOOL)

CORE_DIR = $(subst :,_,$(CORE))
SIM_PATH = $(TARGET)-$(TOOL)

BUILD_PATH = $(shell pwd)/build/$(CORE_DIR)/$(SIM_PATH)
FIX_MAKE   = $(BUILD_PATH)/Makefile

export VIRTUAL_ENV=/opt/fusesoc/

fusesoc_build:
	@echo "Building the FuseSoC Project"
	$(FUSESOC) $(FUSESOC_ARGS) $(CORE)

fix: fusesoc_build 
	@echo "Fixing the Makefile"
	@sed -i '/^all:/,$$d' "$(FIX_MAKE)"
	@echo "TOPLEVEL_LANG ?= verilog" >> "$(FIX_MAKE)"
	@echo "SIM ?= $(TOOL)" >> "$(FIX_MAKE)"
	@echo "COCOTB_HDL_TIMEUNIT = 1ns" >> "$(FIX_MAKE)"
	@echo "COCOTB_HDL_TIMEPRECISION = 1ps" >> "$(FIX_MAKE)"
	@echo "EXTRA_ARGS = -f edalize_main.f" >> "$(FIX_MAKE)"
	@echo "SIM_ARGS += \$$(XRUN_OPTIONS)" >> "$(FIX_MAKE)"
	@echo "MODULE = $(MODULE)" >> "$(FIX_MAKE)"
	@echo "include \$$(shell cocotb-config --makefile)/Makefile.sim" >> "$(FIX_MAKE)" 

	@echo "Makefile updated"

run: fusesoc_build fix
	@cd $(BUILD_PATH) && make TESTCASE=$(TESTCASE)

