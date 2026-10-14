# Complete/review synthesis after constructing or reopening the project.
if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} {
    exec /usr/bin/python3 -E /work/scripts/snapshot-hdl.py $core_kind $output $output/source-snapshot.json
    # N64 is by far the largest application module. Run that OOC target first
    # so source/elaboration failures stop immediately instead of waiting for
    # every unrelated block-design IP target to finish.
    set n64_global_synth 0
    if {$core_kind eq "n64" && [info exists ::env(KRIA_N64_GLOBAL_SYNTH)]} {
        set n64_global_synth [expr {$::env(KRIA_N64_GLOBAL_SYNTH) eq "1"}]
    }
    if {$core_kind eq "n64" && !$n64_global_synth} {
        set app_run [get_runs -quiet kria_platform_app_0_synth_1]
        if {![llength $app_run]} {
            create_ip_run $bd
            set app_run [get_runs -quiet kria_platform_app_0_synth_1]
        }
        if {[llength $app_run] != 1} { error "Missing N64 application OOC run" }
        set_property STEPS.SYNTH_DESIGN.TCL.PRE \
            $board/synthesis-single-thread.tcl $app_run
        if {[get_property PROGRESS $app_run] ne "100%"} {
            launch_runs $app_run -jobs 1
            wait_on_run $app_run
        }
        if {[get_property PROGRESS $app_run] ne "100%"} {
            error "N64 application OOC synthesis failed"
        }
    }
    # Parallelize independent block-design IP runs. Two workers fit the
    # current Docker memory budget while the large N64 application run above
    # remains isolated.
    if {$n64_global_synth} {
        # Child runs do not inherit the parent Vivado thread limit. The
        # diagnostic global run needs this before synth_design to avoid OOM.
        set_property STEPS.SYNTH_DESIGN.TCL.PRE \
            $board/synthesis-single-thread.tcl [get_runs synth_1]
    }
    # MD's application OOC plus a PS IP process exhausted the Docker VM during
    # the first build. Serialize remaining runs and set child thread limits.
    if {$core_kind eq "md"} {
        foreach run [get_runs -filter {IS_SYNTHESIS == 1}] {
            if {[get_property PROGRESS $run] ne "100%"} {
                set_property STEPS.SYNTH_DESIGN.TCL.PRE $board/synthesis-single-thread.tcl $run
            }
        }
    }
    launch_runs synth_1 -jobs [expr {$n64_global_synth || $core_kind eq "md" ? 1 : 2}]
    wait_on_run synth_1
}
if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} { error "Synthesis failed" }
exec /usr/bin/python3 -E /work/scripts/snapshot-hdl.py --check $core_kind $output $output/source-snapshot.json
open_run synth_1
if {$core_kind in {gb gba}} {
    # Audit the actual primitive initialization, not only the RTL simulation.
    set boot_report [open $output/${core_kind}_boot_init.tsv w]
    foreach cell [get_cells -hierarchical -filter {REF_NAME =~ RAMB*}] {
        foreach property [lsort [list_property $cell]] {
            if {[regexp {^INIT_[0-9A-F]{2}$} $property] || ($core_kind eq "gba" && [regexp {^INITP_[0-9A-F]{2}$} $property])} {
                puts $boot_report "$cell\t$property\t[get_property $property $cell]"
            }
        }
    }
    close $boot_report
}
report_utilization -file $output/utilization_synth.rpt
source /work/hardware/kv260/audit-ram-modes.tcl
if {$core_kind eq "psx"} {
    set mmcm_count [llength [get_cells -hierarchical -filter {REF_NAME =~ MMCME4*}]]
    set uram_count [llength [get_cells -hierarchical -filter {REF_NAME =~ URAM288*}]]
    if {$mmcm_count != 4 || $uram_count != 64} {
        error "Review PSX clock/main-RAM mapping: $mmcm_count MMCM, $uram_count UltraRAM"
    }
}
if {$core_kind eq "n64"} {
    set mmcm_count [llength [get_cells -hierarchical -filter {REF_NAME =~ MMCME4*}]]
    set pll_count [llength [get_cells -hierarchical -filter {REF_NAME =~ PLLE4*}]]
    if {$mmcm_count > 4 || $pll_count < 1} {
        error "Review N64 clock mapping: $mmcm_count MMCM, $pll_count PLL"
    }
}
report_utilization -hierarchical -file $output/utilization_synth_hier.rpt
report_clocks -file $output/clocks.rpt
report_timing_summary -delay_type min_max -report_unconstrained -check_timing_verbose -file $output/timing_synth.rpt
report_cdc -details -file $output/cdc_synth.rpt
report_clock_interaction -file $output/clock_interaction_synth.rpt
report_drc -file $output/drc_synth.rpt
# Inspect the application OOC multi-term warning in the linked board netlist.
set clock_details [open $output/core_clock_nets.rpt w]
foreach clock_net [get_nets -hierarchical -filter {NAME =~ *core_clk*}] {
    puts $clock_details "NET $clock_net"
    puts $clock_details "DRIVERS [get_pins -quiet -leaf -of_objects $clock_net -filter {DIRECTION == OUT}]"
    puts $clock_details "PORTS [get_ports -quiet -of_objects $clock_net]"
}
close $clock_details
# Deliberately stop before routing until the emitted clock/CDC reports have
# been reviewed and all bundled data/FIFO constraints are installed. This is
# an implementation gate, not a claim that a synthesis result is releasable.
if {$core_kind in {gb gba}} {
    exec /usr/bin/python3 -E /work/scripts/check-${core_kind}-boot-init.py $output/${core_kind}_boot_init.tsv
}
if {$core_kind eq "gba"} { exec /usr/bin/python3 -E /work/scripts/check-gba-ram-modes.py $output/gba_ram_modes.tsv }
if {$core_kind eq "psx"} { exec /usr/bin/python3 -E /work/scripts/check-psx-ram-modes.py $output/psx_ram_modes.tsv }
puts "Synthesis checkpoint complete; physical CDC constraints and routing remain."
