current_design cpu_top

# Initial ASIC target: 10 MHz. This is intentionally conservative for the
# first complete synthesis/place/route run on Sky130 HD standard cells.
set clock_period 100.0
create_clock -name core_clock -period $clock_period [get_ports clk]

# Reset is asynchronous in the current RTL, so exclude its assertion path
# from synchronous timing analysis.
set_false_path -from [get_ports rst]

# Model modest external board/harness delays on observable core outputs.
set_output_delay 5.0 -clock core_clock [all_outputs]
