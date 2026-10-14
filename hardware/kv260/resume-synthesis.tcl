# Resume only incomplete synthesis runs after an interrupted process. Keep
# completed OOC checkpoints; fail if the source fingerprint has changed.
set core_kind [lindex $argv 0]
if {$core_kind ne "md"} { error "This resume path is for the standalone MD workspace" }
source /work/hardware/kv260/vivado-threads.tcl
set board /work/hardware/kv260
set output /build/kria-mister-$core_kind-vivado
if {[info exists ::env(KRIA_BUILD_OUTPUT)]} { set output $::env(KRIA_BUILD_OUTPUT) }
exec /usr/bin/python3 -E /work/scripts/snapshot-hdl.py --check $core_kind $output $output/source-snapshot.json
open_project $output/kria_mister_$core_kind.xpr
foreach run [get_runs -filter {IS_SYNTHESIS == 1}] {
    if {[get_property PROGRESS $run] ne "100%"} {
        set_property STEPS.SYNTH_DESIGN.TCL.PRE $board/synthesis-single-thread.tcl $run
        reset_run $run
    }
}
set bd [get_files kria_platform.bd]
source $board/finish-synthesis.tcl
