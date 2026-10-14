# Run only after reviewing the corrected linked netlist and its CDC reports.
# All implementation runs use the host/container build lock.
source /work/hardware/kv260/vivado-threads.tcl
set core_kind [lindex $argv 0]
if {$core_kind ni {menu nes snes gb gba psx n64 md}} { error "Expected menu, nes, snes, gb, gba, psx or n64" }
set project_dir /build/kria-mister-$core_kind-vivado
if {[info exists ::env(KRIA_BUILD_OUTPUT)]} {
    set project_dir [file normalize $::env(KRIA_BUILD_OUTPUT)]
    if {![string match "/build/*" $project_dir]} {
        error "KRIA_BUILD_OUTPUT must name a directory below /build"
    }
}
set reviewed $project_dir/cdc-review/constrained_synth.dcp
if {![file exists $reviewed]} { error "Run and review review-cdc.tcl first" }
open_project $project_dir/kria_mister_$core_kind.xpr
set synthesis [get_runs synth_1]
if {[get_property PROGRESS $synthesis] ne "100%" || [get_property NEEDS_REFRESH $synthesis]} {
    error "Synthesis is not up to date"
}
set review_inputs [list $project_dir/kria_mister_$core_kind.runs/synth_1/kria_platform_wrapper.dcp \
    /work/hardware/kv260/cdc-mailboxes.tcl]
if {$core_kind eq "snes"} {
    lappend review_inputs /work/hardware/kv260/snes-clocks.tcl /work/hardware/kv260/snes-cdc.tcl
}
if {$core_kind eq "psx"} {
    lappend review_inputs /work/hardware/kv260/psx-clocks.tcl /work/hardware/kv260/psx-cdc.tcl
}
if {$core_kind eq "n64"} {
    lappend review_inputs /work/hardware/kv260/n64-cdc.tcl
}
foreach path $review_inputs {
    if {[file mtime $path] > [file mtime $reviewed]} { error "CDC review is stale: $path" }
}
close_project
exec /usr/bin/python3 -E /work/scripts/snapshot-hdl.py --check $core_kind $project_dir $project_dir/source-snapshot.json
open_checkpoint $reviewed
set output $project_dir/implementation
file mkdir $output
# Invalidate an earlier success record before doing new physical work.
file delete -force $output/implementation.json
opt_design
write_checkpoint -force $output/optimized.dcp
place_design
report_timing_summary -delay_type min_max -file $output/timing_placed.rpt
write_checkpoint -force $output/placed.dcp
phys_opt_design
route_design
write_checkpoint -force $output/routed.dcp
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
    if {[llength [get_timing_paths -delay_type $delay -max_paths 1 -slack_lesser_than 0]]} {
        error "Routed $delay timing failed; retain reports and correct before bitstream generation"
    }
}
if {[llength [get_drc_violations -quiet -filter {SEVERITY == Error || SEVERITY == "Critical Warning"}]]} {
    error "Routed DRC has errors or critical warnings"
}
# Check pulse-width and unconstrained-path counts as well as setup/hold. This
# deliberately fails closed if the installed report format changes.
exec /usr/bin/python3 -E /work/scripts/check-routed-timing.py $output/timing_routed.rpt
write_bitstream -force $output/$core_kind.bit
set bif [open $output/$core_kind.bif w]
puts $bif "all: { $output/$core_kind.bit }"
close $bif
if {![info exists ::env(XILINX_VIVADO)]} { error "XILINX_VIVADO is not set" }
set bootgen [file join $::env(XILINX_VIVADO) bin bootgen]
exec $bootgen -arch zynqmp \
    -image $output/$core_kind.bif -process_bitstream bin -w on
if {![file exists $output/$core_kind.bit.bin]} { error "Bootgen did not emit raw FPGA firmware" }
exec /usr/bin/python3 -E /work/scripts/record-implementation.py $core_kind $output $reviewed [version -short]
puts "Routed $core_kind firmware and implementation evidence complete: $output"
