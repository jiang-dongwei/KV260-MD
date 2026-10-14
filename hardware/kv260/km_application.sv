// SPDX-License-Identifier: GPL-3.0-or-later
// Common application for the separately built real Menu, NES and SNES cores.
// AXI/control/video memory share 100 MHz; save AXI uses the core clock and
// crosses through the board SmartConnect. Reset inputs assert together on
// application replacement and release synchronously in their named domains.
module km_application(
    (* X_INTERFACE_INFO="xilinx.com:signal:clock:1.0 axi_clk CLK" *)
    (* X_INTERFACE_PARAMETER="XIL_INTERFACENAME axi_clk, ASSOCIATED_BUSIF s_axi:video_axi, ASSOCIATED_RESET axi_resetn" *)
    input wire axi_clk,input wire axi_resetn,
    (* X_INTERFACE_INFO="xilinx.com:signal:clock:1.0 core_clk CLK" *)
    (* X_INTERFACE_PARAMETER="XIL_INTERFACENAME core_clk, ASSOCIATED_RESET core_resetn" *)
    input wire core_clk,input wire core_resetn,
    input wire core_video_clk,
    input wire n64_video_pal_clk,
    input wire n64_clk93,
    (* X_INTERFACE_INFO="xilinx.com:signal:clock:1.0 core_mem_clk CLK" *)
    (* X_INTERFACE_PARAMETER="XIL_INTERFACENAME core_mem_clk, ASSOCIATED_BUSIF cart_axi" *)
    input wire core_mem_clk,
    (* X_INTERFACE_INFO="xilinx.com:signal:clock:1.0 save_clk CLK" *)
    (* X_INTERFACE_PARAMETER="XIL_INTERFACENAME save_clk, ASSOCIATED_BUSIF save_axi" *)
    input wire save_clk,
    input wire video_clk,video_resetn,
    (* X_INTERFACE_INFO="xilinx.com:signal:clock:1.0 audio_clk CLK" *)
    (* X_INTERFACE_PARAMETER="XIL_INTERFACENAME audio_clk, ASSOCIATED_BUSIF audio_axis, ASSOCIATED_RESET audio_resetn" *)
    input wire audio_clk,input wire audio_resetn,
    output wire [7:0] video_r,video_g,video_b,
    output wire video_hs,video_vs,video_de,
    (* X_INTERFACE_INFO="xilinx.com:interface:axis:1.0 audio_axis TDATA" *)
    output wire [31:0] audio_axis_tdata,
    (* X_INTERFACE_INFO="xilinx.com:interface:axis:1.0 audio_axis TID" *)
    output wire [7:0] audio_axis_tid,
    (* X_INTERFACE_INFO="xilinx.com:interface:axis:1.0 audio_axis TVALID" *)
    output wire audio_axis_tvalid,
    (* X_INTERFACE_INFO="xilinx.com:interface:axis:1.0 audio_axis TREADY" *)
    input wire audio_axis_tready,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 s_axi AWADDR" *)
    input wire [7:0]  s_axi_awaddr,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 s_axi AWVALID" *)
    input wire s_axi_awvalid,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 s_axi AWREADY" *)
    output wire s_axi_awready,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 s_axi WDATA" *)
    input wire [31:0] s_axi_wdata,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 s_axi WSTRB" *)
    input wire [3:0]  s_axi_wstrb,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 s_axi WVALID" *)
    input wire s_axi_wvalid,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 s_axi WREADY" *)
    output wire s_axi_wready,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 s_axi BRESP" *)
    output wire [1:0]  s_axi_bresp,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 s_axi BVALID" *)
    output wire s_axi_bvalid,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 s_axi BREADY" *)
    input wire s_axi_bready,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 s_axi ARADDR" *)
    input wire [7:0]  s_axi_araddr,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 s_axi ARVALID" *)
    input wire s_axi_arvalid,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 s_axi ARREADY" *)
    output wire s_axi_arready,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 s_axi RDATA" *)
    output wire [31:0] s_axi_rdata,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 s_axi RRESP" *)
    output wire [1:0]  s_axi_rresp,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 s_axi RVALID" *)
    output wire s_axi_rvalid,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 s_axi RREADY" *)
    input wire s_axi_rready,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 video_axi AWADDR" *)
    output wire [39:0] video_axi_awaddr,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 video_axi AWLEN" *)
    output wire [7:0] video_axi_awlen,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 video_axi AWSIZE" *)
    output wire [2:0] video_axi_awsize,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 video_axi AWBURST" *)
    output wire [1:0] video_axi_awburst,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 video_axi AWLOCK" *)
    output wire video_axi_awlock,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 video_axi AWCACHE" *)
    output wire [3:0] video_axi_awcache,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 video_axi AWPROT" *)
    output wire [2:0] video_axi_awprot,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 video_axi AWVALID" *)
    output wire video_axi_awvalid,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 video_axi AWREADY" *)
    input wire video_axi_awready,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 video_axi WDATA" *)
    output wire [127:0] video_axi_wdata,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 video_axi WSTRB" *)
    output wire [15:0] video_axi_wstrb,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 video_axi WLAST" *)
    output wire video_axi_wlast,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 video_axi WVALID" *)
    output wire video_axi_wvalid,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 video_axi WREADY" *)
    input wire video_axi_wready,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 video_axi BRESP" *)
    input wire [1:0] video_axi_bresp,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 video_axi BVALID" *)
    input wire video_axi_bvalid,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 video_axi BREADY" *)
    output wire video_axi_bready,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 video_axi ARADDR" *)
    output wire [39:0] video_axi_araddr,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 video_axi ARLEN" *)
    output wire [7:0] video_axi_arlen,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 video_axi ARSIZE" *)
    output wire [2:0] video_axi_arsize,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 video_axi ARBURST" *)
    output wire [1:0] video_axi_arburst,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 video_axi ARLOCK" *)
    output wire video_axi_arlock,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 video_axi ARCACHE" *)
    output wire [3:0] video_axi_arcache,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 video_axi ARPROT" *)
    output wire [2:0] video_axi_arprot,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 video_axi ARVALID" *)
    output wire video_axi_arvalid,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 video_axi ARREADY" *)
    input wire video_axi_arready,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 video_axi RDATA" *)
    input wire [127:0] video_axi_rdata,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 video_axi RRESP" *)
    input wire [1:0] video_axi_rresp,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 video_axi RLAST" *)
    input wire video_axi_rlast,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 video_axi RVALID" *)
    input wire video_axi_rvalid,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 video_axi RREADY" *)
    output wire video_axi_rready,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 save_axi AWADDR" *)
    output wire [39:0] save_axi_awaddr,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 save_axi AWLEN" *)
    output wire [7:0] save_axi_awlen,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 save_axi AWSIZE" *)
    output wire [2:0] save_axi_awsize,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 save_axi AWBURST" *)
    output wire [1:0] save_axi_awburst,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 save_axi AWLOCK" *)
    output wire save_axi_awlock,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 save_axi AWCACHE" *)
    output wire [3:0] save_axi_awcache,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 save_axi AWPROT" *)
    output wire [2:0] save_axi_awprot,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 save_axi AWVALID" *)
    output wire save_axi_awvalid,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 save_axi AWREADY" *)
    input wire save_axi_awready,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 save_axi WDATA" *)
    output wire [63:0] save_axi_wdata,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 save_axi WSTRB" *)
    output wire [7:0] save_axi_wstrb,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 save_axi WLAST" *)
    output wire save_axi_wlast,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 save_axi WVALID" *)
    output wire save_axi_wvalid,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 save_axi WREADY" *)
    input wire save_axi_wready,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 save_axi BRESP" *)
    input wire [1:0] save_axi_bresp,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 save_axi BVALID" *)
    input wire save_axi_bvalid,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 save_axi BREADY" *)
    output wire save_axi_bready,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 save_axi ARADDR" *)
    output wire [39:0] save_axi_araddr,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 save_axi ARLEN" *)
    output wire [7:0] save_axi_arlen,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 save_axi ARSIZE" *)
    output wire [2:0] save_axi_arsize,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 save_axi ARBURST" *)
    output wire [1:0] save_axi_arburst,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 save_axi ARLOCK" *)
    output wire save_axi_arlock,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 save_axi ARCACHE" *)
    output wire [3:0] save_axi_arcache,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 save_axi ARPROT" *)
    output wire [2:0] save_axi_arprot,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 save_axi ARVALID" *)
    output wire save_axi_arvalid,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 save_axi ARREADY" *)
    input wire save_axi_arready,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 save_axi RDATA" *)
    input wire [63:0] save_axi_rdata,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 save_axi RRESP" *)
    input wire [1:0] save_axi_rresp,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 save_axi RLAST" *)
    input wire save_axi_rlast,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 save_axi RVALID" *)
    input wire save_axi_rvalid,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 save_axi RREADY" *)
    output wire save_axi_rready,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 cart_axi AWADDR" *)
    output wire [39:0] cart_axi_awaddr,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 cart_axi AWLEN" *)
    output wire [7:0] cart_axi_awlen,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 cart_axi AWSIZE" *)
    output wire [2:0] cart_axi_awsize,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 cart_axi AWBURST" *)
    output wire [1:0] cart_axi_awburst,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 cart_axi AWLOCK" *)
    output wire cart_axi_awlock,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 cart_axi AWCACHE" *)
    output wire [3:0] cart_axi_awcache,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 cart_axi AWPROT" *)
    output wire [2:0] cart_axi_awprot,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 cart_axi AWVALID" *)
    output wire cart_axi_awvalid,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 cart_axi AWREADY" *)
    input wire cart_axi_awready,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 cart_axi WDATA" *)
    output wire [63:0] cart_axi_wdata,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 cart_axi WSTRB" *)
    output wire [7:0] cart_axi_wstrb,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 cart_axi WLAST" *)
    output wire cart_axi_wlast,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 cart_axi WVALID" *)
    output wire cart_axi_wvalid,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 cart_axi WREADY" *)
    input wire cart_axi_wready,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 cart_axi BRESP" *)
    input wire [1:0] cart_axi_bresp,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 cart_axi BVALID" *)
    input wire cart_axi_bvalid,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 cart_axi BREADY" *)
    output wire cart_axi_bready,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 cart_axi ARADDR" *)
    output wire [39:0] cart_axi_araddr,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 cart_axi ARLEN" *)
    output wire [7:0] cart_axi_arlen,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 cart_axi ARSIZE" *)
    output wire [2:0] cart_axi_arsize,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 cart_axi ARBURST" *)
    output wire [1:0] cart_axi_arburst,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 cart_axi ARLOCK" *)
    output wire cart_axi_arlock,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 cart_axi ARCACHE" *)
    output wire [3:0] cart_axi_arcache,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 cart_axi ARPROT" *)
    output wire [2:0] cart_axi_arprot,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 cart_axi ARVALID" *)
    output wire cart_axi_arvalid,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 cart_axi ARREADY" *)
    input wire cart_axi_arready,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 cart_axi RDATA" *)
    input wire [63:0] cart_axi_rdata,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 cart_axi RRESP" *)
    input wire [1:0] cart_axi_rresp,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 cart_axi RLAST" *)
    input wire cart_axi_rlast,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 cart_axi RVALID" *)
    input wire cart_axi_rvalid,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 cart_axi RREADY" *)
    output wire cart_axi_rready
);
    wire [39:0] dma_base,core_dma_base;
    wire [31:0] core_debug;
    wire [31:0] dma_size,core_dma_size;
    wire save_fault,video_fault,cartridge_ready,cartridge_fault;
    wire quiesce,core_quiesce,save_ack,save_drained,video_drained;
    wire memory_ack,host_drained,native_video_clock;
    wire save_quiesce,save_resetn;
    wire [39:0] save_dma_base;
    wire [31:0] save_dma_size;
    // The save port uses the fixed host clock on Menu/NES and the ungated
    // memory root on SNES. Reset asserts with the common application reset.
    (* ASYNC_REG="TRUE" *) reg [1:0] save_reset_sync;
    always @(posedge save_clk or negedge core_resetn)
        if(!core_resetn) save_reset_sync<=0; else save_reset_sync<={save_reset_sync[0],1'b1};
    assign save_resetn=save_reset_sync[1];
    wire [671:0] debug_snapshot_axi;
    wire [28:0] ddram_addr;
    wire [7:0] ddram_burstcnt,ddram_be;
    wire [63:0] ddram_din,ddram_dout;
    wire ddram_rd,ddram_we,ddram_busy,ddram_dout_ready;
`ifdef N64_CORE
    wire n64_sdram_drained,n64_sdram_fault;
    wire n64_pal,n64_video_clock;
    wire n64_save_ack,n64_save_quiesce;
    wire [39:0] n64_save_base;
    wire [31:0] n64_save_size;
    wire n64_ch1_req,n64_ch1_rnw,n64_ch1_ready,n64_ch1_reqprocessed;
    wire [26:0] n64_ch1_addr,n64_ch2_addr;
    wire [31:0] n64_ch1_din,n64_ch1_dout,n64_ch2_din;
    wire [3:0] n64_ch1_be;
    wire n64_ch2_req,n64_ch2_ready;
    wire [7:0] n64_boot_debug;
    wire [11:0] n64_debug_sticky;
    wire [127:0] n64_native_debug;
    wire [28:0] n64_native_errors;
    wire [1:0] n64_vi_error_sources;
    wire [1:0] n64_vi_mem_events;
    wire [2:0] n64_vi_error_state;
    wire [1:0] n64_vi_first_error;
    wire [31:0] n64_vi_timing_source;
    wire [383:0] n64_trace_source;
    wire [255:0] n64_ddr_trace_source;
    wire [11:0] n64_debug_events;
    assign n64_debug_events[0]=n64_ch1_req;
    assign n64_debug_events[1]=n64_ch1_ready;
    assign n64_debug_events[2]=cart_axi_awvalid;
    assign n64_debug_events[3]=cart_axi_awvalid && cart_axi_awready;
    assign n64_debug_events[4]=cart_axi_wvalid;
    assign n64_debug_events[5]=cart_axi_wvalid && cart_axi_wready;
    assign n64_debug_events[6]=cart_axi_bvalid;
    assign n64_debug_events[7]=cart_axi_bvalid && cart_axi_bready;
    assign n64_debug_events[8]=cart_axi_arvalid;
    assign n64_debug_events[9]=cart_axi_arvalid && cart_axi_arready;
    assign n64_debug_events[10]=cart_axi_rvalid;
    assign n64_debug_events[11]=cart_axi_rvalid && cart_axi_rready && cart_axi_rlast;
    km_n64_boot_trace boot_trace(.clk(core_clk),.bridge_resetn(core_resetn),
        .quiesce(core_quiesce),.fault(n64_sdram_fault),.boot_flags(n64_boot_debug),
        .bus_events(n64_debug_events),.native_state(n64_native_debug),
        .native_errors(n64_native_errors),.req(n64_ch1_req),.rnw(n64_ch1_rnw),
        .done(n64_ch1_ready),.address(n64_ch1_addr),
        .history(n64_debug_sticky),.snapshot(n64_trace_source));
    km_frame_config_cdc #(.WIDTH(384),.FRAME_BOUNDARY(0)) n64_debug_snapshot(
        .src_clk(core_clk),.src_resetn(core_resetn),.src_data(n64_trace_source),.src_busy(),
        .dst_clk(axi_clk),.dst_resetn(axi_resetn),.dst_frame(1'b0),
        .dst_data(debug_snapshot_axi[383:0]),.dst_changed());
    km_n64_ddram_trace n64_ddr_trace(
        .clk(save_clk),.resetn(save_resetn),.native_ddr_error(n64_native_errors[3]),
        .ddram_addr(ddram_addr),.ddram_burstcnt(ddram_burstcnt),
        .ddram_rd(ddram_rd),.ddram_we(ddram_we),.ddram_busy(ddram_busy),
        .ddram_dout_ready(ddram_dout_ready),.adapter_fault(save_fault),
        .axi_araddr(save_axi_araddr),.axi_arvalid(save_axi_arvalid),
        .axi_arready(save_axi_arready),.axi_rvalid(save_axi_rvalid),
        .axi_rready(save_axi_rready),.axi_rlast(save_axi_rlast),
        .axi_rresp(save_axi_rresp),.snapshot(n64_ddr_trace_source));
    km_n64_vi_error_first n64_vi_first(
        .clk(core_clk),.resetn(core_resetn),
        .linefetch_error(n64_vi_error_sources[0]),
        .outprocess_error(n64_vi_error_sources[1]),
        .first_source(n64_vi_first_error));
    km_n64_vi_line_timing n64_vi_timing(
        .clk(core_clk),.resetn(core_resetn),
        .request(n64_vi_mem_events[0]),.done(n64_vi_mem_events[1]),
        .linefetch_error(n64_vi_error_sources[0]),
        .error_state(n64_vi_error_state),.snapshot(n64_vi_timing_source));
    km_frame_config_cdc #(.WIDTH(32),.FRAME_BOUNDARY(0)) n64_vi_timing_snapshot(
        .src_clk(core_clk),.src_resetn(core_resetn),.src_data(n64_vi_timing_source),.src_busy(),
        .dst_clk(axi_clk),.dst_resetn(axi_resetn),.dst_frame(1'b0),
        .dst_data(debug_snapshot_axi[671:640]),.dst_changed());
    km_frame_config_cdc #(.WIDTH(256),.FRAME_BOUNDARY(0)) n64_ddr_snapshot(
        .src_clk(save_clk),.src_resetn(save_resetn),.src_data(n64_ddr_trace_source),.src_busy(),
        .dst_clk(axi_clk),.dst_resetn(axi_resetn),.dst_frame(1'b0),
        .dst_data(debug_snapshot_axi[639:384]),.dst_changed());
    // Layout 1: native SDRAM starts at DMA offset 128 MiB, disjoint from video.
    // Previously unused bits [25:24] of 0x34 identify the first VI error.
    assign core_debug={4'h1,2'b00,n64_vi_first_error,core_quiesce,n64_sdram_fault,
                       cart_axi_rready,cart_axi_bready,
                       n64_boot_debug,n64_debug_sticky};
    assign cartridge_ready=1'b1;
    assign cartridge_fault=n64_sdram_fault;
    assign memory_ack=n64_save_ack;
    assign host_drained=n64_sdram_drained;
    assign save_quiesce=n64_save_quiesce;
    assign save_dma_base=n64_save_base;
    assign save_dma_size=n64_save_size;
    km_n64_video_clock video_standard_clock(
        .ntsc_clk(core_video_clk),.pal_clk(n64_video_pal_clk),
        .pal(n64_pal),.video_clk(n64_video_clock));
    assign native_video_clock=n64_video_clock;
`elsif MD_CORE
    wire md_drained,md_memory_fault;
    assign cartridge_ready=1'b1,cartridge_fault=md_memory_fault;
    assign memory_ack=1'b1,host_drained=save_drained && md_drained;
    assign save_quiesce=core_quiesce,save_dma_base=core_dma_base,save_dma_size=core_dma_size;
    assign native_video_clock=core_clk;
    assign cart_axi_awaddr='0,cart_axi_awlen='0,cart_axi_awsize='0,cart_axi_awburst='0;
    assign cart_axi_awlock='0,cart_axi_awcache='0,cart_axi_awprot='0,cart_axi_awvalid='0;
    assign cart_axi_wdata='0,cart_axi_wstrb='0,cart_axi_wlast='0,cart_axi_wvalid='0,cart_axi_bready='0;
    assign cart_axi_araddr='0,cart_axi_arlen='0,cart_axi_arsize='0,cart_axi_arburst='0;
    assign cart_axi_arlock='0,cart_axi_arcache='0,cart_axi_arprot='0,cart_axi_arvalid='0,cart_axi_rready='0;
`elsif SNES_CORE
    wire snes_clock,snes_audio_reset,snes_pal,snes_drained,cart_axi_drained,cart_axi_fault;
    wire snes_memory_fault,snes_audio_overflow,snes_audio_underflow;
    wire line_valid,line_ready,line_write,cart_response_valid,response_ready,response_error;
    wire [18:0] line_address;
    wire [511:0] line_data,response_data;
    assign cartridge_fault=snes_memory_fault | cart_axi_fault | snes_audio_overflow | snes_audio_underflow;
    assign host_drained=1'b1;
    km_dma_lifecycle memory_lifecycle(.source_clk(axi_clk),.source_resetn(axi_resetn),
        .source_quiesce(quiesce),.source_base(dma_base),.source_size(dma_size),.source_drained(memory_ack),
        .destination_clk(save_clk),.destination_resetn(save_resetn),
        .destination_drained(snes_drained && cart_axi_drained && save_drained),
        .destination_quiesce(save_quiesce),.destination_base(save_dma_base),.destination_size(save_dma_size));
`elsif PSX_CORE
    wire psx_drained,psx_memory_fault,psx_axi_fault,psx_axi_drained;
    reg psx_save_quiesce;
    always @(posedge save_clk)
        if(!save_resetn) psx_save_quiesce<=0;
        else psx_save_quiesce<=save_quiesce && psx_drained;
    wire psx_ext_req,psx_ext_write,psx_ext_done;
    wire [26:0] psx_ext_addr;
    wire [31:0] psx_ext_data,psx_ext_q;
    wire [3:0] psx_ext_be;
    assign cartridge_fault=psx_memory_fault | psx_axi_fault;
    assign memory_ack=1'b1,host_drained=save_drained && psx_axi_drained && psx_drained;
    assign save_quiesce=core_quiesce,save_dma_base=core_dma_base,save_dma_size=core_dma_size;
`elsif GB_CORE
    wire gb_drained,gb_memory_fault,cart_axi_drained,cart_axi_fault;
    wire line_valid,line_ready,line_write,cart_response_valid,response_ready,response_error;
    wire [18:0] line_address;
    wire [511:0] line_data,response_data;
    assign cartridge_fault=gb_memory_fault | cart_axi_fault;
    assign native_video_clock=core_video_clk;
    assign memory_ack=1'b1,host_drained=save_drained && gb_drained && cart_axi_drained;
    assign save_quiesce=core_quiesce,save_dma_base=core_dma_base,save_dma_size=core_dma_size;
`else
`ifdef GBA_CORE
    wire gba_drained;
    assign cartridge_ready=1'b1,cartridge_fault=1'b0;
    assign memory_ack=1'b1,host_drained=save_drained && (gba_drained || save_fault);
`else
    assign memory_ack=1'b1,host_drained=save_drained;
`endif
    assign save_quiesce=core_quiesce,save_dma_base=core_dma_base,save_dma_size=core_dma_size;
    assign native_video_clock=core_video_clk;
    assign cart_axi_awaddr='0;
    assign cart_axi_awlen='0;
    assign cart_axi_awsize='0;
    assign cart_axi_awburst='0;
    assign cart_axi_awlock='0;
    assign cart_axi_awcache='0;
    assign cart_axi_awprot='0;
    assign cart_axi_awvalid='0;
    assign cart_axi_wdata='0;
    assign cart_axi_wstrb='0;
    assign cart_axi_wlast='0;
    assign cart_axi_wvalid='0;
    assign cart_axi_bready='0;
    assign cart_axi_araddr='0;
    assign cart_axi_arlen='0;
    assign cart_axi_arsize='0;
    assign cart_axi_arburst='0;
    assign cart_axi_arlock='0;
    assign cart_axi_arcache='0;
    assign cart_axi_arprot='0;
    assign cart_axi_arvalid='0;
    assign cart_axi_rready='0;
`endif
    wire command_valid,command_accept,response_valid;
    wire [1:0] command;
    wire [31:0] argument,result;
    wire [45:0] hps_bus;
    wire [7:0] native_r,native_g,native_b;
    wire native_ce,native_de,native_hs,native_vs,native_f1,freeze;
    wire [12:0] aspect_x,aspect_y,custom_ar1x,custom_ar1y,custom_ar2x,custom_ar2y;
    wire [15:0] cfg,leds,io_din,core_audio_l,core_audio_r;
    wire [4:0] volume_attenuation;
    wire [11:0] hsize,vsize,fb_width,fb_height,fb_hmin,fb_hmax,fb_vmin,fb_vmax;
    wire [13:0] fb_stride;
    wire free_scale,fb_enable,fb_changed,fb_error,io_osd,io_strobe,core_reset,user_led;
    wire [5:0] fb_format;
    wire [31:0] fb_base;
    wire osd_status,audio_signed;
    wire [1:0] audio_mix,buttons;
`ifdef MISTER_FB
    wire gba_fb_enable;
    wire [4:0] gba_fb_format;
    wire [11:0] gba_fb_width,gba_fb_height;
    wire [13:0] gba_fb_stride;
    wire [31:0] gba_fb_base;
    (* ASYNC_REG="TRUE" *) reg [1:0] gba_vblank_sync;
    always @(posedge core_clk)
        if(!core_resetn) gba_vblank_sync<=0; else gba_vblank_sync<={gba_vblank_sync[0],video_vs};
`endif
    (* ASYNC_REG="TRUE" *) reg [1:0] video_fault_sync,cartridge_ready_sync,cartridge_fault_sync,save_fault_sync;
    always @(posedge core_clk) begin
        if(!core_resetn) begin
            video_fault_sync<=0;cartridge_ready_sync<=0;cartridge_fault_sync<=0;save_fault_sync<=0;
        end else begin
            video_fault_sync<={video_fault_sync[0],video_fault};
            cartridge_ready_sync<={cartridge_ready_sync[0],cartridge_ready};
            cartridge_fault_sync<={cartridge_fault_sync[0],cartridge_fault};
            save_fault_sync<={save_fault_sync[0],save_fault};
        end
    end
    wire core_ready=cartridge_ready_sync[1] && !cartridge_fault_sync[1] &&
                    !video_fault_sync[1] && !save_fault_sync[1];
`ifndef N64_CORE
`ifndef MD_CORE
    assign core_debug=32'd0;
`endif
    assign debug_snapshot_axi=672'd0;
`endif
`ifdef N64_CORE
    km_control #(.N64_DEBUG(1)) control(
`else
    km_control control(
`endif
        .axi_clk(axi_clk),.axi_resetn(axi_resetn),
        .core_clk(core_clk),.core_resetn(core_resetn),.core_ready(core_ready),.core_debug(core_debug),
        .debug_snapshot_axi(debug_snapshot_axi),
        .core_cmd_valid(command_valid),.core_cmd(command),.core_argument(argument),
        .core_cmd_accept(command_accept),.core_rsp_valid(response_valid),.core_result(result),
        .dma_base(dma_base),.dma_size(dma_size),.quiesce(quiesce),
        .dma_drained(quiesce && video_drained && save_ack && memory_ack),
        .s_axi_awaddr(s_axi_awaddr),
        .s_axi_awvalid(s_axi_awvalid),
        .s_axi_awready(s_axi_awready),
        .s_axi_wdata(s_axi_wdata),
        .s_axi_wstrb(s_axi_wstrb),
        .s_axi_wvalid(s_axi_wvalid),
        .s_axi_wready(s_axi_wready),
        .s_axi_bresp(s_axi_bresp),
        .s_axi_bvalid(s_axi_bvalid),
        .s_axi_bready(s_axi_bready),
        .s_axi_araddr(s_axi_araddr),
        .s_axi_arvalid(s_axi_arvalid),
        .s_axi_arready(s_axi_arready),
        .s_axi_rdata(s_axi_rdata),
        .s_axi_rresp(s_axi_rresp),
        .s_axi_rvalid(s_axi_rvalid),
        .s_axi_rready(s_axi_rready)
    );
    km_dma_lifecycle lifecycle(.source_clk(axi_clk),.source_resetn(axi_resetn),
        .source_quiesce(quiesce),.source_base(dma_base),.source_size(dma_size),.source_drained(save_ack),
        .destination_clk(core_clk),.destination_resetn(core_resetn),.destination_drained(host_drained),
        .destination_quiesce(core_quiesce),.destination_base(core_dma_base),.destination_size(core_dma_size));
`ifdef N64_CORE
    km_dma_lifecycle n64_ddr_lifecycle(.source_clk(axi_clk),.source_resetn(axi_resetn),
        .source_quiesce(quiesce),.source_base(dma_base),.source_size(dma_size),.source_drained(n64_save_ack),
        .destination_clk(save_clk),.destination_resetn(save_resetn),.destination_drained(save_drained),
        .destination_quiesce(n64_save_quiesce),.destination_base(n64_save_base),.destination_size(n64_save_size));
`endif
    km_framework framework(.sys_clk(core_clk),.resetn(core_resetn),.clk_100m(axi_clk),
        .native_video_clk(native_video_clock),.native_ce(native_ce),.native_de(native_de),
        .native_hs(native_hs),.native_vs(native_vs),.native_f1(native_f1),.output_vs(video_vs),
        .aspect_x(aspect_x),.aspect_y(aspect_y),.buttons(buttons),
        .cmd_valid(command_valid),.cmd(command),.argument(argument),.cmd_accept(command_accept),
        .rsp_valid(response_valid),.result(result),.HPS_BUS(hps_bus),
        .io_osd(io_osd),.io_strobe(io_strobe),.io_din(io_din),.core_reset(core_reset),.user_led(user_led),
        .cfg(cfg),.leds(leds),.volume_attenuation(volume_attenuation),
        .hsize(hsize),.vsize(vsize),.free_scale(free_scale),
        .custom_ar1x(custom_ar1x),.custom_ar1y(custom_ar1y),.custom_ar2x(custom_ar2x),.custom_ar2y(custom_ar2y),
        .fb_enable(fb_enable),.fb_format(fb_format),.fb_base(fb_base),.fb_width(fb_width),.fb_height(fb_height),
        .fb_hmin(fb_hmin),.fb_hmax(fb_hmax),.fb_vmin(fb_vmin),.fb_vmax(fb_vmax),
        .fb_stride(fb_stride),.fb_changed(fb_changed),.fb_error(fb_error));
`ifdef MENU_CORE
    assign cartridge_ready=1'b1,cartridge_fault=1'b0;
`endif
`ifdef PSX_CORE
    wire psx_bob,psx_blackout;
`endif
    emu core(
`ifdef MENU_CORE
        .km_clk_sys(core_clk),.km_clk_video(core_video_clk),
`elsif MD_CORE
        .km_clk_sys(core_clk),.km_app_reset(!core_resetn),.km_quiesce(core_quiesce),
        .km_dma_fault(save_fault),.km_dma_drained(save_drained),
        .km_memory_drained(md_drained),.km_memory_fault(md_memory_fault),
        .km_video_debug(core_debug),
`elsif N64_CORE
        .km_clk_1x(core_clk),.km_clk_93(n64_clk93),.km_clk_2x(save_clk),
        .km_clk_video(native_video_clock),.km_clock_locked(core_resetn),.km_pal(n64_pal),
        .km_boot_debug(n64_boot_debug),
        .km_native_debug(n64_native_debug),.km_native_errors(n64_native_errors),
        .km_vi_error_sources(n64_vi_error_sources),
        .km_vi_mem_events(n64_vi_mem_events),
        .km_vi_error_state(n64_vi_error_state),
        .km_sdram_ch1_req(n64_ch1_req),.km_sdram_ch1_rnw(n64_ch1_rnw),
        .km_sdram_ch1_addr(n64_ch1_addr),.km_sdram_ch1_din(n64_ch1_din),
        .km_sdram_ch1_be(n64_ch1_be),.km_sdram_ch1_dout(n64_ch1_dout),
        .km_sdram_ch1_ready(n64_ch1_ready),.km_sdram_ch1_reqprocessed(n64_ch1_reqprocessed),
        .km_sdram_ch2_req(n64_ch2_req),.km_sdram_ch2_addr(n64_ch2_addr),
        .km_sdram_ch2_din(n64_ch2_din),.km_sdram_ch2_ready(n64_ch2_ready),
`elsif PSX_CORE
        .HDMI_BOB_DEINT(psx_bob),.HDMI_BLACKOUT(psx_blackout),
        .km_clk_core(core_clk),.km_clk_save(save_clk),.km_clk_mem(core_mem_clk),
        .km_app_reset(!core_resetn),.km_quiesce(core_quiesce),.km_dma_fault(save_fault),
        .km_memory_ready(cartridge_ready),.km_memory_fault(psx_memory_fault),.km_memory_drained(psx_drained),
        .km_ext_req(psx_ext_req),.km_ext_addr(psx_ext_addr),.km_ext_write(psx_ext_write),
        .km_ext_data(psx_ext_data),.km_ext_be(psx_ext_be),.km_ext_done(psx_ext_done),
        .km_ext_q(psx_ext_q),.km_ext_fault(psx_axi_fault),.CLK_VIDEO(native_video_clock),
        .FB_EN(gba_fb_enable),.FB_FORMAT(gba_fb_format),.FB_WIDTH(gba_fb_width),.FB_HEIGHT(gba_fb_height),
        .FB_BASE(gba_fb_base),.FB_STRIDE(gba_fb_stride),.FB_VBL(gba_vblank_sync[1]),.FB_LL(1'b0),
`elsif GBA_CORE
        .km_clk_sys(core_clk),.km_clk_video(core_video_clk),.km_app_reset(!core_resetn),
        .km_quiesce(core_quiesce),.km_dma_fault(save_fault),.km_memory_drained(gba_drained),
        .FB_EN(gba_fb_enable),.FB_FORMAT(gba_fb_format),.FB_WIDTH(gba_fb_width),.FB_HEIGHT(gba_fb_height),
        .FB_BASE(gba_fb_base),.FB_STRIDE(gba_fb_stride),.FB_VBL(gba_vblank_sync[1]),.FB_LL(1'b0),
`elsif GB_CORE
        .km_clk_core(core_clk),.km_clk_video(core_video_clk),.km_app_reset(!core_resetn),.km_quiesce(core_quiesce),
        .km_memory_ready(cartridge_ready),.km_memory_fault(gb_memory_fault),.km_memory_drained(gb_drained),
        .km_line_valid(line_valid),.km_line_ready(line_ready),.km_line_write(line_write),
        .km_line_address(line_address),.km_line_data(line_data),
        .km_response_valid(cart_response_valid),.km_response_ready(response_ready),
        .km_response_data(response_data),.km_response_error(response_error),
`elsif SNES_CORE
        .km_clk_mem(core_mem_clk),.km_clk_host(core_clk),.km_clk_core(snes_clock),
        .km_app_reset(!save_resetn),.km_quiesce(save_quiesce),
        .km_audio_reset(snes_audio_reset),.km_pal(snes_pal),.CLK_VIDEO(native_video_clock),
        .km_memory_ready(cartridge_ready),.km_memory_fault(snes_memory_fault),.km_memory_drained(snes_drained),
        .km_line_valid(line_valid),.km_line_ready(line_ready),.km_line_write(line_write),
        .km_line_address(line_address),.km_line_data(line_data),
        .km_response_valid(cart_response_valid),.km_response_ready(response_ready),
        .km_response_data(response_data),.km_response_error(response_error),
`else
        .km_clk_mem(core_mem_clk),.km_clk_core(core_clk),.km_clk_video(core_video_clk),
        .km_clock_locked(core_resetn),.km_app_reset(!core_resetn),
        .km_memory_ready(cartridge_ready),.km_memory_fault(cartridge_fault),
`endif
        .CLK_50M(axi_clk),.CLK_AUDIO(audio_clk),
`ifdef PSX_CORE
        .RESET(!core_resetn || core_reset),
`elsif GBA_CORE
        // Pause admission while outstanding GBA CPU/DMA work drains. Resetting
        // a client before its posted request completes can change its payload.
        .RESET(!core_resetn || core_reset),
`else
        .RESET(!core_resetn || core_reset || core_quiesce),
`endif
        .HPS_BUS(hps_bus),.CE_PIXEL(native_ce),.VGA_R(native_r),.VGA_G(native_g),.VGA_B(native_b),
        .VGA_HS(native_hs),.VGA_VS(native_vs),.VGA_DE(native_de),.VGA_F1(native_f1),
        .VIDEO_ARX(aspect_x),.VIDEO_ARY(aspect_y),.HDMI_FREEZE(freeze),
        .HDMI_WIDTH(12'd1920),.HDMI_HEIGHT(12'd1080),.OSD_STATUS(osd_status),
        .AUDIO_L(core_audio_l),.AUDIO_R(core_audio_r),.AUDIO_S(audio_signed),.AUDIO_MIX(audio_mix),
        .SD_MISO(1'b1),.SD_CD(1'b1),.UART_CTS(1'b0),.UART_DSR(1'b0),
        .BUTTONS(buttons),.USER_IN(7'h7f),.UART_RXD(1'b1),
        .DDRAM_ADDR(ddram_addr),.DDRAM_BURSTCNT(ddram_burstcnt),.DDRAM_DIN(ddram_din),.DDRAM_BE(ddram_be),
        .DDRAM_RD(ddram_rd),.DDRAM_WE(ddram_we),.DDRAM_BUSY(ddram_busy),
        .DDRAM_DOUT(ddram_dout),.DDRAM_DOUT_READY(ddram_dout_ready));
`ifdef MD_CORE
    km_md_ddram_axi saves(.clk(save_clk),.resetn(save_resetn),.quiesce(save_quiesce && md_drained),
`elsif SNES_CORE
    // Keep accepting already-issued upstream MSU/save operations until its
    // request toggles and command mailboxes have also drained.
    km_snes_ddram_axi saves(.clk(save_clk),.resetn(save_resetn),.quiesce(save_quiesce && snes_drained),
`elsif PSX_CORE
    km_psx_ddram_axi saves(.clk(save_clk),.resetn(save_resetn),.quiesce(psx_save_quiesce),
`elsif GBA_CORE
    km_gba_ddram_axi saves(.clk(save_clk),.resetn(save_resetn),.quiesce(save_quiesce && gba_drained),
`elsif N64_CORE
    km_n64_ddram_axi saves(.clk(save_clk),.resetn(save_resetn),.quiesce(save_quiesce),
`else
    km_ddram_axi saves(.clk(save_clk),.resetn(save_resetn),.quiesce(save_quiesce),
`endif
        .memory_base(save_dma_base),.memory_size(save_dma_size),.drained(save_drained),.fault(save_fault),
        .ddram_addr(ddram_addr),.ddram_burstcnt(ddram_burstcnt),.ddram_din(ddram_din),.ddram_be(ddram_be),
        .ddram_rd(ddram_rd),.ddram_we(ddram_we),.ddram_busy(ddram_busy),
        .ddram_dout(ddram_dout),.ddram_dout_ready(ddram_dout_ready),
        .m_axi_awaddr(save_axi_awaddr),
        .m_axi_awlen(save_axi_awlen),
        .m_axi_awsize(save_axi_awsize),
        .m_axi_awburst(save_axi_awburst),
        .m_axi_awlock(save_axi_awlock),
        .m_axi_awcache(save_axi_awcache),
        .m_axi_awprot(save_axi_awprot),
        .m_axi_awvalid(save_axi_awvalid),
        .m_axi_awready(save_axi_awready),
        .m_axi_wdata(save_axi_wdata),
        .m_axi_wstrb(save_axi_wstrb),
        .m_axi_wlast(save_axi_wlast),
        .m_axi_wvalid(save_axi_wvalid),
        .m_axi_wready(save_axi_wready),
        .m_axi_bresp(save_axi_bresp),
        .m_axi_bvalid(save_axi_bvalid),
        .m_axi_bready(save_axi_bready),
        .m_axi_araddr(save_axi_araddr),
        .m_axi_arlen(save_axi_arlen),
        .m_axi_arsize(save_axi_arsize),
        .m_axi_arburst(save_axi_arburst),
        .m_axi_arlock(save_axi_arlock),
        .m_axi_arcache(save_axi_arcache),
        .m_axi_arprot(save_axi_arprot),
        .m_axi_arvalid(save_axi_arvalid),
        .m_axi_arready(save_axi_arready),
        .m_axi_rdata(save_axi_rdata),
        .m_axi_rresp(save_axi_rresp),
        .m_axi_rlast(save_axi_rlast),
        .m_axi_rvalid(save_axi_rvalid),
        .m_axi_rready(save_axi_rready)
    );
`ifdef PSX_CORE
    km_psx_main_axi main_dma(.clk(core_mem_clk),.resetn(core_resetn),
        .memory_base(core_dma_base),.memory_size(core_dma_size),
        .ext_req(psx_ext_req),.ext_addr(psx_ext_addr),.ext_write(psx_ext_write),
        .ext_data(psx_ext_data),.ext_be(psx_ext_be),.ext_done(psx_ext_done),
        .ext_q(psx_ext_q),.ext_fault(psx_axi_fault),.drained(psx_axi_drained),
        .m_axi_awaddr(cart_axi_awaddr),
        .m_axi_awlen(cart_axi_awlen),
        .m_axi_awsize(cart_axi_awsize),
        .m_axi_awburst(cart_axi_awburst),
        .m_axi_awlock(cart_axi_awlock),
        .m_axi_awcache(cart_axi_awcache),
        .m_axi_awprot(cart_axi_awprot),
        .m_axi_awvalid(cart_axi_awvalid),
        .m_axi_awready(cart_axi_awready),
        .m_axi_wdata(cart_axi_wdata),
        .m_axi_wstrb(cart_axi_wstrb),
        .m_axi_wlast(cart_axi_wlast),
        .m_axi_wvalid(cart_axi_wvalid),
        .m_axi_wready(cart_axi_wready),
        .m_axi_bresp(cart_axi_bresp),
        .m_axi_bvalid(cart_axi_bvalid),
        .m_axi_bready(cart_axi_bready),
        .m_axi_araddr(cart_axi_araddr),
        .m_axi_arlen(cart_axi_arlen),
        .m_axi_arsize(cart_axi_arsize),
        .m_axi_arburst(cart_axi_arburst),
        .m_axi_arlock(cart_axi_arlock),
        .m_axi_arcache(cart_axi_arcache),
        .m_axi_arprot(cart_axi_arprot),
        .m_axi_arvalid(cart_axi_arvalid),
        .m_axi_arready(cart_axi_arready),
        .m_axi_rdata(cart_axi_rdata),
        .m_axi_rresp(cart_axi_rresp),
        .m_axi_rlast(cart_axi_rlast),
        .m_axi_rvalid(cart_axi_rvalid),
        .m_axi_rready(cart_axi_rready));
`elsif N64_CORE
    km_n64_sdram_axi low_latency_memory(.clk(core_clk),.resetn(core_resetn),
        .quiesce(core_quiesce),.memory_base(core_dma_base),.memory_size(core_dma_size),
        .drained(n64_sdram_drained),.fault(n64_sdram_fault),
        .ch1_addr(n64_ch1_addr),.ch1_din(n64_ch1_din),.ch1_dout(n64_ch1_dout),
        .ch1_req(n64_ch1_req),.ch1_rnw(n64_ch1_rnw),.ch1_be(n64_ch1_be),
        .ch1_ready(n64_ch1_ready),.ch1_reqprocessed(n64_ch1_reqprocessed),
        .ch2_addr(n64_ch2_addr),.ch2_din(n64_ch2_din),.ch2_req(n64_ch2_req),
        .ch2_ready(n64_ch2_ready),
        .m_axi_awaddr(cart_axi_awaddr),
        .m_axi_awlen(cart_axi_awlen),
        .m_axi_awsize(cart_axi_awsize),
        .m_axi_awburst(cart_axi_awburst),
        .m_axi_awlock(cart_axi_awlock),
        .m_axi_awcache(cart_axi_awcache),
        .m_axi_awprot(cart_axi_awprot),
        .m_axi_awvalid(cart_axi_awvalid),
        .m_axi_awready(cart_axi_awready),
        .m_axi_wdata(cart_axi_wdata),
        .m_axi_wstrb(cart_axi_wstrb),
        .m_axi_wlast(cart_axi_wlast),
        .m_axi_wvalid(cart_axi_wvalid),
        .m_axi_wready(cart_axi_wready),
        .m_axi_bresp(cart_axi_bresp),
        .m_axi_bvalid(cart_axi_bvalid),
        .m_axi_bready(cart_axi_bready),
        .m_axi_araddr(cart_axi_araddr),
        .m_axi_arlen(cart_axi_arlen),
        .m_axi_arsize(cart_axi_arsize),
        .m_axi_arburst(cart_axi_arburst),
        .m_axi_arlock(cart_axi_arlock),
        .m_axi_arcache(cart_axi_arcache),
        .m_axi_arprot(cart_axi_arprot),
        .m_axi_arvalid(cart_axi_arvalid),
        .m_axi_arready(cart_axi_arready),
        .m_axi_rdata(cart_axi_rdata),
        .m_axi_rresp(cart_axi_rresp),
        .m_axi_rlast(cart_axi_rlast),
        .m_axi_rvalid(cart_axi_rvalid),
        .m_axi_rready(cart_axi_rready));
`endif
`ifdef GB_CORE
`define KM_CART_AXI
`endif
`ifdef SNES_CORE
`define KM_CART_AXI
`endif
`ifdef KM_CART_AXI
    km_snes_cart_line_axi #(.ADDRESS_BITS(25)) cartridge_dma(.clk(save_clk),.resetn(save_resetn),
        .memory_base(save_dma_base),.memory_size(save_dma_size),.drained(cart_axi_drained),.fault(cart_axi_fault),
        .line_valid(line_valid),.line_ready(line_ready),.line_write(line_write),
        .line_address(line_address),.line_data(line_data),.response_valid(cart_response_valid),
        .response_ready(response_ready),.response_data(response_data),.response_error(response_error),
        .m_axi_awaddr(cart_axi_awaddr),
        .m_axi_awlen(cart_axi_awlen),
        .m_axi_awsize(cart_axi_awsize),
        .m_axi_awburst(cart_axi_awburst),
        .m_axi_awlock(cart_axi_awlock),
        .m_axi_awcache(cart_axi_awcache),
        .m_axi_awprot(cart_axi_awprot),
        .m_axi_awvalid(cart_axi_awvalid),
        .m_axi_awready(cart_axi_awready),
        .m_axi_wdata(cart_axi_wdata),
        .m_axi_wstrb(cart_axi_wstrb),
        .m_axi_wlast(cart_axi_wlast),
        .m_axi_wvalid(cart_axi_wvalid),
        .m_axi_wready(cart_axi_wready),
        .m_axi_bresp(cart_axi_bresp),
        .m_axi_bvalid(cart_axi_bvalid),
        .m_axi_bready(cart_axi_bready),
        .m_axi_araddr(cart_axi_araddr),
        .m_axi_arlen(cart_axi_arlen),
        .m_axi_arsize(cart_axi_arsize),
        .m_axi_arburst(cart_axi_arburst),
        .m_axi_arlock(cart_axi_arlock),
        .m_axi_arcache(cart_axi_arcache),
        .m_axi_arprot(cart_axi_arprot),
        .m_axi_arvalid(cart_axi_arvalid),
        .m_axi_arready(cart_axi_arready),
        .m_axi_rdata(cart_axi_rdata),
        .m_axi_rresp(cart_axi_rresp),
        .m_axi_rlast(cart_axi_rlast),
        .m_axi_rvalid(cart_axi_rvalid),
        .m_axi_rready(cart_axi_rready)
    );
`undef KM_CART_AXI
`endif
    km_video video(
`ifdef PSX_CORE
        .core_bob(psx_bob),.core_blackout(psx_blackout),
`endif
        .sys_clk(core_clk),.input_clk(native_video_clock),.output_clk(video_clk),.memory_clk(axi_clk),
`ifdef MISTER_FB
        .core_fb_enable(gba_fb_enable),.core_fb_format({1'b0,gba_fb_format}),.core_fb_base(gba_fb_base),
        .core_fb_width(gba_fb_width),.core_fb_height(gba_fb_height),.core_fb_stride(gba_fb_stride),
`endif
        .sys_resetn(core_resetn),.output_resetn(video_resetn),.memory_resetn(axi_resetn),
        .scaler_resetn(core_resetn && !core_quiesce && video_resetn),
        .input_r(native_r),.input_g(native_g),.input_b(native_b),.input_hs(native_hs),.input_vs(native_vs),
        .input_de(native_de),.input_ce(native_ce),.freeze(freeze),
        .input_field(native_f1),
        .io_osd(io_osd),.io_strobe(io_strobe),.io_din(io_din),
        .aspect_x(aspect_x),.aspect_y(aspect_y),.custom_ar1x(custom_ar1x),.custom_ar1y(custom_ar1y),
        .custom_ar2x(custom_ar2x),.custom_ar2y(custom_ar2y),.hsize(hsize),.vsize(vsize),.free_scale(free_scale),
        .fb_enable(fb_enable),.fb_format(fb_format),.fb_base(fb_base),.fb_width(fb_width),.fb_height(fb_height),
        .fb_hmin(fb_hmin),.fb_hmax(fb_hmax),.fb_vmin(fb_vmin),.fb_vmax(fb_vmax),.fb_stride(fb_stride),
        .output_r(video_r),.output_g(video_g),.output_b(video_b),
        .output_hs(video_hs),.output_vs(video_vs),.output_de(video_de),.osd_status(osd_status),
        .detected_width(),.detected_height(),.quiesce(quiesce),.memory_base(dma_base),.memory_size(dma_size),
        .drained(video_drained),.fault(video_fault),
        .m_axi_awaddr(video_axi_awaddr),
        .m_axi_awlen(video_axi_awlen),
        .m_axi_awsize(video_axi_awsize),
        .m_axi_awburst(video_axi_awburst),
        .m_axi_awlock(video_axi_awlock),
        .m_axi_awcache(video_axi_awcache),
        .m_axi_awprot(video_axi_awprot),
        .m_axi_awvalid(video_axi_awvalid),
        .m_axi_awready(video_axi_awready),
        .m_axi_wdata(video_axi_wdata),
        .m_axi_wstrb(video_axi_wstrb),
        .m_axi_wlast(video_axi_wlast),
        .m_axi_wvalid(video_axi_wvalid),
        .m_axi_wready(video_axi_wready),
        .m_axi_bresp(video_axi_bresp),
        .m_axi_bvalid(video_axi_bvalid),
        .m_axi_bready(video_axi_bready),
        .m_axi_araddr(video_axi_araddr),
        .m_axi_arlen(video_axi_arlen),
        .m_axi_arsize(video_axi_arsize),
        .m_axi_arburst(video_axi_arburst),
        .m_axi_arlock(video_axi_arlock),
        .m_axi_arcache(video_axi_arcache),
        .m_axi_arprot(video_axi_arprot),
        .m_axi_arvalid(video_axi_arvalid),
        .m_axi_arready(video_axi_arready),
        .m_axi_rdata(video_axi_rdata),
        .m_axi_rresp(video_axi_rresp),
        .m_axi_rlast(video_axi_rlast),
        .m_axi_rvalid(video_axi_rvalid),
        .m_axi_rready(video_axi_rready)
    );
`ifdef SNES_CORE
    // Common stream reset clears both FIFO pointers even if the console clock
    // is stopped. Each receiving domain releases its own reset synchronously.
    wire stream_reset=snes_audio_reset || !audio_resetn || !save_resetn;
    (* ASYNC_REG="TRUE" *) reg [1:0] source_audio_reset_sync,sink_audio_reset_sync;
    always @(posedge snes_clock or posedge stream_reset)
        if(stream_reset) source_audio_reset_sync<=0; else source_audio_reset_sync<={source_audio_reset_sync[0],1'b1};
    always @(posedge audio_clk or posedge stream_reset)
        if(stream_reset) sink_audio_reset_sync<=0; else sink_audio_reset_sync<={sink_audio_reset_sync[0],1'b1};
    wire [39:0] queued_audio;
    km_snes_audio_queue audio_queue(.source_clk(snes_clock),.source_resetn(source_audio_reset_sync[1]),.pal(snes_pal),
        .source_sample({audio_signed,audio_mix,volume_attenuation,core_audio_l,core_audio_r}),.overflow(snes_audio_overflow),
        .audio_clk(audio_clk),.audio_resetn(sink_audio_reset_sync[1]),.audio_sample(queued_audio),
        .sample_valid(),.underflow(snes_audio_underflow),.playing(),.occupancy());
    km_audio #(.DIRECT_AUDIO_CLOCK(1)) audio(.core_clk(audio_clk),.core_resetn(audio_resetn),
        .audio_clk(audio_clk),.audio_resetn(audio_resetn),.core_l(queued_audio[31:16]),.core_r(queued_audio[15:0]),
        .is_signed(queued_audio[39]),.mix(queued_audio[38:37]),.attenuation(queued_audio[36:32]),
`else
`ifdef N64_CORE
    // N64 AI samples are produced by clkvid, not clk1x. Start the coherent
    // audio mailbox in that same domain so its payload is never sampled by
    // unrelated core-clock logic before the explicit handshake.
    (* ASYNC_REG="TRUE" *) reg [1:0] n64_audio_reset_sync;
    (* ASYNC_REG="TRUE" *) reg [1:0] n64_audio_quiesce_sync;
    always @(posedge native_video_clock or negedge core_resetn)
        if(!core_resetn) begin
            n64_audio_reset_sync<=0;
            n64_audio_quiesce_sync<=2'b11;
        end else begin
            n64_audio_reset_sync<={n64_audio_reset_sync[0],1'b1};
            n64_audio_quiesce_sync<={n64_audio_quiesce_sync[0],core_quiesce};
        end
    wire audio_source_clk=native_video_clock;
    wire audio_source_resetn=n64_audio_reset_sync[1];
    wire audio_source_quiesce=n64_audio_quiesce_sync[1];
    wire [7:0] n64_audio_controls_video;
    km_frame_config_cdc #(.WIDTH(8),.FRAME_BOUNDARY(0),.RESET_VALUE(8'hff))
        n64_audio_controls(
            .src_clk(core_clk),.src_resetn(core_resetn),
            .src_data({audio_signed,audio_mix,volume_attenuation}),.src_busy(),
            .dst_clk(native_video_clock),.dst_resetn(audio_source_resetn),
            .dst_frame(1'b0),.dst_data(n64_audio_controls_video),.dst_changed());
    wire audio_source_signed=n64_audio_controls_video[7];
    wire [1:0] audio_source_mix=n64_audio_controls_video[6:5];
    wire [4:0] audio_source_attenuation=n64_audio_controls_video[4:0];
`else
    wire audio_source_clk=core_clk;
    wire audio_source_resetn=core_resetn;
    wire audio_source_quiesce=core_quiesce;
    wire audio_source_signed=audio_signed;
    wire [1:0] audio_source_mix=audio_mix;
    wire [4:0] audio_source_attenuation=volume_attenuation;
`endif
    km_audio audio(.core_clk(audio_source_clk),.core_resetn(audio_source_resetn),
        .audio_clk(audio_clk),.audio_resetn(audio_resetn),.core_l(audio_source_quiesce ? 16'd0 : core_audio_l),.core_r(audio_source_quiesce ? 16'd0 : core_audio_r),
        .is_signed(audio_source_signed),.mix(audio_source_mix),.attenuation(audio_source_attenuation),
`endif
        .m_axis_tdata(audio_axis_tdata),.m_axis_tid(audio_axis_tid),
        .m_axis_tvalid(audio_axis_tvalid),.m_axis_tready(audio_axis_tready));
endmodule
