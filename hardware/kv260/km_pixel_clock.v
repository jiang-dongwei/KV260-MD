// Adapted from z486_XL/platform/kv260/rtl/z486_clock_gate_div2.v.
// Fixed-profile BD clock metadata: 297 MHz input / 2 = 148.5 MHz pixels.
`timescale 1ns/1ps

// The AVPG DRM driver programs clk_in at twice the requested pixel rate.
// Both DRM-controlled enables share one BUFGCE_DIV so scaler and VTC see the
// same pixel-clock edge.
module km_pixel_clock (
    input wire control_clk,
    input wire clk_in,
    input wire enable_video,
    input wire enable_vtc,
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 video_clk CLK" *)
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME video_clk, FREQ_HZ 148500000" *)
    output wire video_clk,
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 vtc_clk CLK" *)
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME vtc_clk, FREQ_HZ 148500000" *)
    output wire vtc_clk
);
wire pixel_clk;
// Both GPIO bits originate on control_clk. Register their OR before crossing
// domains so GPIO output skew cannot become a spurious clock-enable pulse.
reg enable = 0;
always @(posedge control_clk) enable <= enable_video | enable_vtc;
// The GPIO clock is independent of the display MMCM. Sample the combined
// enable on the ungated input so a stopped pixel clock can restart itself.
(* ASYNC_REG="TRUE" *) reg enable_meta = 0, enable_sync = 0;
always @(posedge clk_in) begin
    enable_meta <= enable;
    enable_sync <= enable_meta;
end
BUFGCE_DIV #(.BUFGCE_DIVIDE(2)) pixel_clock_buffer (
    .I(clk_in), .CE(enable_sync), .CLR(1'b0), .O(pixel_clk)
);
assign video_clk = pixel_clk;
assign vtc_clk = pixel_clk;
endmodule
