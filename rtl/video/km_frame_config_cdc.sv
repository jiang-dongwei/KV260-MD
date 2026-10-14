// SPDX-License-Identifier: GPL-3.0-or-later
// Latest-value configuration mailbox. The payload is held until a complete
// destination commit is acknowledged (at a frame boundary by default). Changes while busy are
// coalesced into the next complete snapshot. Both domains share application
// reset; deassert it synchronously in each domain at the enclosing shell.
// Physical constraints must bound the held_data -> dst_data bundled-data path
// to one destination clock period (the request has two synchronizer stages).
module km_frame_config_cdc #(
    parameter integer WIDTH=125,
    parameter integer FRAME_BOUNDARY=1,
    parameter [WIDTH-1:0] RESET_VALUE=0
)(
    input wire src_clk, src_resetn,
    input wire [WIDTH-1:0] src_data,
    output wire src_busy,
    input wire dst_clk, dst_resetn, dst_frame,
    output reg [WIDTH-1:0] dst_data,
    output reg dst_changed
);
    reg [WIDTH-1:0] held_data;
    reg request, ack, first;
    (* ASYNC_REG="TRUE" *) reg ack_meta, ack_sync;
    (* ASYNC_REG="TRUE" *) reg req_meta, req_sync;
    reg old_frame;
    assign src_busy=request!=ack_sync;
    always @(posedge src_clk) begin
        if(!src_resetn) begin
            held_data<=RESET_VALUE;request<=0;first<=1;
            ack_meta<=0;ack_sync<=0;
        end else begin
            ack_meta<=ack;ack_sync<=ack_meta;
            if(!src_busy && (first || src_data!=held_data)) begin
                held_data<=src_data;request<=~request;first<=0;
            end
        end
    end
    always @(posedge dst_clk) begin
        if(!dst_resetn) begin
            req_meta<=0;req_sync<=0;ack<=0;old_frame<=0;
            dst_data<=RESET_VALUE;dst_changed<=0;
        end else begin
            req_meta<=request;req_sync<=req_meta;old_frame<=dst_frame;
            dst_changed<=0;
            if((!FRAME_BOUNDARY || (dst_frame && !old_frame)) && req_sync!=ack) begin
                dst_data<=held_data;ack<=req_sync;dst_changed<=1;
            end
        end
    end
endmodule
