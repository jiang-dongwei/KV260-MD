// SPDX-License-Identifier: GPL-3.0-or-later
// Private UIO 0x70 extension: operand 0 polls, 1 holds+flushes, 2 releases.
// Response 0x4e00 | hold<<3 | error<<2 | busy<<1 | done. Hold persists after
// success until a new ROM download or explicit release. It pauses emulation,
// not the backup-memory/HPS engine. Every writable battery cartridge gets a
// full snapshot, allowing retry after an earlier filesystem write failure.
module km_md_flush(
    input wire clk,reset,downloading,
    inout wire [35:0] ext_bus,
    input wire battery,pending,enabled,backup_busy,paused,
    output reg hold,output reg save_request
);
    wire select=ext_bus[34],strobe=ext_bus[33];
    wire [15:0] din=ext_bus[31:16];
    reg command_seen,selected;
    reg done,error;
    localparam IDLE=0,SETTLE=1,PRIOR=2,START=3,FINISH=4,COMPLETE=5;
    reg [2:0] state;
    wire busy=state!=IDLE && state!=COMPLETE;
    assign ext_bus[32]=select && selected;
    assign ext_bus[15:0]={8'h4e,4'd0,hold,error,busy,done};
    wire begin_request=select && strobe && command_seen && selected && din==1;
    wire release_request=select && strobe && command_seen && selected && din==2;
    always @(posedge clk) begin
        if(reset) begin
            command_seen<=0;selected<=0;done<=0;error<=0;
            hold<=0;save_request<=0;state<=IDLE;
        end else begin
            save_request<=0;
            if(!select) begin command_seen<=0;selected<=0;end
            else if(strobe && !command_seen) begin
                command_seen<=1;selected<=din==16'h70;
            end
            if(downloading || release_request) begin
                hold<=0;done<=0;error<=0;state<=IDLE;
            end else if(begin_request && !busy) begin
                hold<=1;done<=0;error<=0;state<=SETTLE;
            end else case(state)
                // The MD console clock gate must acknowledge the hold;
                // waiting a fixed number of clocks is not sufficient.
                SETTLE: if(paused) state<=PRIOR;
                PRIOR: if(!backup_busy) begin
                    if(!battery || (!enabled && !pending)) begin done<=1;state<=COMPLETE;end
                    else if(!enabled) begin error<=1;done<=1;state<=COMPLETE;end
                    else begin save_request<=1;state<=START;end
                end
                START: if(backup_busy) state<=FINISH;
                FINISH: if(!backup_busy) begin done<=1;state<=COMPLETE;end
                default: ;
            endcase
        end
    end
endmodule
