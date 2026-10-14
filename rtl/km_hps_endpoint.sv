// SPDX-License-Identifier: GPL-3.0-or-later
// GPO/GPI encoding and strobe/ack sequencing follow MiSTer's sys_top.v
// (MiSTer framework, Alexey Melnikov and contributors). The transport is AXI.
module km_hps_endpoint #(
    parameter [7:0] CORE_TYPE = 8'ha4
) (
    input wire clk,
    input wire resetn,
    input wire cmd_valid,
    input wire [1:0] cmd,
    input wire [31:0] argument,
    output wire cmd_accept,
    output reg rsp_valid,
    output reg [31:0] result,
    input wire [15:0] io_dout,
    input wire io_wide,
    input wire io_wait,
    input wire vs_wait,
    input wire [1:0] buttons,
    output wire [15:0] io_din,
    output wire io_strobe,
    output wire io_fpga,
    output wire io_uio,
    output wire io_osd,
    output wire core_reset,
    output wire user_led
);
    reg [31:0] gpo;
    reg rack, io_ack;
    wire [31:0] gpi = {1'b0, buttons[1], buttons[0], 1'b1,
                       7'd0, 1'b0, 2'd1, io_ack, io_wide, io_dout};
    assign cmd_accept = resetn;
    assign io_din = gpo[15:0];
    assign io_strobe = ~rack & gpo[17];
    assign io_fpga = ~gpo[19] & gpo[18];
    assign io_uio = ~gpo[19] & gpo[20];
    assign io_osd = gpo[19] & (~gpo[18] | ~gpo[20]);
    assign core_reset = gpo[30] & ~gpo[31];
    assign user_led = gpo[29];
    always @(posedge clk) begin
        if (!resetn) begin
            gpo <= 0;
            rack <= 0;
            io_ack <= 0;
            rsp_valid <= 0;
            result <= 0;
        end else begin
            rsp_valid <= 0;
            if (!(io_wait | vs_wait) | io_strobe) begin
                rack <= gpo[17];
                io_ack <= rack;
            end
            if (cmd_valid && cmd_accept) begin
                if (cmd == 1) begin
                    gpo <= argument;
                    result <= 0;
                end else if (cmd == 2) begin
                    result <= gpo[31] ? gpi : {24'h5ca623, CORE_TYPE};
                end else begin
                    result <= 32'hffffffff;
                end
                rsp_valid <= 1;
            end
        end
    end
endmodule
