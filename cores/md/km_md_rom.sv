// SPDX-License-Identifier: GPL-3.0-or-later
// Same-clock replacement for Genesis SDRAM + DDRAM ROM storage.
// Toggle clients hold payload until acknowledgment. Loader words are already
// swapped by emu to the console's big-endian word order. Cache lines contain
// 32 such words; all stores invalidate the indexed line before completing.
// Application reset clears metadata only; console reset does not cancel DMA.
module km_md_rom #(
    parameter INDEX_BITS=8
)(
    input wire clk, resetn, quiesce,
    output wire drained, output reg fault,
    input wire [23:0] load_addr, input wire [15:0] load_data,
    input wire load_req, output reg load_ack,
    input wire [23:0] rom_addr, output reg [15:0] rom_data,
    input wire [15:0] rom_write_data, input wire [1:0] rom_be,
    input wire rom_write, rom_req, output reg rom_ack,
    input wire [23:0] rom2_addr, output reg [15:0] rom2_data,
    input wire rom2_req, output reg rom2_ack,
    input wire DDRAM_BUSY, DDRAM_FAULT, DDRAM_DRAINED,
    output reg [7:0] DDRAM_BURSTCNT, output reg [28:0] DDRAM_ADDR,
    input wire [63:0] DDRAM_DOUT, input wire DDRAM_DOUT_READY,
    output reg DDRAM_RD, output reg [63:0] DDRAM_DIN,
    output reg [7:0] DDRAM_BE, output reg DDRAM_WE
);
    localparam TAG_BITS=19-INDEX_BITS;
    localparam IDLE=0, LOOKUP=1, COMMAND=2, WRITE_WAIT=3, FILL=4, COMPLETE=5;
    reg [2:0] state;
    reg [2:0] queued;
    reg queued_token[0:2],queued_write[0:2];
    reg [23:0] queued_address[0:2];
    reg [15:0] queued_data[0:2];
    reg [1:0] queued_be[0:2];
    wire [1:0] next_channel=queued[0] ? 0 : queued[1] ? 1 : 2;
    wire [23:0] next_address=queued_address[next_channel];
    reg [1:0] channel;
    reg token, writing;
    reg [23:0] address;
    reg [15:0] data;
    reg [1:0] byte_enable;
    reg [2:0] beat;
    reg [15:0] result;
    reg [INDEX_BITS-1:0] clear_index;
    reg initialized;
    reg valid [0:(1<<INDEX_BITS)-1];
    reg [TAG_BITS-1:0] tags [0:(1<<INDEX_BITS)-1];
    (* ram_style="block" *) reg [63:0] cache [0:(1<<(INDEX_BITS+3))-1];
    wire [INDEX_BITS-1:0] index=address[INDEX_BITS+4:5];
    wire [TAG_BITS-1:0] tag=address[23:INDEX_BITS+5];
    reg cache_valid_q;
    reg [TAG_BITS-1:0] tag_q;
    reg [63:0] cache_q;
    // Synchronous lookup; one extra cycle in LOOKUP observes the RAM result.
    always @(posedge clk) begin
        if(state==IDLE) begin
            cache_q<=cache[{next_address[INDEX_BITS+4:5],next_address[4:2]}];
            tag_q<=tags[next_address[INDEX_BITS+4:5]];
            cache_valid_q<=valid[next_address[INDEX_BITS+4:5]];
        end
        if(state==FILL && DDRAM_DOUT_READY)
            cache[{index,beat}]<=DDRAM_DOUT;
    end
    wire pending=(|queued) || (load_req!=load_ack) || (rom_req!=rom_ack) || (rom2_req!=rom2_ack);
    assign drained=initialized && state==IDLE && (!pending || fault) && !DDRAM_RD && !DDRAM_WE;
    // quiesce stops the console/loader at integration level. Already posted
    // toggles are still accepted here so replacing an application can drain.
    always @(posedge clk) begin
        if(!resetn) begin
            state<=IDLE; fault<=0; initialized<=0; clear_index<=0;queued<=0;
            for(integer i=0;i<3;i=i+1) begin
                queued_token[i]<=0;queued_write[i]<=0;queued_address[i]<=0;
                queued_data[i]<=0;queued_be[i]<=0;
            end
            load_ack<=0; rom_ack<=0; rom2_ack<=0;
            rom_data<=0;rom2_data<=0; result<=0;
            channel<=0; token<=0; writing<=0; address<=0; data<=0;byte_enable<=0;beat<=0;
            DDRAM_RD<=0; DDRAM_WE<=0; DDRAM_BURSTCNT<=0;
            DDRAM_ADDR<=0; DDRAM_DIN<=0; DDRAM_BE<=0;
        end else begin
            DDRAM_RD<=0; DDRAM_WE<=0;
            // Capture every posted toggle immediately, including while another
            // client owns DDR. Console reset can change mapper registers before
            // arbitration returns idle; it must not rewrite an admitted payload.
            if(initialized && !fault && !DDRAM_FAULT) begin
                if(!queued[0] && !(state!=IDLE && channel==0) && load_req!=load_ack) begin
                    queued[0]<=1;queued_token[0]<=load_req;queued_write[0]<=1;
                    queued_address[0]<=load_addr;queued_data[0]<=load_data;queued_be[0]<=3;
                end
                if(!queued[1] && !(state!=IDLE && channel==1) && rom_req!=rom_ack) begin
                    queued[1]<=1;queued_token[1]<=rom_req;queued_write[1]<=rom_write;
                    queued_address[1]<=rom_addr;queued_data[1]<=rom_write_data;queued_be[1]<=rom_be;
                end
                if(!queued[2] && !(state!=IDLE && channel==2) && rom2_req!=rom2_ack) begin
                    queued[2]<=1;queued_token[2]<=rom2_req;queued_write[2]<=0;
                    queued_address[2]<=rom2_addr;queued_data[2]<=0;queued_be[2]<=0;
                end
            end
            if(!initialized) begin
                valid[clear_index]<=0;
                if(&clear_index) initialized<=1;
                else clear_index<=clear_index+1'b1;
            end else if(DDRAM_FAULT || fault) begin
                fault<=1;
                // An error response must still finish on AXI before this
                // client can report drained. Never release the DMA allocation
                // while the backend is waiting for B/RLAST.
                if(DDRAM_DRAINED) state<=IDLE;
            end else case(state)
                IDLE: if(|queued) begin
                    channel<=next_channel;token<=queued_token[next_channel];
                    address<=next_address;writing<=queued_write[next_channel];
                    data<=queued_data[next_channel];byte_enable<=queued_be[next_channel];
                    queued[next_channel]<=0;
                    state<=next_channel==1 && !queued_write[next_channel] ? LOOKUP : COMMAND;
                end
                LOOKUP: begin
                    if(cache_valid_q && tag_q==tag) begin
                        result<=cache_q[address[1:0]*16+:16];state<=COMPLETE;
                    end else state<=COMMAND;
                end
                COMMAND: if(!DDRAM_BUSY) begin
                    // word address -> 64-bit DDRAM address. DMA offset 256 MiB.
                    DDRAM_ADDR<=writing ? {4'b0011,3'd0,address[23:2]} :
                                           {4'b0011,3'd0,address[23:5],3'd0};
                    DDRAM_BURSTCNT<=writing ? 8'd1 : 8'd8;
                    DDRAM_DIN<={4{data}};
                    DDRAM_BE<=writing ? ({6'd0,byte_enable} << {address[1:0],1'b0}) : 8'hff;
                    valid[index]<=0;
                    beat<=0;
                    if(writing) begin DDRAM_WE<=1;state<=WRITE_WAIT; end
                    else begin DDRAM_RD<=1;state<=FILL; end
                end
                WRITE_WAIT: if(!DDRAM_BUSY && !DDRAM_WE) state<=COMPLETE;
                FILL: if(DDRAM_DOUT_READY) begin
                    if(beat==address[4:2]) result<=DDRAM_DOUT[address[1:0]*16+:16];
                    if(beat==7) begin
                        valid[index]<=1;tags[index]<=tag;state<=COMPLETE;
                    end else beat<=beat+1'b1;
                end
                COMPLETE: begin
                    case(channel)
                        0: load_ack<=token;
                        1: begin rom_ack<=token;rom_data<=result;end
                        2: begin rom2_ack<=token;rom2_data<=result;end
                        default: fault<=1;
                    endcase
                    state<=IDLE;
                end
                default: fault<=1;
            endcase
        end
    end
endmodule
