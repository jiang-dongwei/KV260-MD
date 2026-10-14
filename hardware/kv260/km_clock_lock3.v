// Hold N64 reset until the core and both selectable video clocks are stable.
module km_clock_lock3(
    input  wire core_locked,
    input  wire ntsc_locked,
    input  wire pal_locked,
    output wire locked
);
    assign locked = core_locked & ntsc_locked & pal_locked;
endmodule
