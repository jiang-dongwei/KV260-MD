# Use all eight logical CPUs on the dedicated four-core/8-thread Intel host.
# Limit concurrent OOC runs separately in finish-synthesis.tcl: each Vivado
# process can hold several GiB of the 12.7 GiB Docker VM memory.
set vivado_threads 8
if {[info exists ::env(KRIA_VIVADO_THREADS)]} {
    set vivado_threads $::env(KRIA_VIVADO_THREADS)
    if {![string is integer -strict $vivado_threads] || $vivado_threads < 1 || $vivado_threads > 8} {
        error "KRIA_VIVADO_THREADS must be an integer from 1 to 8"
    }
}
set_param general.maxThreads $vivado_threads
puts "Vivado maximum threads: $vivado_threads"
