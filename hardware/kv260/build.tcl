# KV260 MiSTer full-application build. Adapted from supplied z486 live-DP wiring.
# Run with: vivado -mode batch -source /work/hardware/kv260/build.tcl -tclargs menu|nes|snes|n64
# Device/board availability is checked before creating a project; IP catalog
# queries require the opened project in Vivado 2023.2.
set core_kind [lindex $argv 0]
source /work/hardware/kv260/vivado-threads.tcl
if {$core_kind ni {menu nes snes gb gba psx n64 md}} { error "Expected menu, nes, snes, gb, gba, psx or n64" }
set part xck26-sfvc784-2LV-c
if {[llength [get_parts -quiet $part]] != 1} {
    error "K26 device data is missing. Add K26/Zynq UltraScale+ support to Vivado before building."
}
set boards [get_board_parts -quiet xilinx.com:kv260_som:part0:*]
if {![llength $boards]} { error "KV260 SOM board preset missing" }
set root /work
set board $root/hardware/kv260
set prepared $root/build/hdl/$core_kind
if {![file isdirectory $prepared]} { error "Run scripts/stage-hdl.sh in the Linux container first" }
set output /build/kria-mister-$core_kind-vivado
if {[info exists ::env(KRIA_BUILD_OUTPUT)]} {
    set output [file normalize $::env(KRIA_BUILD_OUTPUT)]
    if {![string match "/build/*" $output] || $output eq "/build"} {
        error "KRIA_BUILD_OUTPUT must name a directory below /build"
    }
}
file mkdir $output
create_project kria_mister_$core_kind $output -force -part $part
foreach ip {zynq_ultra_ps_e:3.5 smartconnect:1.0 av_pat_gen:2.0 clk_wiz:6.0 axi_gpio:2.0 xlslice:1.0 proc_sys_reset:5.0 xlconstant:1.1 util_vector_logic:2.0} {
    if {![llength [get_ipdefs -all -quiet xilinx.com:ip:$ip]]} { error "Required IP unavailable: $ip" }
}
set_property board_part [lindex [lsort -dictionary $boards] end] [current_project]
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]
set_property include_dirs [list $prepared] [get_filesets sources_1]
set headers {build_id.v}
foreach header $headers {
    add_files -norecurse $prepared/$header
    set_property file_type {Verilog Header} [get_files $prepared/$header]
}
if {$core_kind eq "menu"} {
    set_property verilog_define {MENU_CORE=1} [get_filesets sources_1]
    foreach file [list $prepared/menu.sv $prepared/sys/hps_io.sv $prepared/rtl/cos.sv \
        $root/cores/menu/km_menu_noise.sv $root/upstream/Template_MiSTeX/sys/math.sv \
        $root/upstream/NES_MiSTer/sys/iir_filter.v] { read_verilog -sv $file }

} elseif {$core_kind eq "md"} {
    set_property verilog_define {MD_CORE=1} [get_filesets sources_1]
    read_verilog -sv $root/upstream/Template_MiSTeX/sys/math.sv
    source $root/build/hdl/md-sources.tcl
    foreach file $md_vhdl_sources {
        if {[file tail $file] eq "km_md_vdp_ram.vhd"} {
            # VHDL-93 permits the standard shared-variable true dual-port RAM.
            read_vhdl $file
        } else { read_vhdl -vhdl2008 $file }
    }
    foreach file $md_verilog_sources { read_verilog -sv $file }
    foreach file [glob $prepared/rtl/FX68K/*.mem] {
        add_files -norecurse $file
        set_property file_type {Memory Initialization Files} [get_files $file]
    }
} elseif {$core_kind eq "n64"} {
    set_property verilog_define {N64_CORE=1} [get_filesets sources_1]
    source $root/build/hdl/n64-sources.tcl
    foreach file $n64_mem_sources { read_vhdl -library mem -vhdl2008 $file }
    foreach file $n64_vhdl_sources { read_vhdl -vhdl2008 $file }
    foreach file $n64_verilog_sources { read_verilog -sv $file }
    read_verilog -sv $root/upstream/Menu_MiSTer/sys/math.sv
    read_verilog -sv $prepared/sys/iir_filter.v
    read_verilog -sv $root/cores/n64/km_n64_ddram_axi.sv
    read_verilog -sv $root/cores/n64/km_n64_sdram_axi.sv
    read_verilog -sv $root/cores/n64/km_n64_boot_trace.sv
    read_verilog -sv $root/cores/n64/km_n64_ddram_trace.sv
    read_verilog -sv $root/cores/n64/km_n64_vi_error_first.sv
    read_verilog -sv $root/cores/n64/km_n64_vi_line_timing.sv
} elseif {$core_kind eq "psx"} {
    set_property verilog_define {PSX_CORE=1 MISTER_FB=1} [get_filesets sources_1]
    create_ip -name clk_wiz -vendor xilinx.com -library ip -version 6.0 -module_name km_psx_video_mmcm
    set_property -dict [list CONFIG.PRIM_IN_FREQ {99.999001} CONFIG.PRIM_SOURCE {No_buffer} \
        CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {53.693182} CONFIG.USE_DYN_RECONFIG {true} \
        CONFIG.USE_LOCKED {true} CONFIG.OVERRIDE_MMCM {true} \
        CONFIG.MMCM_DIVCLK_DIVIDE {2} CONFIG.MMCM_CLKFBOUT_MULT_F {23.625} \
        CONFIG.MMCM_CLKOUT0_DIVIDE_F {22.000}] [get_ips km_psx_video_mmcm]
    generate_target all [get_ips km_psx_video_mmcm]
    source $root/build/hdl/psx-sources.tcl
    foreach file $psx_sources {
        if {[file extension $file] eq ".vhd"} { read_vhdl -vhdl2008 $file } else { read_verilog -sv $file }
    }
} elseif {$core_kind eq "gba"} {
    set_property verilog_define {GBA_CORE=1 MISTER_FB=1} [get_filesets sources_1]
    source $root/build/hdl/gba-sources.tcl
    foreach file $gba_sources {
        if {[file extension $file] eq ".vhd"} { read_vhdl -vhdl2008 $file } else { read_verilog -sv $file }
    }
} elseif {$core_kind eq "gb"} {
    set_property verilog_define {GB_CORE=1} [get_filesets sources_1]
    source $root/build/hdl/gb-sources.tcl
    foreach file $gb_sources {
        if {[file extension $file] eq ".vhd"} { read_vhdl -vhdl2008 $file } else { read_verilog -sv $file }
    }
    foreach file [glob $prepared/BootROMs/*.hex $prepared/rtl/*.hex] { add_files -norecurse $file }
} elseif {$core_kind eq "snes"} {
    set_property verilog_define {SNES_CORE=1} [get_filesets sources_1]
    source $root/build/hdl/snes-sources.tcl
    foreach file $snes_sources {
        if {[file extension $file] eq ".vhd"} { read_vhdl -vhdl2008 $file } else { read_verilog -sv $file }
    }
    foreach file [glob -nocomplain $prepared/rtl/chip/*/*.hex] {
        add_files -norecurse $file
        set_property file_type {Memory Initialization Files} [get_files $file]
    }
} else {
    source $root/build/hdl/nes-sources.tcl
    foreach file $nes_sources {
        if {[file extension $file] eq ".vhd"} { read_vhdl -vhdl2008 $file } else { read_verilog -sv $file }
    }
    foreach file {tao.hex loopy_NSF.hex} {
        add_files -norecurse $prepared/rtl/$file
        set_property file_type {Memory Initialization Files} [get_files $prepared/rtl/$file]
    }
}
foreach file {km_control.sv km_dma_lifecycle.sv km_framework.sv km_hps_endpoint.sv km_sys_io.sv km_ddram_axi.sv} {
    read_verilog -sv $root/rtl/$file
}
foreach file {km_video.sv km_video_axi.sv km_frame_config_cdc.sv km_viewport.sv} {
    read_verilog -sv $root/rtl/video/$file
}
read_vhdl -vhdl2008 $root/build/hdl/scaler/ascal.vhd
read_vhdl -vhdl2008 $root/rtl/video/km_scaler.vhd
read_verilog -sv $prepared/sys/osd.v
foreach file {km_audio.sv km_audio_filter.sv} { read_verilog -sv $root/rtl/audio/$file }
set prior $root/z486_XL/platform/kv260/rtl
foreach file {z486_dp_audio.sv z486_rgb_to_dp36.v} {
    if {[file extension $file] eq ".sv"} { read_verilog -sv $prior/$file } else { read_verilog $prior/$file }
}
read_verilog -sv $board/km_application.sv
read_verilog $board/km_application_bd.v
if {$core_kind eq "n64"} { read_verilog -sv $board/km_n64_video_clock.sv }
read_verilog $board/km_clock_lock3.v
read_verilog $board/km_pixel_clock.v
read_verilog $board/km_vtc_lite_1ppc.v
read_xdc $board/board.xdc
update_compile_order -fileset sources_1
create_bd_design kria_platform
proc ip {name type} { return [create_bd_cell -type ip -vlnv xilinx.com:ip:$type $name] }
proc net {args} {
    set pins {}
    foreach pin $args { lappend pins [get_bd_pins $pin] }
    connect_bd_net {*}$pins
}
proc bus {a b} { connect_bd_intf_net [get_bd_intf_pins $a] [get_bd_intf_pins $b] }
set ps [ip ps zynq_ultra_ps_e:3.5]
apply_bd_automation -rule xilinx.com:bd_rule:zynq_ultra_ps_e -config {apply_board_preset "1"} $ps
set_property -dict [list CONFIG.PSU__USE__M_AXI_GP0 {1} CONFIG.PSU__USE__M_AXI_GP1 {0} \
    CONFIG.PSU__USE__S_AXI_GP2 {1} CONFIG.PSU__SAXIGP2__DATA_WIDTH {128} \
    CONFIG.PSU__USE__S_AXI_GP3 {0} CONFIG.PSU__USE__S_AXI_GP4 {1} \
    CONFIG.PSU__SAXIGP4__DATA_WIDTH {128} CONFIG.PSU__USE__S_AXI_GP5 {0} \
    CONFIG.PSU__USE__VIDEO {1} CONFIG.PSU__USE__AUDIO {1} \
    CONFIG.PSU__TTC0__WAVEOUT__ENABLE {1} CONFIG.PSU__TTC0__WAVEOUT__IO {EMIO} \
    CONFIG.PSU__CRL_APB__PL0_REF_CTRL__FREQMHZ {100}] $ps
set pl_hz [get_property CONFIG.FREQ_HZ [get_bd_pins ps/pl_clk0]]
set pl_mhz [format %.6f [expr {$pl_hz / 1000000.0}]]
puts "PS PL0 reference reported by board preset: $pl_hz Hz"
set app [create_bd_cell -type module -reference km_application_bd app]
set control [ip control_bus smartconnect:1.0]
set_property -dict [list CONFIG.NUM_MI {5} CONFIG.NUM_SI {1}] $control
set saves [ip save_bus smartconnect:1.0]
set_property -dict [list CONFIG.NUM_MI {1} CONFIG.NUM_SI {2} CONFIG.NUM_CLKS {2}] $saves
if {$core_kind in {nes psx n64}} { set_property CONFIG.NUM_CLKS {3} $saves }
set video_bus [ip video_bus smartconnect:1.0]
set_property -dict [list CONFIG.NUM_MI {1} CONFIG.NUM_SI {1}] $video_bus
set avpg [ip avpg av_pat_gen:2.0]
set_property -dict [list CONFIG.BPC {8} CONFIG.PPC {1}] $avpg
set clock [ip video_clock clk_wiz:6.0]
set_property -dict [list CONFIG.PRIM_IN_FREQ $pl_mhz CONFIG.PRIM_SOURCE {No_buffer} \
    CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {297.000} CONFIG.USE_DYN_RECONFIG {true} CONFIG.USE_LOCKED {true}] $clock
set audio [ip audio_clock clk_wiz:6.0]
set_property -dict [list CONFIG.PRIM_IN_FREQ $pl_mhz CONFIG.PRIM_SOURCE {No_buffer} \
    CONFIG.PRIMITIVE {PLL} CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {24.576} \
    CONFIG.USE_LOCKED {true}] $audio
set core_clock [ip core_clock clk_wiz:6.0]
if {$core_kind eq "n64"} {
    # 100 MHz * 15 / 1 = 1500 MHz VCO; integer outputs preserve the
    # upstream 125/93.75/62.5 MHz 2:1, 3:2 relationships exactly.
    # Enable the extra ports first because Clocking Wizard derives its hidden
    # NUM_OUT_CLKS value from the per-output USED properties.
    set_property CONFIG.CLKOUT2_USED {true} $core_clock
    set_property CONFIG.CLKOUT3_USED {true} $core_clock
    set_property -dict [list CONFIG.PRIM_IN_FREQ $pl_mhz CONFIG.PRIM_SOURCE {No_buffer} \
        CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {125.000} \
        CONFIG.CLKOUT2_REQUESTED_OUT_FREQ {93.750} CONFIG.CLKOUT3_REQUESTED_OUT_FREQ {62.500} \
        CONFIG.OVERRIDE_MMCM {true} CONFIG.MMCM_DIVCLK_DIVIDE {1} \
        CONFIG.MMCM_CLKFBOUT_MULT_F {15.000} CONFIG.MMCM_CLKOUT0_DIVIDE_F {12.000} \
        CONFIG.MMCM_CLKOUT1_DIVIDE {16} CONFIG.MMCM_CLKOUT2_DIVIDE {24} \
        CONFIG.USE_LOCKED {true}] $core_clock
    set n64_video_clock [ip n64_video_clock clk_wiz:6.0]
    set_property -dict [list CONFIG.PRIM_IN_FREQ $pl_mhz CONFIG.PRIM_SOURCE {No_buffer} \
        CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {48.680} CONFIG.USE_LOCKED {true}] $n64_video_clock
    set n64_pal_video_clock [ip n64_pal_video_clock clk_wiz:6.0]
    set_property -dict [list CONFIG.PRIM_IN_FREQ $pl_mhz CONFIG.PRIM_SOURCE {No_buffer} \
        CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {49.650} CONFIG.USE_LOCKED {true}] $n64_pal_video_clock
    create_bd_cell -type module -reference km_clock_lock3 n64_clock_locks
    set core_clock_pin core_clock/clk_out3
    net core_clock/clk_out3 app/core_clk app/core_mem_clk save_bus/aclk2
    net core_clock/clk_out2 app/n64_clk93
    net core_clock/clk_out1 app/save_clk save_bus/aclk1
    net n64_video_clock/clk_out1 app/core_video_clk
    net n64_pal_video_clock/clk_out1 app/n64_video_pal_clk
} elseif {$core_kind eq "md"} {
    # NTSC 53.693181818 MHz, exact console ratio at nominal PL0 (100 MHz).
    # All console/HPS/ROM/save paths share one clock; no toggle CDC in ROM.
    set_property -dict [list CONFIG.PRIM_IN_FREQ $pl_mhz CONFIG.PRIM_SOURCE {No_buffer} \
        CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {53.693182} \
        CONFIG.OVERRIDE_MMCM {true} CONFIG.MMCM_DIVCLK_DIVIDE {2} \
        CONFIG.MMCM_CLKFBOUT_MULT_F {23.625} CONFIG.MMCM_CLKOUT0_DIVIDE_F {22.000} \
        CONFIG.USE_LOCKED {true}] $core_clock
    set core_clock_pin core_clock/clk_out1
    net core_clock/clk_out1 app/core_clk app/core_video_clk app/core_mem_clk app/save_clk save_bus/aclk1
} elseif {$core_kind eq "psx"} {
    set_property -dict [list CONFIG.PRIM_IN_FREQ $pl_mhz CONFIG.PRIM_SOURCE {No_buffer} \
        CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {203.214286} CONFIG.CLKOUT1_DRIVES {No_buffer} \
        CONFIG.OVERRIDE_MMCM {true} CONFIG.MMCM_DIVCLK_DIVIDE {5} \
        CONFIG.MMCM_CLKFBOUT_MULT_F {71.125} CONFIG.MMCM_CLKOUT0_DIVIDE_F {7.000} \
        CONFIG.USE_LOCKED {true}] $core_clock
    set clock_source [open $board/km_psx_core_clocks.v r]
    set clock_rtl [read $clock_source]
    close $clock_source
    set replacements {}
    foreach nominal {203214286 33869048 67738095 101607143} divide {1 6 3 2} {
        lappend replacements $nominal [expr {int($pl_hz * 71.125 / 5.0 / 7.0 / $divide)}]
    }
    set generated_clocks [open $output/km_core_clocks.v w]
    puts $generated_clocks [string map $replacements $clock_rtl]
    close $generated_clocks
    read_verilog $output/km_core_clocks.v
    update_compile_order -fileset sources_1
    create_bd_cell -type module -reference km_psx_core_clocks core_dividers
    net core_clock/clk_out1 core_dividers/clk_in
    set invert [ip core_unlock util_vector_logic:2.0]
    set_property -dict [list CONFIG.C_OPERATION {not} CONFIG.C_SIZE {1}] $invert
    net core_clock/locked core_unlock/Op1
    net core_unlock/Res core_dividers/reset
    set core_clock_pin core_dividers/core_clk
    net core_dividers/core_clk app/core_clk app/core_video_clk
    net core_dividers/save_clk app/save_clk save_bus/aclk1
    net core_dividers/mem_clk app/core_mem_clk save_bus/aclk2
} elseif {$core_kind in {nes snes gb gba}} {
    # 100 MHz * 47.25 / 5 / 11 = 85.9090909 MHz. The same buffered source
    # supplies /1 memory, /2 video and /4 emulation clocks.
    set_property -dict [list CONFIG.PRIM_IN_FREQ $pl_mhz CONFIG.PRIM_SOURCE {No_buffer} \
        CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {85.909091} CONFIG.CLKOUT1_DRIVES {No_buffer} \
        CONFIG.OVERRIDE_MMCM {true} \
        CONFIG.MMCM_DIVCLK_DIVIDE {5} CONFIG.MMCM_CLKFBOUT_MULT_F {47.250} \
        CONFIG.MMCM_CLKOUT0_DIVIDE_F {11.000} CONFIG.USE_LOCKED {true}] $core_clock
    if {$core_kind eq "gb"} {
        # 134.216867 MHz -> 67.108434 MHz video and 33.554217 MHz host.
        # -6.42 ppm from the 4.194304 MHz Game Boy crystal at nominal PL0.
        set_property -dict [list CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {134.216867} \
            CONFIG.MMCM_DIVCLK_DIVIDE {5} CONFIG.MMCM_CLKFBOUT_MULT_F {69.625} \
            CONFIG.MMCM_CLKOUT0_DIVIDE_F {10.375}] $core_clock
    }
    if {$core_kind eq "gba"} {
        # 100.663350 MHz host and related /2 video; GBA uses six host
        # cycles per 16.777216 MHz console cycle (+0.536 ppm nominal).
        set_property -dict [list CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {100.663350} \
            CONFIG.MMCM_DIVCLK_DIVIDE {9} CONFIG.MMCM_CLKFBOUT_MULT_F {75.875} \
            CONFIG.MMCM_CLKOUT0_DIVIDE_F {8.375}] $core_clock
    }
    # Module-reference HDL attributes are reapplied during BD propagation,
    # overriding a direct set_property on its clock pins. Generate metadata
    # from the real PS reference and the enforced MMCM ratio instead.
    set core_mem_hz [expr {int($pl_hz * 47.25 / 5.0 / 11.0)}]
    if {$core_kind eq "gb"} { set core_mem_hz [expr {int($pl_hz * 69.625 / 5.0 / 10.375)}] }
    if {$core_kind eq "gba"} { set core_mem_hz [expr {int($pl_hz * 75.875 / 9.0 / 8.375)}] }
    set clock_source [open $board/km_core_clocks.v r]
    set clock_hdl [read $clock_source]
    close $clock_source
    set clock_hdl [string map [list 85909091 $core_mem_hz \
        42954545 [expr {$core_mem_hz / 2}] 21477273 [expr {$core_mem_hz / 4}]] $clock_hdl]
    set clock_source [open $output/km_core_clocks.v w]
    puts $clock_source $clock_hdl
    close $clock_source
    read_verilog $output/km_core_clocks.v
    update_compile_order -fileset sources_1
    create_bd_cell -type module -reference km_core_clocks core_dividers
    net core_clock/clk_out1 core_dividers/clk_in
    # One common asynchronous clear for all three buffers.
    set invert [ip core_unlock util_vector_logic:2.0]
    set_property -dict [list CONFIG.C_OPERATION {not} CONFIG.C_SIZE {1}] $invert
    net core_clock/locked core_unlock/Op1
    net core_unlock/Res core_dividers/reset
    set core_clock_pin core_dividers/core_clk
    if {$core_kind eq "gba"} { set core_clock_pin core_dividers/mem_clk }
    net $core_clock_pin app/core_clk
    if {$core_kind in {snes gba}} {
        net core_dividers/mem_clk app/save_clk save_bus/aclk1
    } else {
        net core_dividers/core_clk app/save_clk save_bus/aclk1
    }
    net core_dividers/video_clk app/core_video_clk
    if {$core_kind eq "gb"} {
        # Game Boy's ROM cache and save-state AXI engines share clk_sys.
        # core_mem_clk also carries the cart_axi interface metadata.
        net core_dividers/core_clk app/core_mem_clk
    } else {
        net core_dividers/mem_clk app/core_mem_clk
    }
    if {$core_kind eq "nes"} { net core_dividers/mem_clk save_bus/aclk2 }
} else {
    set_property -dict [list CONFIG.PRIM_IN_FREQ $pl_mhz CONFIG.PRIM_SOURCE {No_buffer} \
        CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {20.000} \
        CONFIG.OVERRIDE_MMCM {true} \
        CONFIG.MMCM_DIVCLK_DIVIDE {5} CONFIG.MMCM_CLKFBOUT_MULT_F {50.000} \
        CONFIG.MMCM_CLKOUT0_DIVIDE_F {50.000} CONFIG.USE_LOCKED {true}] $core_clock
    net core_clock/clk_out1 app/core_video_clk
    net ps/pl_clk0 app/core_clk app/core_mem_clk app/save_clk save_bus/aclk1
    set core_clock_pin ps/pl_clk0
}
if {$core_kind ne "n64"} { net ps/pl_clk0 app/n64_clk93 app/n64_video_pal_clk }
set gpio [ip clock_enable axi_gpio:2.0]
set_property -dict [list CONFIG.C_ALL_OUTPUTS {1} CONFIG.C_DOUT_DEFAULT {0x00000000} CONFIG.C_GPIO_WIDTH {2} CONFIG.C_IS_DUAL {0}] $gpio
foreach {name bit width} {ce_video 0 2 ce_vtc 1 2 fan_pwm 2 3} {
    set slice [ip $name xlslice:1.0]
    set_property -dict [list CONFIG.DIN_FROM $bit CONFIG.DIN_TO $bit CONFIG.DIN_WIDTH $width CONFIG.DOUT_WIDTH {1}] $slice
}
create_bd_cell -type module -reference km_pixel_clock pixel_gate
create_bd_cell -type module -reference z486_rgb_to_dp36 rgb_to_dp
create_bd_cell -type module -reference z486_vtc_lite_1ppc vtc
foreach name {reset video_reset audio_reset core_reset} {
    set reset_cell [ip $name proc_sys_reset:5.0]
}
set one [ip one xlconstant:1.1]
set_property CONFIG.CONST_VAL {1} $one
bus ps/M_AXI_HPM0_FPD control_bus/S00_AXI
foreach {index destination} {00 avpg/av_axi 01 vtc/S_AXI 02 clock_enable/S_AXI 03 video_clock/s_axi_lite 04 app/s_axi} {
    bus control_bus/M${index}_AXI $destination
}
bus app/video_axi video_bus/S00_AXI
bus video_bus/M00_AXI ps/S_AXI_HP2_FPD
bus app/save_axi save_bus/S00_AXI
bus app/cart_axi save_bus/S01_AXI
bus save_bus/M00_AXI ps/S_AXI_HP0_FPD
bus app/audio_axis avpg/aud_in_axi4s
bus avpg/aud_out_axi4s ps/S_AXIS_AUDIO
foreach channel {r g b} { net app/video_$channel rgb_to_dp/$channel }
net rgb_to_dp/dp36 ps/dp_live_video_in_pixel1
net app/video_hs ps/dp_live_video_in_hsync
net app/video_vs ps/dp_live_video_in_vsync
net app/video_de ps/dp_live_video_in_de
net ps/pl_clk0 ps/maxihpm0_fpd_aclk ps/saxihp0_fpd_aclk ps/saxihp2_fpd_aclk \
    control_bus/aclk save_bus/aclk video_bus/aclk app/axi_clk avpg/av_axi_aclk vtc/s_axi_aclk \
    clock_enable/s_axi_aclk video_clock/s_axi_aclk video_clock/clk_in1 pixel_gate/control_clk \
    audio_clock/clk_in1 core_clock/clk_in1 reset/slowest_sync_clk
if {$core_kind eq "n64"} {
    net ps/pl_clk0 n64_video_clock/clk_in1 n64_pal_video_clock/clk_in1
    net core_clock/locked n64_clock_locks/core_locked
    net n64_video_clock/locked n64_clock_locks/ntsc_locked
    net n64_pal_video_clock/locked n64_clock_locks/pal_locked
}
net ps/pl_resetn0 reset/ext_reset_in video_reset/ext_reset_in audio_reset/ext_reset_in core_reset/ext_reset_in
net one/dout reset/dcm_locked
net video_clock/locked video_reset/dcm_locked
net audio_clock/locked audio_reset/dcm_locked
if {$core_kind eq "n64"} {
    net n64_clock_locks/locked core_reset/dcm_locked
} else {
    net core_clock/locked core_reset/dcm_locked
}
net $core_clock_pin core_reset/slowest_sync_clk
net reset/interconnect_aresetn control_bus/aresetn save_bus/aresetn video_bus/aresetn
net reset/peripheral_aresetn app/axi_resetn avpg/av_axi_aresetn vtc/s_axi_aresetn \
    clock_enable/s_axi_aresetn video_clock/s_axi_aresetn
net core_reset/peripheral_aresetn app/core_resetn
net clock_enable/gpio_io_o ce_video/Din ce_vtc/Din
net ce_video/Dout pixel_gate/enable_video
net ce_vtc/Dout pixel_gate/enable_vtc
net video_clock/clk_out1 pixel_gate/clk_in
net pixel_gate/video_clk app/video_clk avpg/vid_out_axi4s_aclk video_reset/slowest_sync_clk ps/dp_video_in_clk vtc/pixel_clk
net video_reset/peripheral_aresetn app/video_resetn avpg/vid_out_axi4s_aresetn vtc/pixel_resetn
net audio_clock/clk_out1 app/audio_clk avpg/aud_clk avpg/aud_out_axi4s_aclk ps/dp_s_axis_audio_clk audio_reset/slowest_sync_clk
net audio_reset/peripheral_aresetn app/audio_resetn avpg/aud_out_axi4s_aresetn
net one/dout vtc/pixel_ce
net ps/emio_ttc0_wave_o fan_pwm/Din
connect_bd_net [get_bd_pins fan_pwm/Dout] [create_bd_port -dir O fan_en_b]
assign_bd_address
# Override the automatic control map to match the versioned DT/MMIO contract.
foreach {interface offset} {avpg/av_axi 0xA0000000 vtc/S_AXI 0xA0010000 clock_enable/S_AXI 0xA0020000 video_clock/s_axi_lite 0xA0030000 app/s_axi 0xA0040000} {
    set segment [get_bd_addr_segs -of_objects [get_bd_intf_pins $interface]]
    if {[llength $segment]!=1} { error "Ambiguous address segment: $interface" }
    assign_bd_address -force -offset $offset -range 0x10000 -target_address_space [get_bd_addr_spaces ps/Data] $segment
}
# Keep the intended rational clock relationship. Automatic frequency search
# previously selected 119.5/9/66.375 for Menu, producing 20.004 MHz and a
# needlessly long common period with the 100 MHz framework clock.
if {$core_kind eq "md"} { set ratios {2 23.625 22.0} } elseif {$core_kind eq "menu"} { set ratios {5 50.0 50.0} } elseif {$core_kind eq "gb"} { set ratios {5 69.625 10.375} } elseif {$core_kind eq "gba"} { set ratios {9 75.875 8.375} } elseif {$core_kind eq "psx"} { set ratios {5 71.125 7.0} } elseif {$core_kind eq "n64"} { set ratios {1 15.0 12.0} } else { set ratios {5 47.25 11.0} }
foreach parameter {MMCM_DIVCLK_DIVIDE MMCM_CLKFBOUT_MULT_F MMCM_CLKOUT0_DIVIDE_F} expected $ratios {
    if {abs([get_property CONFIG.$parameter $core_clock] - $expected) > 0.000001} {
        error "Clock Wizard changed the intended $core_kind ratio: $parameter"
    }
}
# The buffered SNES audio cadence uses the exact installed audio MMCM ratio,
# not the rounded 24.576 MHz request. Keep this common frequency reference
# explicit so a Clock Wizard re-selection cannot cause long-term FIFO drift.
foreach parameter {MMCM_DIVCLK_DIVIDE MMCM_CLKFBOUT_MULT_F MMCM_CLKOUT0_DIVIDE_F} expected {1 15 61} {
    if {abs([get_property CONFIG.$parameter $audio] - $expected) > 0.000001} {
        error "Clock Wizard changed the audio ratio used by the logical sample queue: $parameter=[get_property CONFIG.$parameter $audio], expected $expected"
    }
}
validate_bd_design
foreach name {reset video_reset audio_reset core_reset} {
    if {[get_property CONFIG.C_EXT_RESET_HIGH [get_bd_cells $name]] != 0} {
        error "PS active-low reset polarity did not propagate to $name"
    }
}
save_bd_design
set bd [get_files kria_platform.bd]
set n64_global_synth 0
if {$core_kind eq "n64" && [info exists ::env(KRIA_N64_GLOBAL_SYNTH)]} {
    set n64_global_synth [expr {$::env(KRIA_N64_GLOBAL_SYNTH) eq "1"}]
}
if {$n64_global_synth} {
    # Diagnostic workaround for the reproducible application OOC stall.
    # Keep the normal OOC flow untouched unless explicitly requested.
    set_property SYNTH_CHECKPOINT_MODE NONE $bd
    puts "N64 diagnostic global synthesis: [get_property SYNTH_CHECKPOINT_MODE $bd]"
}
generate_target all $bd
add_files -norecurse [make_wrapper -files $bd -top]
set_property top kria_platform_wrapper [current_fileset]
update_compile_order -fileset sources_1
report_ip_status -file $output/ip_status.rpt
source $board/finish-synthesis.tcl
