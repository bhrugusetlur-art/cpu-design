IVERILOG := iverilog
VVP := vvp
BUILD_DIR := build
PYTHON ?= python3

CPU_DEPS := design/cpu_top.v design/mmu.v design/tlb.v design/datapath.v \
	design/cache_hierarchy.v design/l1_cache.v design/l2_cache.v design/dmem.v \
	design/pc.v design/imem.v design/control.v design/reg_file.v design/alu.v

SIMS := alu cache_hierarchy control cpu_programs cpu_top cpu_vm datapath dmem \
	imem l1_cache l2_cache mmu pc reg_file tlb
SIM_BINS := $(addprefix $(BUILD_DIR)/,$(SIMS))
FPGA_TRACE_BIN := $(BUILD_DIR)/fpga_demo_trace
BASYS3_COMPILE_BIN := $(BUILD_DIR)/basys3_compile
GDS_INPUT ?= openroad/work/results/sky130hd/cpu8/base/6_final.gds
GDS_RAW := $(BUILD_DIR)/final-gds-layout-raw.png
GDS_IMAGE := docs/images/final-gds-layout.png

.PHONY: all test basys3-compile check-visual-deps fpga-demo-trace fpga-readme-assets gds-readme-asset visual-checks clean

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

$(FPGA_TRACE_BIN): sim/fpga_demo_trace_tb.v $(CPU_DEPS) | $(BUILD_DIR)
	$(IVERILOG) -g2012 -o $@ $^

$(BASYS3_COMPILE_BIN): design/basys3_top.v $(CPU_DEPS) | $(BUILD_DIR)
	$(IVERILOG) -g2012 -s basys3_top -o $@ $^

basys3-compile: $(BASYS3_COMPILE_BIN)

fpga-demo-trace: $(FPGA_TRACE_BIN)
	$(VVP) $(FPGA_TRACE_BIN)

check-visual-deps:
	@$(PYTHON) -c 'import PIL' >/dev/null 2>&1 || { \
		echo "Pillow is required. Run: $(PYTHON) -m pip install -r requirements-visuals.txt" >&2; \
		exit 1; \
	}

fpga-readme-assets: fpga-demo-trace check-visual-deps
	$(PYTHON) tools/render_fpga_visuals.py \
		--trace $(BUILD_DIR)/fpga-demo-trace.csv \
		--gif docs/images/fpga-demo.gif \
		--svg docs/images/fpga-controls.svg

gds-readme-asset: check-visual-deps | $(BUILD_DIR)
	@test -f $(GDS_INPUT) || { echo "Missing final GDS: $(GDS_INPUT)" >&2; exit 1; }
	docker run --rm --platform linux/amd64 \
		-e GDS_INPUT=/project/$(GDS_INPUT) \
		-e GDS_OUTPUT=/project/$(GDS_RAW) \
		-e GDS_WIDTH=1200 -e GDS_HEIGHT=1200 \
		-v "$(CURDIR):/project" -w /project \
		openroad/orfs:latest klayout -b -r /project/tools/render_gds_layout.py
	$(PYTHON) tools/style_gds_visual.py --input $(GDS_RAW) --output $(GDS_IMAGE)

visual-checks: fpga-readme-assets
	$(PYTHON) tests/check_fpga_visuals.py
	$(PYTHON) tests/check_gds_image.py

test: $(SIM_BINS)
	@set -e; for sim in $(SIMS); do \
		echo "Running $$sim"; \
		$(VVP) $(BUILD_DIR)/$$sim; \
	done
	bash tests/run_assembler_tests.sh
	bash tests/run_lvs_deck_tests.sh
	bash tests/check_basys3_compile.sh
	bash tests/check_fpga_demo_trace.sh
	bash tests/check_visual_setup.sh

clean:
	rm -rf $(BUILD_DIR)
