// SPDX-License-Identifier: GPL-3.0-or-later
// Shared MiSTer control plumbing for Menu and NES. sys_clk must equal the
// clock returned by the core on HPS_BUS[36]. Native video feeds video_calc;
// output_vs is the fixed DisplayPort raster used by the vsync wait command.
module km_framework #(parameter [7:0] CORE_TYPE=8'ha4)(
    input wire sys_clk, input wire resetn, input wire clk_100m,
    input wire native_video_clk, native_ce, native_de, native_hs, native_vs, native_f1,
    input wire output_vs, input wire [12:0] aspect_x, aspect_y,
    input wire [1:0] buttons,
    input wire cmd_valid, input wire [1:0] cmd, input wire [31:0] argument,
    output wire cmd_accept, rsp_valid, output wire [31:0] result,
    inout wire [45:0] HPS_BUS,
    output wire io_osd, io_strobe, output wire [15:0] io_din,
    output wire core_reset, user_led,
    output wire [15:0] cfg, leds, output wire [4:0] volume_attenuation,
    output wire [11:0] hsize, vsize, output wire free_scale,
    output wire [12:0] custom_ar1x, custom_ar1y, custom_ar2x, custom_ar2y,
    output wire fb_enable, output wire [5:0] fb_format,
    output wire [31:0] fb_base, output wire [11:0] fb_width, fb_height,
    output wire [11:0] fb_hmin, fb_hmax, fb_vmin, fb_vmax,
    output wire [13:0] fb_stride, output wire fb_changed, fb_error
);
    wire io_fpga, io_uio, vs_wait;
    wire [15:0] sys_dout;
    assign HPS_BUS[45:38]={native_f1,output_vs,clk_100m,native_video_clk,
                          native_ce,native_de,native_hs,native_vs};
    assign HPS_BUS[35:33]={io_fpga,io_uio,io_strobe};
    assign HPS_BUS[31:16]=io_din;
    km_hps_endpoint #(.CORE_TYPE(CORE_TYPE)) endpoint(
        .clk(sys_clk),.resetn(resetn),.cmd_valid(cmd_valid),.cmd(cmd),.argument(argument),
        .cmd_accept(cmd_accept),.rsp_valid(rsp_valid),.result(result),
        .io_dout(HPS_BUS[15:0] | sys_dout),.io_wide(HPS_BUS[32]),
        .io_wait(HPS_BUS[37]),.vs_wait(vs_wait),.buttons(buttons),
        .io_din(io_din),.io_strobe(io_strobe),.io_fpga(io_fpga),.io_uio(io_uio),
        .io_osd(io_osd),.core_reset(core_reset),.user_led(user_led)
    );
    km_sys_io system_io(
        .clk(sys_clk),.resetn(resetn),.io_uio(io_uio),.io_strobe(io_strobe),.io_din(io_din),
        .io_dout(sys_dout),.output_vs(output_vs),.native_vs(native_vs),
        .aspect_x(aspect_x),.aspect_y(aspect_y),.vs_wait(vs_wait),
        .cfg(cfg),.volume_attenuation(volume_attenuation),.leds(leds),
        .hsize(hsize),.vsize(vsize),.free_scale(free_scale),
        .custom_ar1x(custom_ar1x),.custom_ar1y(custom_ar1y),
        .custom_ar2x(custom_ar2x),.custom_ar2y(custom_ar2y),
        .fb_enable(fb_enable),.fb_format(fb_format),.fb_base(fb_base),
        .fb_width(fb_width),.fb_height(fb_height),.fb_hmin(fb_hmin),.fb_hmax(fb_hmax),
        .fb_vmin(fb_vmin),.fb_vmax(fb_vmax),.fb_stride(fb_stride),
        .fb_changed(fb_changed),.fb_error(fb_error)
    );
endmodule
