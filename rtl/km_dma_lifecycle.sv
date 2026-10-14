// SPDX-License-Identifier: GPL-3.0-or-later
// Quiesce handshake across unrelated AXI and core clocks. A stop is acknowledged
// only after the receiving master stops admission AND drains issued transfers.
// The source may update base/size only while source_drained is true. These
// bundled data paths require a max-delay constraint of one destination period.
module km_dma_lifecycle(
    input wire source_clk,source_resetn,source_quiesce,
    input wire [39:0] source_base,input wire [31:0] source_size,
    output wire source_drained,
    input wire destination_clk,destination_resetn,destination_drained,
    output reg destination_quiesce,
    output reg [39:0] destination_base,output reg [31:0] destination_size
);
    reg request,held_quiesce,first;
    reg acknowledge;
    (* ASYNC_REG="TRUE" *) reg ack_meta,ack_sync,req_meta,req_sync;
    wire busy=request!=ack_sync;
    assign source_drained=source_quiesce && held_quiesce && !first && !busy;
    always @(posedge source_clk) begin
        if(!source_resetn) begin
            request<=0;held_quiesce<=1;first<=1;ack_meta<=0;ack_sync<=0;
        end else begin
            ack_meta<=acknowledge;ack_sync<=ack_meta;
            if(!busy && (first || source_quiesce!=held_quiesce)) begin
                request<=~request;held_quiesce<=source_quiesce;first<=0;
            end
        end
    end
    reg committed;
    always @(posedge destination_clk) begin
        if(!destination_resetn) begin
            req_meta<=0;req_sync<=0;acknowledge<=0;committed<=0;
            destination_quiesce<=1;destination_base<=0;destination_size<=0;
        end else begin
            req_meta<=request;req_sync<=req_meta;
            // Source metadata is stable before the release request traverses
            // two synchronizer flops. It never changes while DMA is running.
            if(destination_quiesce) begin
                destination_base<=source_base;destination_size<=source_size;
            end
            if(req_sync!=acknowledge) begin
                if(!committed) begin
                    destination_quiesce<=held_quiesce;
                    committed<=1;
                end else if(!destination_quiesce || destination_drained) begin
                    acknowledge<=req_sync;committed<=0;
                end
            end
        end
    end
endmodule
