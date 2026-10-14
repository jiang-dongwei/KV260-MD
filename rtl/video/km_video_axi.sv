// SPDX-License-Identifier: GPL-3.0-or-later
// Bounded Avalon 128-bit burst adapter for ascal, with independent AXI AW/W.
// One transaction at a time, bursts 1..16 words; split at AXI 4 KiB boundaries.
// Complete write bursts are buffered before issuing any AXI address. Quiesce
// may discard an incomplete buffered video write, but never an AXI transfer.
module km_video_axi (
    input wire clk, resetn, quiesce,
    input wire [39:0] memory_base, input wire [31:0] memory_size,
    output wire drained, output reg fault,
    input wire [27:0] avl_address, input wire [7:0] avl_burstcount,
    input wire [127:0] avl_writedata, input wire [15:0] avl_byteenable,
    input wire avl_write, avl_read, output wire avl_waitrequest,
    output reg [127:0] avl_readdata, output reg avl_readdatavalid,
    output reg [39:0] m_axi_awaddr, output wire [7:0] m_axi_awlen,
    output wire [2:0] m_axi_awsize, output wire [1:0] m_axi_awburst,
    output wire m_axi_awlock, output wire [3:0] m_axi_awcache,
    output wire [2:0] m_axi_awprot, output reg m_axi_awvalid, input wire m_axi_awready,
    output wire [127:0] m_axi_wdata, output wire [15:0] m_axi_wstrb,
    output wire m_axi_wlast, output reg m_axi_wvalid, input wire m_axi_wready,
    input wire [1:0] m_axi_bresp, input wire m_axi_bvalid, output wire m_axi_bready,
    output reg [39:0] m_axi_araddr, output wire [7:0] m_axi_arlen,
    output wire [2:0] m_axi_arsize, output wire [1:0] m_axi_arburst,
    output wire m_axi_arlock, output wire [3:0] m_axi_arcache,
    output wire [2:0] m_axi_arprot, output reg m_axi_arvalid, input wire m_axi_arready,
    input wire [127:0] m_axi_rdata, input wire [1:0] m_axi_rresp,
    input wire m_axi_rlast, m_axi_rvalid, output wire m_axi_rready
);
    localparam IDLE=0, COLLECT=1, WRITE=2, READ=3;
    reg [1:0] state;
    reg [127:0] write_buffer [0:15];
    reg [15:0] strobe_buffer [0:15];
    reg [4:0] collected, remaining, segment_len, segment_sent;
    reg [3:0] write_index;
    wire [31:0] logical_address={avl_address,4'b0000};
    wire [32:0] byte_count={21'd0,avl_burstcount,4'b0000};
    wire [32:0] offset={1'b0,logical_address}-33'h020000000;
    wire [40:0] translated={1'b0,memory_base}+{8'd0,offset};
    wire address_ok=logical_address>=32'h20000000 &&
        {1'b0,logical_address}+byte_count<=33'h040000000 &&
        offset+byte_count<={1'b0,memory_size} &&
        translated+{8'd0,byte_count}<=41'h10000000000;
    wire write_ok={1'b0,logical_address}+byte_count<=33'h021800000;
    function automatic [4:0] segment(input [39:0] address,input [4:0] count);
        reg [8:0] page_words;
        begin
            page_words=9'd256-{1'b0,address[11:4]};
            segment=page_words < {4'd0,count} ? page_words[4:0] : count;
        end
    endfunction
    wire [4:0] next_remaining=remaining-segment_len;
    wire [39:0] next_write_address=m_axi_awaddr+{31'd0,segment_len,4'b0000};
    wire [39:0] next_read_address=m_axi_araddr+{31'd0,segment_len,4'b0000};
    assign avl_waitrequest=!resetn || quiesce || fault || (state!=IDLE && state!=COLLECT);
    assign drained=state==IDLE && !m_axi_awvalid && !m_axi_wvalid && !m_axi_arvalid;
    assign m_axi_awlen={3'd0,segment_len}-8'd1;
    assign m_axi_arlen={3'd0,segment_len}-8'd1;
    assign m_axi_awsize=4, m_axi_arsize=4;
    assign m_axi_awburst=1, m_axi_arburst=1;
    assign m_axi_awlock=0, m_axi_arlock=0;
    assign m_axi_awcache=0, m_axi_arcache=0;
    assign m_axi_awprot=0, m_axi_arprot=0;
    assign m_axi_wdata=write_buffer[write_index];
    assign m_axi_wstrb=strobe_buffer[write_index];
    assign m_axi_wlast=segment_sent+1'b1==segment_len;
    assign m_axi_bready=state==WRITE && !m_axi_awvalid && !m_axi_wvalid;
    assign m_axi_rready=state==READ && !m_axi_arvalid;
    always @(posedge clk) begin
        if(!resetn) begin
            state<=IDLE; fault<=0; avl_readdata<=0; avl_readdatavalid<=0;
            collected<=0; remaining<=0; segment_len<=1; segment_sent<=0; write_index<=0;
            m_axi_awaddr<=0; m_axi_araddr<=0; m_axi_awvalid<=0; m_axi_arvalid<=0; m_axi_wvalid<=0;
        end else begin
            avl_readdatavalid<=0;
            if(m_axi_awvalid && m_axi_awready) m_axi_awvalid<=0;
            if(m_axi_arvalid && m_axi_arready) m_axi_arvalid<=0;
            if(m_axi_wvalid && m_axi_wready) begin
                write_index<=write_index+1'b1;
                segment_sent<=segment_sent+1'b1;
                if(m_axi_wlast) m_axi_wvalid<=0;
            end
            if(m_axi_bvalid && m_axi_bready) begin
                if(m_axi_bresp!=0) begin fault<=1; state<=IDLE; end
                else if(next_remaining!=0) begin
                    remaining<=next_remaining; segment_len<=segment(next_write_address,next_remaining);
                    segment_sent<=0; m_axi_awaddr<=next_write_address;
                    m_axi_awvalid<=1; m_axi_wvalid<=1;
                end else state<=IDLE;
            end
            if(m_axi_rvalid && m_axi_rready) begin
                avl_readdatavalid<=1;
                avl_readdata<=m_axi_rresp==0 ? m_axi_rdata : 128'd0;
                segment_sent<=segment_sent+1'b1;
                if(m_axi_rresp!=0 || m_axi_rlast!=(segment_sent+1'b1==segment_len)) fault<=1;
                if(m_axi_rlast) begin
                    if(next_remaining!=0 && !fault && m_axi_rresp==0 && segment_sent+1'b1==segment_len) begin
                        remaining<=next_remaining; segment_len<=segment(next_read_address,next_remaining);
                        segment_sent<=0; m_axi_araddr<=next_read_address; m_axi_arvalid<=1;
                    end else state<=IDLE;
                end
            end
            if(state==COLLECT && quiesce) state<=IDLE;
            if(!avl_waitrequest && (avl_write || avl_read)) begin
                if(state==IDLE) begin
                    if(!address_ok || (avl_write && !write_ok) || avl_burstcount==0 || avl_burstcount>16 || (avl_write && avl_read))
                        fault<=1;
                    else begin
                        remaining<=avl_burstcount[4:0]; segment_len<=segment(translated[39:0],avl_burstcount[4:0]);
                        segment_sent<=0; write_index<=0;
                        if(avl_write) begin
                            write_buffer[0]<=avl_writedata; strobe_buffer[0]<=avl_byteenable;
                            collected<=1; m_axi_awaddr<=translated[39:0];
                            if(avl_burstcount==1) begin state<=WRITE; m_axi_awvalid<=1; m_axi_wvalid<=1; end
                            else state<=COLLECT;
                        end else begin
                            state<=READ; m_axi_araddr<=translated[39:0]; m_axi_arvalid<=1;
                        end
                    end
                end else if(state==COLLECT) begin
                    if(!avl_write || avl_read) begin fault<=1; state<=IDLE; end
                    else begin
                        write_buffer[collected[3:0]]<=avl_writedata;
                        strobe_buffer[collected[3:0]]<=avl_byteenable;
                        collected<=collected+1'b1;
                        if(collected+1'b1==remaining) begin state<=WRITE; m_axi_awvalid<=1; m_axi_wvalid<=1; end
                    end
                end
            end
        end
    end
endmodule
