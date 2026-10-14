# Record active primitive pins and original RAM hierarchy in an open linked netlist.
if {$core_kind in {gba psx n64 md}} {
    set ram_modes [open $output/${core_kind}_ram_modes.tsv w]
    puts $ram_modes "cell\tprimitive\twrite_mode_a\twrite_mode_b\tread_width_a\tread_width_b\twrite_width_a\twrite_width_b\twrite_active_a\twrite_active_b\tread_active_a\tread_active_b\tram_hierarchy"
    set ground_cache [dict create]
    set ram_parent_cache [dict create]
    foreach cell [get_cells -hierarchical -filter {REF_NAME =~ RAMB*}] {
        set row [list $cell [get_property REF_NAME $cell]]
        foreach property {WRITE_MODE_A WRITE_MODE_B READ_WIDTH_A READ_WIDTH_B WRITE_WIDTH_A WRITE_WIDTH_B} {
            lappend row [get_property $property $cell]
        }
        foreach pattern {WEA* WEBWE*} {
            set active 0
            foreach enable [get_pins -of_objects $cell -filter "REF_PIN_NAME =~ $pattern"] {
                set nets [get_nets -of_objects $enable]
                if {![dict exists $ground_cache $nets]} {
                    set drivers [get_pins -quiet -leaf -of_objects $nets -filter {DIRECTION == OUT}]
                    set ground 0
                    if {[llength $drivers] == 1 && [get_property REF_NAME [get_cells -of_objects $drivers]] eq "GND"} { set ground 1 }
                    dict set ground_cache $nets $ground
                }
                if {![dict get $ground_cache $nets]} { set active 1 }
            }
            lappend row $active
        }
        foreach names {{DOADO* DOPADOP* DOUTADOUT* DOUTPADOUTP* CASDOUTA* CASDOUTPA*} {DOBDO* DOPBDOP* DOUTBDOUT* DOUTPBDOUTP* CASDOUTB* CASDOUTPB*}} {
            set active 0
            foreach pattern $names {
                foreach pin [get_pins -quiet -of_objects $cell -filter "REF_PIN_NAME =~ $pattern"] {
                    set nets [get_nets -quiet -of_objects $pin]
                    if {[llength [get_pins -quiet -leaf -of_objects $nets -filter {DIRECTION == IN}]]} { set active 1 }
                }
            }
            lappend row $active
        }
        set parents {}
        set scope [file dirname $cell]
        while {$scope ne "."} {
            if {![dict exists $ram_parent_cache $scope]} {
                set escaped [string map [list {[} {\[} {]} {\]} {.} {\.}] $scope]
                set parent [get_cells -quiet -hierarchical -regexp "^$escaped$"]
                dict set ram_parent_cache $scope [get_property -quiet REF_NAME $parent]
            }
            lappend parents [dict get $ram_parent_cache $scope]
            set scope [file dirname $scope]
        }
        lappend row [join $parents ";"]
        puts $ram_modes [join $row "\t"]
    }
    close $ram_modes
}
