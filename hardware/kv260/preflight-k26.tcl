# Read-only toolchain gate before an isolated KV260 build. No HDL is compiled.
source /work/hardware/kv260/vivado-threads.tcl
set selected_version [version -short]
if {[info exists ::env(KRIA_VIVADO_VERSION)] &&
    $::env(KRIA_VIVADO_VERSION) ne $selected_version} {
    error "Requested Vivado $::env(KRIA_VIVADO_VERSION), running $selected_version"
}
set part xck26-sfvc784-2LV-c
if {[llength [get_parts -quiet $part]] != 1} {
    error "Missing exact K26 part: $part"
}
set boards [get_board_parts -quiet xilinx.com:kv260_som:part0:*]
if {![llength $boards]} {
    error "Missing KV260 SOM board preset"
}
create_project -in_memory -part $part
foreach ip {zynq_ultra_ps_e:3.5 smartconnect:1.0 av_pat_gen:2.0 clk_wiz:6.0 axi_gpio:2.0 xlslice:1.0 proc_sys_reset:5.0 xlconstant:1.1 util_vector_logic:2.0} {
    if {![llength [get_ipdefs -all -quiet xilinx.com:ip:$ip]]} {
        error "Missing required IP: $ip"
    }
}
if {![info exists ::env(XILINX_VIVADO)] ||
    ![file executable [file join $::env(XILINX_VIVADO) bin bootgen]]} {
    error "Missing bootgen for selected Vivado"
}
puts "K26 preflight PASS: Vivado $selected_version; part $part; board [lindex [lsort -dictionary $boards] end]; required IP and bootgen present"
