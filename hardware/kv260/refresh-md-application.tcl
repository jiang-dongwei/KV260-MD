# Rebuild changed application HDL while preserving completed platform IP.
# The input guard rejects BD, clock/IP configuration and source-list changes.
set core_kind [lindex $argv 0]
if {$core_kind ne "md"} { error "Expected md" }
source /work/hardware/kv260/vivado-threads.tcl
set board /work/hardware/kv260
set output /build/kria-mister-md-vivado
if {[info exists ::env(KRIA_BUILD_OUTPUT)]} { set output $::env(KRIA_BUILD_OUTPUT) }
exec /usr/bin/python3 -E /work/scripts/check-md-app-refresh.py $output
open_project $output/kria_mister_md.xpr
set app_run [get_runs -quiet kria_platform_app_0_synth_1]
if {[llength $app_run] != 1} { error "Expected one application OOC run" }
foreach run [list $app_run [get_runs synth_1]] {
    set_property STEPS.SYNTH_DESIGN.TCL.PRE $board/synthesis-single-thread.tcl $run
    reset_run $run
}
set bd [get_files kria_platform.bd]
source $board/finish-synthesis.tcl
