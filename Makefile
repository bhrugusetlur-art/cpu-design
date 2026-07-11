IVERILOG := iverilog
VVP := vvp
BUILD_DIR := build

CPU_DEPS := design/cpu_top.v design/mmu.v design/tlb.v design/datapath.v \
	design/cache_hierarchy.v design/l1_cache.v design/l2_cache.v design/dmem.v \
	design/pc.v design/imem.v design/control.v design/reg_file.v design/alu.v

SIMS := alu cache_hierarchy control cpu_programs cpu_top cpu_vm datapath dmem \
	imem l1_cache l2_cache mmu pc reg_file tlb
SIM_BINS := $(addprefix $(BUILD_DIR)/,$(SIMS))

.PHONY: all test clean

all: $(SIM_BINS)

$(BUILD_DIR):
	mkdir -p $@

$(BUILD_DIR)/alu: sim/alu_tb.v design/alu.v | $(BUILD_DIR)
	$(IVERILOG) -g2012 -o $@ $^

$(BUILD_DIR)/cache_hierarchy: sim/cache_hierarchy_tb.v design/cache_hierarchy.v design/l1_cache.v design/l2_cache.v | $(BUILD_DIR)
	$(IVERILOG) -g2012 -o $@ $^

$(BUILD_DIR)/control: sim/control_tb.v design/control.v | $(BUILD_DIR)
	$(IVERILOG) -g2012 -o $@ $^

$(BUILD_DIR)/cpu_programs: sim/cpu_programs_tb.v $(CPU_DEPS) | $(BUILD_DIR)
	$(IVERILOG) -g2012 -o $@ $^

$(BUILD_DIR)/cpu_top: sim/cpu_top_tb.v $(CPU_DEPS) | $(BUILD_DIR)
	$(IVERILOG) -g2012 -o $@ $^

$(BUILD_DIR)/cpu_vm: sim/cpu_vm_tb.v $(CPU_DEPS) | $(BUILD_DIR)
	$(IVERILOG) -g2012 -o $@ $^

$(BUILD_DIR)/datapath: sim/datapath_tb.v design/datapath.v design/pc.v design/imem.v design/control.v design/reg_file.v design/alu.v | $(BUILD_DIR)
	$(IVERILOG) -g2012 -o $@ $^

$(BUILD_DIR)/dmem: sim/dmem_tb.v design/dmem.v | $(BUILD_DIR)
	$(IVERILOG) -g2012 -o $@ $^

$(BUILD_DIR)/imem: sim/imem_tb.v design/imem.v | $(BUILD_DIR)
	$(IVERILOG) -g2012 -o $@ $^

$(BUILD_DIR)/l1_cache: sim/l1_cache_tb.v design/l1_cache.v | $(BUILD_DIR)
	$(IVERILOG) -g2012 -o $@ $^

$(BUILD_DIR)/l2_cache: sim/l2_cache_tb.v design/l2_cache.v | $(BUILD_DIR)
	$(IVERILOG) -g2012 -o $@ $^

$(BUILD_DIR)/mmu: sim/mmu_tb.v design/mmu.v design/tlb.v | $(BUILD_DIR)
	$(IVERILOG) -g2012 -o $@ $^

$(BUILD_DIR)/pc: sim/pc_tb.v design/pc.v | $(BUILD_DIR)
	$(IVERILOG) -g2012 -o $@ $^

$(BUILD_DIR)/reg_file: sim/reg_file_tb.v design/reg_file.v | $(BUILD_DIR)
	$(IVERILOG) -g2012 -o $@ $^

$(BUILD_DIR)/tlb: sim/tlb_tb.v design/tlb.v | $(BUILD_DIR)
	$(IVERILOG) -g2012 -o $@ $^

test: $(SIM_BINS)
	@set -e; for sim in $(SIMS); do \
		echo "Running $$sim"; \
		$(VVP) $(BUILD_DIR)/$$sim; \
	done
	bash tests/run_assembler_tests.sh

clean:
	rm -rf $(BUILD_DIR)
