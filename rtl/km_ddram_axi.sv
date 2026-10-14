// SPDX-License-Identifier: GPL-3.0-or-later
// NES save-state DDRAM adapter. The pinned NES issues one 64-bit beat per
// request. Unsupported burst sizes fault rather than silently truncating.
// All ports share clk. A board-level AXI clock converter crosses to PS HP.
// memory_base/size may change only while quiesced and drained.
module km_ddram_axi (
    input wire clk, input wire resetn, input wire quiesce,
    input wire [39:0] memory_base, input wire [31:0] memory_size,
    output wire drained, output reg fault,
    input wire [28:0] ddram_addr, input wire [7:0] ddram_burstcnt,
    input wire [63:0] ddram_din, input wire [7:0] ddram_be,
    input wire ddram_rd, input wire ddram_we,
    output wire ddram_busy, output reg [63:0] ddram_dout,
    output reg ddram_dout_ready,
    output reg [39:0] m_axi_awaddr, output wire [7:0] m_axi_awlen,
    output wire [2:0] m_axi_awsize, output wire [1:0] m_axi_awburst,
    output wire m_axi_awlock, output wire [3:0] m_axi_awcache,
    output wire [2:0] m_axi_awprot, output reg m_axi_awvalid,
    input wire m_axi_awready,
    output reg [63:0] m_axi_wdata, output reg [7:0] m_axi_wstrb,
    output wire m_axi_wlast, output reg m_axi_wvalid, input wire m_axi_wready,
    input wire [1:0] m_axi_bresp, input wire m_axi_bvalid, output wire m_axi_bready,
    output reg [39:0] m_axi_araddr, output wire [7:0] m_axi_arlen,
    output wire [2:0] m_axi_arsize, output wire [1:0] m_axi_arburst,
    output wire m_axi_arlock, output wire [3:0] m_axi_arcache,
    output wire [2:0] m_axi_arprot, output reg m_axi_arvalid,
    input wire m_axi_arready,
    input wire [63:0] m_axi_rdata, input wire [1:0] m_axi_rresp,
    input wire m_axi_rlast, input wire m_axi_rvalid, output wire m_axi_rready
);
    localparam IDLE=0, WRITE=1, READ=2;
    reg [1:0] state;
    wire [31:0] logical_address = {ddram_addr, 3'b000};
    wire [32:0] offset = {1'b0,logical_address} - 33'h020000000;
    wire [40:0] translated = {1'b0,memory_base} + {8'd0,offset};
    wire address_ok = logical_address >= 32'h20000000 &&
                      logical_address < 32'h40000000 &&
                      offset + 33'd8 <= {1'b0,memory_size} &&
                      translated + 41'd7 < 41'h10000000000;
    assign ddram_busy = !resetn || quiesce || fault || state != IDLE;
    assign drained = state == IDLE && !m_axi_awvalid && !m_axi_wvalid && !m_axi_arvalid;
    assign m_axi_awlen=0, m_axi_arlen=0;
    assign m_axi_awsize=3, m_axi_arsize=3;
    assign m_axi_awburst=1, m_axi_arburst=1;
    assign m_axi_awlock=0, m_axi_arlock=0;
    // Noncacheable PS HP transactions match the kernel coherent allocation.
    assign m_axi_awcache=0, m_axi_arcache=0;
    assign m_axi_awprot=0, m_axi_arprot=0;
    assign m_axi_wlast=1;
    assign m_axi_bready=state == WRITE && !m_axi_awvalid && !m_axi_wvalid;
    assign m_axi_rready=state == READ && !m_axi_arvalid;

    always @(posedge clk) begin
        if (!resetn) begin
            state<=IDLE; fault<=0; ddram_dout<=0; ddram_dout_ready<=0;
            m_axi_awaddr<=0; m_axi_awvalid<=0; m_axi_wdata<=0;
            m_axi_wstrb<=0; m_axi_wvalid<=0; m_axi_araddr<=0; m_axi_arvalid<=0;
        end else begin
            ddram_dout_ready<=0;
            if (m_axi_awvalid && m_axi_awready) m_axi_awvalid<=0;
            if (m_axi_wvalid && m_axi_wready) m_axi_wvalid<=0;
            if (m_axi_arvalid && m_axi_arready) m_axi_arvalid<=0;
            if (m_axi_bvalid && m_axi_bready) begin
                if (m_axi_bresp != 0) fault<=1;
                state<=IDLE;
            end
            if (m_axi_rvalid && m_axi_rready) begin
                if (m_axi_rresp != 0 || !m_axi_rlast) fault<=1;
                // RLAST determines drain completion even on a malformed slave.
                if (m_axi_rlast) begin
                    state<=IDLE;
                    if (m_axi_rresp == 0 && !fault) begin
                        ddram_dout<=m_axi_rdata;
                        ddram_dout_ready<=1;
                    end
                end
            end
            if (!ddram_busy && (ddram_rd || ddram_we)) begin
                if (!address_ok || ddram_burstcnt != 1 || (ddram_rd && ddram_we)) fault<=1;
                else if (ddram_we) begin
                    m_axi_awaddr<=translated[39:0]; m_axi_awvalid<=1;
                    m_axi_wdata<=ddram_din; m_axi_wstrb<=ddram_be; m_axi_wvalid<=1;
                    state<=WRITE;
                end else begin
                    m_axi_araddr<=translated[39:0]; m_axi_arvalid<=1;
                    state<=READ;
                end
            end
        end
    end
endmodule
