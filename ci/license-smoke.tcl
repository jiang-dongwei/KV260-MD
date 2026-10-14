source /work/hardware/kv260/vivado-threads.tcl
create_project -in_memory -part xck26-sfvc784-2LV-c
read_verilog /work/ci/license-smoke.sv
synth_design -top license_smoke -part xck26-sfvc784-2LV-c
opt_design
place_design
route_design
puts "K26 license synthesis/implementation checkout PASS"
