# OpenROAD Flow Scripts configuration for an initial Sky130 hardening run.
# Invoke from the repository root so imem.v can resolve program.mem:
#   make --file=<ORFS_ROOT>/flow/Makefile \
#        DESIGN_CONFIG=$(pwd)/openroad/config.mk

export DESIGN_NICKNAME = cpu8
export DESIGN_NAME = cpu_top
export PLATFORM = sky130hd

PROJECT_DIR := $(abspath $(dir $(DESIGN_CONFIG))/..)

export VERILOG_FILES = \
  $(PROJECT_DIR)/design/cpu_top.v \
  $(PROJECT_DIR)/design/mmu.v \
  $(PROJECT_DIR)/design/tlb.v \
  $(PROJECT_DIR)/design/datapath.v \
  $(PROJECT_DIR)/design/cache_hierarchy.v \
  $(PROJECT_DIR)/design/l1_cache.v \
  $(PROJECT_DIR)/design/l2_cache.v \
  $(PROJECT_DIR)/design/dmem.v \
  $(PROJECT_DIR)/design/pc.v \
  $(PROJECT_DIR)/design/imem.v \
  $(PROJECT_DIR)/design/control.v \
  $(PROJECT_DIR)/design/reg_file.v \
  $(PROJECT_DIR)/design/alu.v

export SDC_FILE = $(PROJECT_DIR)/openroad/constraint.sdc

# The upstream Sky130 deck does not connect ORFS's GDS pin-purpose geometry
# (datatype 16) to the routed metal and text layers.  Use the project deck so
# all 82 top-level port labels participate in extraction and LVS.
export KLAYOUT_LVS_FILE = $(PROJECT_DIR)/openroad/sky130hd_lvs.lylvs

# Keep ORFS-generated logs, reports, databases, and GDS files out of the
# source tree while retaining them under the project for reproducibility.
export WORK_HOME = $(PROJECT_DIR)/openroad/work

# Conservative first-pass floorplan settings. These can be tightened after
# the first successful placement and congestion report.
export CORE_UTILIZATION = 15
export PLACE_DENSITY_LB_ADDON = 0.03
export SLEW_MARGIN = 20
export CAP_MARGIN = 20
export TNS_END_PERCENT = 100
