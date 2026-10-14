// SPDX-License-Identifier: GPL-3.0-or-later
// Console-only pause for a coherent SRAM snapshot. HPS, ROM DMA and SRAM
// port B keep running on clk. Gate CE changes on the falling edge, so a
// synchronous hold can never truncate a console rising-edge clock pulse.
// paused is acknowledged on the next host rising edge after CE is low.
module km_md_clock_gate(
    input wire clk,resetn,hold,
    output wire console_clk,output reg paused
);
    reg enable=1;
    always @(negedge clk) begin
        if(!resetn) enable<=1;
        else enable<=!hold;
    end
    BUFGCE #(.CE_TYPE("ASYNC")) gate(.I(clk),.CE(enable),.O(console_clk));
    always @(posedge clk) begin
        if(!resetn) paused<=0;
        else paused<=!enable;
    end
endmodule
