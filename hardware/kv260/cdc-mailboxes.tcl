# Apply only to the corrected, linked application netlist before implementation.
# This covers the platform mailboxes, not all scaler/core CDC. Remaining paths
# must still pass timing/CDC review; do not add global asynchronous clock groups.
if {![info exists core_kind] || $core_kind ni {menu nes snes gb gba psx n64 md}} {
    error "Set core_kind to menu, nes, snes, gb, gba, psx or n64 before applying mailbox constraints"
}
set km_app kria_platform_i/app/inst/impl

proc km_registers {scope stems} {
    set result {}
    foreach stem $stems {
        set result [concat $result [get_cells -quiet -hierarchical \
            -filter "NAME =~ $scope/${stem}_reg* && REF_NAME =~ FD*"]]
    }
    set result [lsort -unique $result]
    if {![llength $result]} { error "Missing payload registers: $scope / $stems" }
    return $result
}

proc km_register_clock {registers} {
    set pins [get_pins -quiet -of_objects $registers -filter {REF_PIN_NAME == C}]
    set clocks [lsort -unique [get_clocks -quiet -of_objects $pins]]
    if {[lsort $clocks] eq {snes_core_even snes_core_odd}} {
        # The two phase variants share one physical divider and period.
        return snes_core_even
    }
    if {[lsort $clocks] eq {psx_video_fast psx_video_ntsc psx_video_pal}} {
        # The reconfigured MMCM carries one of these three clocks at a
        # time. Use its fastest mode for every bundled-data physical bound.
        return psx_video_fast
    }
    if {[lsort $clocks] eq {clk_out1_kria_platform_n64_pal_video_clock_0 clk_out1_kria_platform_n64_video_clock_0}} {
        # BUFGMUX selects exactly one N64 video clock at runtime. PAL is the
        # faster mode, so its shorter period is the conservative data bound.
        return clk_out1_kria_platform_n64_pal_video_clock_0
    }
    if {[llength $clocks] != 1} { error "Expected one payload clock: $registers -> $clocks" }
    return [lindex $clocks 0]
}

proc km_payload {source_scope source_stems destination_scope destination_stems} {
    set source [km_registers $source_scope $source_stems]
    set destination [km_registers $destination_scope $destination_stems]
    set source_clock [km_register_clock $source]
    set destination_clock [km_register_clock $destination]
    if {$source_clock eq $destination_clock} {
        puts "CDC payload retains ordinary timing: $source_scope -> $destination_scope"
        return
    }
    set period [get_property PERIOD [get_clocks $destination_clock]]
    set source_pins [get_pins -of_objects $source -filter {REF_PIN_NAME == Q}]
    set destination_pins [get_pins -of_objects $destination -filter {REF_PIN_NAME == D}]
    if {![llength $source_pins] || ![llength $destination_pins]} {
        error "Payload is not a register-to-register transfer"
    }
    # Data is held until an acknowledgement, and the receiving request traverses
    # two synchronizer stages. Keep the bus arrival within one receiving cycle.
    # Cells are valid timing start/end points. Starting at Q explicitly splits
    # the clock path in Vivado and creates TIMING-13/TIMING-42 segmentation.
    set_max_delay -datapath_only $period -from $source -to $destination
    puts "CDC payload bound $period ns: $source_scope/$source_stems -> $destination_scope/$destination_stems"
}

proc km_first_stage {scope name} {
    set escaped [string map [list {[} {\[} {]} {\]}] $name]
    set cells [get_cells -quiet -hierarchical -regexp "^$scope/$escaped$"]
    # Constant/same-clock status signals can be optimized away. A surviving
    # first stage must carry the source RTL's placement attribute.
    if {![llength $cells]} { return }
    foreach cell $cells {
        if {[string toupper [get_property ASYNC_REG $cell]] ni {TRUE 1}} {
            error "First-stage register lost ASYNC_REG: $cell"
        }
    }
    set_false_path -to [get_pins -of_objects $cells -filter {REF_PIN_NAME == D}]
    puts "CDC first-stage input: $cells"
}

proc km_reset_chain {scope stems} {
    set cells [km_registers $scope $stems]
    km_register_clock $cells
    foreach cell $cells {
        if {[string toupper [get_property ASYNC_REG $cell]] ni {TRUE 1}} {
            error "Reset synchronizer lost ASYNC_REG: $cell"
        }
    }
    set reset_pins [get_pins -of_objects $cells \
        -filter {REF_PIN_NAME == CLR || REF_PIN_NAME == PRE}]
    if {[llength $reset_pins] != [llength $cells]} {
        error "Expected one asynchronous reset pin per synchronizer register"
    }
    # The asynchronous input may release near either stage's clock edge.
    # Keep Q->D between stages, and synchronized Q->consumer reset recovery /
    # removal, under ordinary timing. Exempt only these synchronizer reset pins.
    set_false_path -to $reset_pins
    puts "CDC reset-chain inputs: $reset_pins"
}

set configuration_scopes {video/configuration}
if {$core_kind ne "snes"} {
    # Vivado may retain a generate block as a slash-separated hierarchy or
    # combine it with the instance name. Resolve the exact surviving mailbox.
    set audio_scopes {}
    foreach candidate {audio/coherent_samples/samples audio/coherent_samples.samples} {
        if {[llength [get_cells -quiet -hierarchical -filter "NAME == $km_app/$candidate"]]} {
            lappend audio_scopes $candidate
        }
    }
    if {[llength $audio_scopes] != 1} { error "Expected one coherent audio mailbox: $audio_scopes" }
    lappend configuration_scopes [lindex $audio_scopes 0]
}
foreach scope $configuration_scopes {
    # Constant interpretation bits can merge with `first` (e.g. the audio
    # signed flag). It changes with the first held snapshot and then stays put.
    km_payload $km_app/$scope {held_data first} $km_app/$scope {dst_data}
    foreach name {ack_meta_reg req_meta_reg} { km_first_stage $km_app/$scope $name }
}
km_payload $km_app/video/compositor {km_osd_held} $km_app/video/compositor {km_osd_pixel}
foreach name {km_osd_ack_meta_reg km_osd_req_meta_reg} {
    km_first_stage $km_app/video/compositor $name
}
set km_measure $km_app/core/hps_io/video_calc
km_payload $km_measure {km_measure_held} $km_measure {km_measure_sys}
if {[llength [get_cells -quiet -hierarchical -filter "NAME =~ $km_measure/km_raster_held_reg*"]]} {
    km_payload $km_measure {km_raster_held} $km_measure {km_raster_sys}
    foreach name {km_raster_ack_meta_reg km_raster_req_meta_reg} { km_first_stage $km_measure $name }
}
foreach name {km_measure_ack_meta_reg km_measure_req_meta_reg km_vs_meta_reg
              km_hs_meta_reg km_de_meta_reg km_hdmi_vs_meta_reg} {
    km_first_stage $km_measure $name
}
km_payload kria_platform_i/vtc/inst {held} kria_platform_i/vtc/inst {pixel_config}
foreach name {ack_meta_reg req_meta_reg} { km_first_stage kria_platform_i/vtc/inst $name }
km_first_stage kria_platform_i/pixel_gate/inst enable_meta_reg

km_payload $km_app/control {mailbox_cmd mailbox_argument} $km_app/control {core_cmd core_argument}
km_payload $km_app/control {mailbox_result} $km_app/control {result_reg}
if {$core_kind eq "md"} {
    km_payload $km_app/md_video_snapshot {held_data} $km_app/md_video_snapshot {dst_data}
    foreach name {ack_meta_reg req_meta_reg} { km_first_stage $km_app/md_video_snapshot $name }
}
foreach name {request_sync_reg[0] response_sync_reg[0] ready_sync_reg[0]} {
    km_first_stage $km_app/control $name
}
foreach name {output_vs_sync_reg[0] native_vs_sync_reg[0]} {
    km_first_stage $km_app/framework/system_io $name
}
foreach name {video_fault_sync_reg[0] cartridge_ready_sync_reg[0] cartridge_fault_sync_reg[0] save_fault_sync_reg[0]} {
    km_first_stage $km_app $name
}
if {$core_kind in {gba psx}} {
    # The output-frame event enters the GBA host domain through two placed
    # synchronizer stages before updating its enhanced framebuffer pointer.
    km_first_stage $km_app {gba_vblank_sync_reg[0]}
}
set km_scaler $km_app/video/scaler/scaler
foreach stems {{km_i_reset_meta i_reset_na} {km_o_reset_meta o_reset_na}
               {km_avl_reset_meta avl_reset_na}} {
    km_reset_chain $km_scaler $stems
}
km_payload $km_scaler {km_offsets_held} $km_scaler \
    {avl_i_offset0 avl_i_offset1 avl_o_offset0 avl_o_offset1}
foreach name {km_offsets_req_meta_reg km_offsets_ack_meta_reg} {
    km_first_stage $km_scaler $name
}
# Capture holds its burst descriptor for at least six input cycles. The write
# toggle traverses two sampling stages and an edge detector before the memory
# domain captures it. Read addresses settle before the synchronized read event
# is consumed and remain unchanged until the returned read acknowledgement.
# The memory data RAMs and capture overrun assumptions require separate review.
km_payload $km_scaler {i_wadrs i_wline i_walt} $km_scaler {avl_wadrs avl_wline avl_walt}
km_payload $km_scaler {o_adrs o_rline} $km_scaler {avl_radrs avl_rline}
km_payload $km_scaler {km_target_held} $km_scaler {i_ohsize i_ovsize i_bob_deint}
km_payload $km_scaler {km_image_held} $km_scaler {km_image_pixel}
foreach name {km_avl_write_meta_reg km_avl_read_meta_reg km_avl_vs_meta_reg
              km_frame0_meta_reg km_frame1_meta_reg km_field_meta_reg km_readack_meta_reg
              km_readdataack_meta_reg km_target_req_meta_reg km_target_ack_meta_reg
              km_image_req_meta_reg km_image_ack_meta_reg km_i_freeze_meta_reg
              km_o_freeze_meta_reg} {
    km_first_stage $km_scaler $name
}

# The burst RAMs are read synchronously in the receiving domain, but Vivado
# implements these small arrays as distributed RAM with asynchronous data
# outputs before the receiving FD registers. Bound that data propagation;
# keep receiving address/decode -> FD paths under ordinary timing.
# Input ownership transfers after the completed capture burst's write event.
# Output ownership transfers after the final response word's data event; the
# final RAM write completes before the synchronized event can start copying.
# Throughput/overrun assumptions are separate from this physical CDC bound.
foreach {ram destination_stem} {i_dpram avl_dr o_dpram o_dr} {
    set source [get_cells -quiet -hierarchical -filter \
        "NAME =~ $km_scaler/${ram}_reg* && (REF_NAME == RAMD32 || REF_NAME == RAMS32)"]
    if {![llength $source]} { error "Review changed burst RAM inference: $ram" }
    set source_clock_pins [get_pins -of_objects $source \
        -filter {REF_PIN_NAME == CLK || REF_PIN_NAME == WCLK}]
    if {![llength $source_clock_pins]} { error "Missing distributed RAM write clocks: $ram" }
    set destination [km_registers $km_scaler [list $destination_stem]]
    set destination_clock [km_register_clock $destination]
    set period [get_property PERIOD [get_clocks $destination_clock]]
    # Use the actual sequential leaf clock pins. RAM32M16 macro containers
    # are also marked primitive by Vivado but are not timing startpoints.
    set_max_delay -datapath_only $period -from $source_clock_pins -to $destination
    puts "CDC burst RAM bound $period ns: $ram -> $destination_stem"
}
km_reset_chain $km_app {save_reset_sync}
# SNES consumes base/size in memory_lifecycle instead; its fixed-host base
# payload is removed. The fixed-host quiesce still controls video lifecycle.
if {$core_kind in {nes snes gb gba psx n64 md}} {
    if {$core_kind in {nes gb gba psx n64 md}} {
        km_payload $km_app/control {dma_base dma_size} $km_app/lifecycle {destination_base destination_size}
    }
    km_payload $km_app/lifecycle {held_quiesce} $km_app/lifecycle {destination_quiesce}
    foreach name {ack_meta_reg req_meta_reg} { km_first_stage $km_app/lifecycle $name }
}

if {$core_kind eq "n64"} {
    # The DDRAM adapter runs at 125 MHz while the main N64/application domain
    # runs at 62.5 MHz, so it has its own lifecycle mailbox.
    km_payload $km_app/control {dma_base dma_size} $km_app/n64_ddr_lifecycle {destination_base destination_size}
    km_payload $km_app/n64_ddr_lifecycle {held_quiesce} $km_app/n64_ddr_lifecycle {destination_quiesce}
    foreach name {ack_meta_reg req_meta_reg} { km_first_stage $km_app/n64_ddr_lifecycle $name }
}

if {$core_kind eq "psx"} {
    foreach name {lock_meta_reg mode_meta_reg[0] mode_meta_reg[1]} {
        km_first_stage $km_app/core/video_clock/config_writer $name
    }
}
