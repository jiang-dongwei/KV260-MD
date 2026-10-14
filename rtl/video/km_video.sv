// SPDX-License-Identifier: GPL-3.0-or-later
// Shared real-core capture, fixed 1080p scaler, Main framebuffer and MiSTer OSD.
// sys/native clocks belong to the core; memory/output clocks belong to the PS
// shell. Reset deassertion is synchronized by that shell per receiving domain.
module km_video(
`ifdef PSX_CORE
    input wire core_bob,core_blackout,
`endif
`ifdef MISTER_FB
    input wire core_fb_enable,input wire [5:0] core_fb_format,input wire [31:0] core_fb_base,
    input wire [11:0] core_fb_width,core_fb_height,input wire [13:0] core_fb_stride,
`endif
    input wire sys_clk, input_clk, output_clk, memory_clk,
    input wire sys_resetn, output_resetn, memory_resetn, scaler_resetn,
    input wire [7:0] input_r,input_g,input_b,
    input wire input_hs,input_vs,input_de,input_ce,input_field,freeze,
    input wire io_osd,io_strobe,input wire [15:0] io_din,
    input wire [12:0] aspect_x,aspect_y,custom_ar1x,custom_ar1y,custom_ar2x,custom_ar2y,
    input wire [11:0] hsize,vsize,input wire free_scale,
    input wire fb_enable,input wire [5:0] fb_format,input wire [31:0] fb_base,
    input wire [11:0] fb_width,fb_height,fb_hmin,fb_hmax,fb_vmin,fb_vmax,
    input wire [13:0] fb_stride,
    output wire [7:0] output_r,output_g,output_b,
    output wire output_hs,output_vs,output_de,osd_status,
    output wire [11:0] detected_width,detected_height,
    input wire quiesce,input wire [39:0] memory_base,input wire [31:0] memory_size,
    output wire drained,fault,
    output wire [39:0] m_axi_awaddr, output wire [7:0] m_axi_awlen,
    output wire [2:0] m_axi_awsize, output wire [1:0] m_axi_awburst,
    output wire m_axi_awlock, output wire [3:0] m_axi_awcache,
    output wire [2:0] m_axi_awprot, output wire m_axi_awvalid, input wire m_axi_awready,
    output wire [127:0] m_axi_wdata, output wire [15:0] m_axi_wstrb,
    output wire m_axi_wlast, output wire m_axi_wvalid, input wire m_axi_wready,
    input wire [1:0] m_axi_bresp, input wire m_axi_bvalid, output wire m_axi_bready,
    output wire [39:0] m_axi_araddr, output wire [7:0] m_axi_arlen,
    output wire [2:0] m_axi_arsize, output wire [1:0] m_axi_arburst,
    output wire m_axi_arlock, output wire [3:0] m_axi_arcache,
    output wire [2:0] m_axi_arprot, output wire m_axi_arvalid, input wire m_axi_arready,
    input wire [127:0] m_axi_rdata, input wire [1:0] m_axi_rresp,
    input wire m_axi_rlast, m_axi_rvalid, output wire m_axi_rready
);
`ifndef PSX_CORE
    wire core_bob=1'b0,core_blackout=1'b0;
`endif
    wire [11:0] native_hmin,native_hmax,native_vmin,native_vmax;
    km_viewport viewport(.clk(sys_clk),.resetn(sys_resetn),
        .aspect_x(aspect_x),.aspect_y(aspect_y),.custom_ar1x(custom_ar1x),.custom_ar1y(custom_ar1y),
        .custom_ar2x(custom_ar2x),.custom_ar2y(custom_ar2y),.hsize(hsize),.vsize(vsize),.free_scale(free_scale),
        .hmin(native_hmin),.hmax(native_hmax),.vmin(native_vmin),.vmax(native_vmax));
    localparam [126:0] RESET_CONFIG={2'b00,1'b0,6'h16,32'h22000000,12'd0,12'd0,14'd0,
                                   12'd0,12'd1919,12'd0,12'd1079};
    wire [76:0] framebuffer_config={fb_enable,fb_format,fb_base,fb_width,fb_height,fb_stride};
`ifdef MISTER_FB
    // Main's file-browser framebuffer has priority. The core framebuffer renderer
    // otherwise uses the same native aspect-ratio viewport as its raster.
    wire [76:0] selected_framebuffer=fb_enable ? framebuffer_config :
        {core_fb_enable,core_fb_format,core_fb_base,core_fb_width,core_fb_height,core_fb_stride};
`else
    wire [76:0] selected_framebuffer=framebuffer_config;
`endif
    wire [126:0] source_config={core_bob,core_blackout,selected_framebuffer,
        fb_enable ? fb_hmin : native_hmin,fb_enable ? fb_hmax : native_hmax,
        fb_enable ? fb_vmin : native_vmin,fb_enable ? fb_vmax : native_vmax};
    wire [126:0] pixel_config;
    wire pixel_bob,pixel_blackout;
    wire pixel_fb_enable;
    wire [5:0] pixel_fb_format;
    wire [31:0] pixel_fb_base;
    wire [11:0] pixel_fb_width,pixel_fb_height,hmin,hmax,vmin,vmax;
    wire [13:0] pixel_fb_stride;
    assign {pixel_bob,pixel_blackout,pixel_fb_enable,pixel_fb_format,pixel_fb_base,pixel_fb_width,pixel_fb_height,
            pixel_fb_stride,hmin,hmax,vmin,vmax}=pixel_config;
    wire [7:0] r,g,b;
    wire hs,vs,de;
    km_frame_config_cdc #(.WIDTH(127),.RESET_VALUE(RESET_CONFIG)) configuration(
        .src_clk(sys_clk),.src_resetn(sys_resetn),.src_data(source_config),.src_busy(),
        .dst_clk(output_clk),.dst_resetn(output_resetn),.dst_frame(vs),.dst_data(pixel_config),.dst_changed());
    wire [27:0] avl_address;
    wire [7:0] avl_burstcount;
    wire [127:0] avl_writedata,avl_readdata;
    wire [15:0] avl_byteenable;
    wire avl_read,avl_write,avl_waitrequest,avl_readdatavalid;
    km_scaler
`ifdef SYNTHESIS
`ifdef SNES_CORE
        #(.INTERLACED(1))
`elsif PSX_CORE
        #(.INTERLACED(1))
`endif
`endif
        scaler(.resetn(scaler_resetn),.input_clk(input_clk),.output_clk(output_clk),.memory_clk(memory_clk),
        .input_field(input_field),.bob_deint(pixel_bob),.swblack(pixel_blackout),
        .input_r(input_r),.input_g(input_g),.input_b(input_b),.input_hs(input_hs),.input_vs(input_vs),
        .input_de(input_de),.input_ce(input_ce),.freeze(freeze),
        .output_r(r),.output_g(g),.output_b(b),.output_hs(hs),.output_vs(vs),.output_de(de),
        .fb_enable(pixel_fb_enable),.fb_format(pixel_fb_format),.fb_base(pixel_fb_base),
        .fb_width(pixel_fb_width),.fb_height(pixel_fb_height),.fb_stride(pixel_fb_stride),
        .hmin(hmin),.hmax(hmax),.vmin(vmin),.vmax(vmax),
        .detected_width(detected_width),.detected_height(detected_height),
        .avl_address(avl_address),.avl_burstcount(avl_burstcount),.avl_writedata(avl_writedata),
        .avl_readdata(avl_readdata),.avl_byteenable(avl_byteenable),.avl_read(avl_read),.avl_write(avl_write),
        .avl_waitrequest(avl_waitrequest),.avl_readdatavalid(avl_readdatavalid));
    osd compositor(.clk_sys(sys_clk),.io_osd(io_osd),.io_strobe(io_strobe),.io_din(io_din),
        .clk_video(output_clk),.din({r,g,b}),.de_in(de),.vs_in(vs),.hs_in(hs),
        .dout({output_r,output_g,output_b}),.de_out(output_de),.vs_out(output_vs),.hs_out(output_hs),
        .osd_status(osd_status));
    km_video_axi bridge(.clk(memory_clk),.resetn(memory_resetn),.*);
endmodule
