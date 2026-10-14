# Validate individual CDC constraints against a completed, corrected netlist.
# Run through scripts/compile.sh vivado. This does not launch implementation.
source /work/hardware/kv260/vivado-threads.tcl
set core_kind [lindex $argv 0]
if {$core_kind ni {menu nes snes gb gba psx n64 md}} { error "Expected menu, nes, snes, gb, gba, psx or n64" }
set output /build/kria-mister-$core_kind-vivado
if {[info exists ::env(KRIA_BUILD_OUTPUT)]} {
    set output [file normalize $::env(KRIA_BUILD_OUTPUT)]
    if {![string match "/build/*" $output]} {
        error "KRIA_BUILD_OUTPUT must name a directory below /build"
    }
}
open_project $output/kria_mister_$core_kind.xpr
set synthesis [get_runs synth_1]
if {[get_property PROGRESS $synthesis] ne "100%" ||
    [get_property NEEDS_REFRESH $synthesis]} {
    error "Complete synthesis of the corrected application before CDC review"
}
open_run synth_1
if {$core_kind eq "psx"} {
    source /work/hardware/kv260/audit-ram-modes.tcl
    exec /usr/bin/python3 -E /work/scripts/check-psx-ram-modes.py $output/psx_ram_modes.tsv
}
set review $output/cdc-review
file mkdir $review
if {$core_kind eq "snes"} { source /work/hardware/kv260/snes-clocks.tcl }
if {$core_kind eq "psx"} { source /work/hardware/kv260/psx-clocks.tcl }
source /work/hardware/kv260/cdc-mailboxes.tcl
if {$core_kind eq "n64"} { source /work/hardware/kv260/n64-cdc.tcl }
if {$core_kind eq "snes"} { source /work/hardware/kv260/snes-cdc.tcl }
if {$core_kind eq "psx"} { source /work/hardware/kv260/psx-cdc.tcl }
set inventory [open $review/synchronizer_fanout.rpt w]
foreach pattern [list $km_scaler/km_frame*_meta_reg \
    kria_platform_i/pixel_gate/inst/enable_meta_reg \
    $km_measure/km_hdmi_vs_meta_reg] {
    foreach cell [get_cells -quiet -hierarchical -filter "NAME =~ $pattern"] {
        puts $inventory "SOURCE $cell [get_property REF_NAME $cell] ASYNC_REG=[get_property ASYNC_REG $cell]"
        set q [get_pins -of_objects $cell -filter {REF_PIN_NAME == Q}]
        set nets [get_nets -of_objects $q]
        foreach pin [get_pins -leaf -of_objects $nets -filter {DIRECTION == IN}] {
            set receiver [get_cells -of_objects $pin]
            puts $inventory "  LOAD $pin [get_property REF_NAME $receiver] ASYNC_REG=[get_property ASYNC_REG $receiver]"
        }
    }
}
close $inventory
report_clocks -file $review/clocks.rpt
report_timing_summary -delay_type min_max -report_unconstrained \
    -check_timing_verbose -file $review/timing.rpt
report_bus_skew -file $review/bus_skew.rpt
set paths_file [open $review/failing_setup_paths.tsv w]
puts $paths_file "slack\tstart\tend\tsource_clock\tdestination_clock"
foreach path [get_timing_paths -delay_type max -max_paths 2000 -nworst 1 -slack_lesser_than 0] {
    puts $paths_file [join [list [get_property SLACK $path] \
        [get_property STARTPOINT_PIN $path] [get_property ENDPOINT_PIN $path] \
        [get_property STARTPOINT_CLOCK $path] [get_property ENDPOINT_CLOCK $path]] "\t"]
}
close $paths_file
report_cdc -details -file $review/cdc.rpt
report_clock_interaction -file $review/clock_interaction.rpt
report_exceptions -coverage -file $review/exception_coverage.rpt
report_exceptions -ignored -file $review/ignored_exceptions.rpt
report_methodology -file $review/methodology.rpt
report_drc -file $review/drc.rpt
write_checkpoint -force $review/constrained_synth.dcp
puts "CDC constraint application complete. Review remaining crossings and exception precedence before routing."
