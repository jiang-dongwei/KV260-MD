# Complete signoff and firmware generation from an existing routed checkpoint.
# This intentionally never invokes opt/place/phys_opt/route, so a routed result
# can be resumed after a reporting or packaging failure without rerouting it.
source /work/hardware/kv260/vivado-threads.tcl
set core_kind [lindex $argv 0]
if {$core_kind ni {menu nes snes gb gba psx n64 md}} {
    error "Expected menu, nes, snes, gb, gba, psx or n64"
}

set project_dir /build/kria-mister-$core_kind-vivado
if {[info exists ::env(KRIA_BUILD_OUTPUT)]} {
    set project_dir [file normalize $::env(KRIA_BUILD_OUTPUT)]
    if {![string match "/build/*" $project_dir]} {
        error "KRIA_BUILD_OUTPUT must name a directory below /build"
    }
}
set reviewed $project_dir/cdc-review/constrained_synth.dcp
set output $project_dir/implementation
set routed $output/routed.dcp
if {![file exists $reviewed]} { error "Missing reviewed synthesis checkpoint" }
if {![file exists $routed]} { error "Missing routed checkpoint" }

exec /usr/bin/python3 -E /work/scripts/snapshot-hdl.py --check \
    $core_kind $project_dir $project_dir/source-snapshot.json
open_checkpoint $routed

# Recreate the reports consumed by the strict checker from this exact design.
report_route_status -file $output/route_status.rpt
report_utilization -file $output/utilization_routed.rpt
report_clock_utilization -file $output/clock_utilization.rpt
report_cdc -details -file $output/cdc_routed.rpt
report_exceptions -coverage -file $output/exception_coverage.rpt
report_exceptions -ignored -file $output/ignored_exceptions.rpt
report_bus_skew -file $output/bus_skew.rpt
report_methodology -file $output/methodology_routed.rpt
report_drc -file $output/drc_routed.rpt
report_timing_summary -delay_type min_max -report_unconstrained \
    -check_timing_verbose -file $output/timing_routed.rpt
foreach delay {max min} {
    if {[llength [get_timing_paths -delay_type $delay -max_paths 1 \
            -slack_lesser_than 0]]} {
        error "Routed $delay timing failed"
    }
}
if {[llength [get_drc_violations -quiet \
        -filter {SEVERITY == Error || SEVERITY == "Critical Warning"}]]} {
    error "Routed DRC has errors or critical warnings"
}
exec /usr/bin/python3 -E /work/scripts/check-routed-timing.py \
    $output/timing_routed.rpt

write_bitstream -force $output/$core_kind.bit
set bif [open $output/$core_kind.bif w]
puts $bif "all: { $output/$core_kind.bit }"
close $bif
if {![info exists ::env(XILINX_VIVADO)]} { error "XILINX_VIVADO is not set" }
set bootgen [file join $::env(XILINX_VIVADO) bin bootgen]
exec $bootgen -arch zynqmp -image $output/$core_kind.bif \
    -process_bitstream bin -w on
if {![file exists $output/$core_kind.bit.bin]} {
    error "Bootgen did not emit raw FPGA firmware"
}
exec /usr/bin/python3 -E /work/scripts/record-implementation.py \
    $core_kind $output $reviewed [version -short]
puts "Existing routed $core_kind design signed off and firmware generated: $output"
