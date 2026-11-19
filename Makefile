RTL   := rtl/mbist_ctrl.sv rtl/mbist_wrapper.sv
BUILD := build

.PHONY: test lint synth clean

test:
	@mkdir -p $(BUILD)
	iverilog -g2012 -o $(BUILD)/tb.vvp $(RTL) tb/faulty_sram.sv tb/tb_mbist.sv
	vvp -n $(BUILD)/tb.vvp

lint:
	verilator --lint-only -Wall -Wno-DECLFILENAME -Wno-UNUSEDSIGNAL --top-module mbist_wrapper $(RTL)

synth:
	@mkdir -p $(BUILD)
	yosys -q -p "read_verilog -sv $(RTL); synth -top mbist_wrapper; tee -o $(BUILD)/synth_stat.txt stat"

clean:
	rm -rf $(BUILD)
