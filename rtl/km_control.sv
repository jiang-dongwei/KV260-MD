// SPDX-License-Identifier: GPL-3.0-or-later
// AXI4-Lite control registers and a single-outstanding CDC mailbox.
// Both reset inputs must be asserted for a platform reset/core replacement.
// core_ready stays low until the core-side endpoint is initialized.
module km_control #(parameter N64_DEBUG=0) (
    input  wire        axi_clk,
    input  wire        axi_resetn,
    input  wire [7:0]  s_axi_awaddr,
    input  wire        s_axi_awvalid,
    output wire        s_axi_awready,
    input  wire [31:0] s_axi_wdata,
    input  wire [3:0]  s_axi_wstrb,
    input  wire        s_axi_wvalid,
    output wire        s_axi_wready,
    output reg  [1:0]  s_axi_bresp,
    output reg         s_axi_bvalid,
    input  wire        s_axi_bready,
    input  wire [7:0]  s_axi_araddr,
    input  wire        s_axi_arvalid,
    output wire        s_axi_arready,
    output reg  [31:0] s_axi_rdata,
    output reg  [1:0]  s_axi_rresp,
    output reg         s_axi_rvalid,
    input  wire        s_axi_rready,
    input  wire        core_clk,
    input  wire        core_resetn,
    input  wire        core_ready,
    // Independent, synchronized diagnostic flags. Producers must latch
    // transient events in core_clk before presenting them here.
    input  wire [31:0] core_debug,
    // Coherent mailbox payload, already in axi_clk. Reading 0x38 freezes
    // all twenty words so successive MMIO reads refer to one snapshot.
    input  wire [671:0] debug_snapshot_axi,
    output reg         core_cmd_valid,
    output reg  [1:0]  core_cmd,
    // Preserve the destination mailbox register boundary. Absorbing these
    // registers into a downstream DSP bypasses the bundled-data constraints.
    (* DONT_TOUCH="TRUE" *) output reg [31:0] core_argument,
    input  wire        core_cmd_accept,
    input  wire        core_rsp_valid,
    input  wire [31:0] core_result,
    output reg  [39:0] dma_base,
    output reg  [31:0] dma_size,
    output reg         quiesce,
    input  wire        dma_drained
);
    localparam [31:0] MAGIC = 32'h4b4d5354;
    localparam [31:0] ABI = 32'h00010000;
    localparam [1:0] OKAY = 2'b00, SLVERR = 2'b10;
    reg aw_pending, w_pending;
    reg [7:0] aw_addr;
    reg [31:0] w_data;
    reg [3:0] w_strb;
    reg [31:0] argument_reg, result_reg, completed;
    reg overrun;
    reg request_toggle;
    reg [1:0] mailbox_cmd;
    reg [31:0] mailbox_argument;
    reg response_toggle;
    reg [31:0] mailbox_result;
    reg response_seen;
    (* ASYNC_REG = "TRUE" *) reg [1:0] response_sync;
    (* ASYNC_REG = "TRUE" *) reg [1:0] ready_sync;
    (* ASYNC_REG = "TRUE" *) reg [31:0] debug_meta, debug_sync;
    (* ASYNC_REG = "TRUE" *) reg [1:0] request_sync;
    reg request_seen;
    reg core_waiting;
    reg [671:0] debug_latched;
    wire busy = request_toggle != response_seen;

    // Capture AW and W independently. Backpressure holds B/R payloads stable.
    assign s_axi_awready = axi_resetn && !aw_pending && !s_axi_bvalid;
    assign s_axi_wready = axi_resetn && !w_pending && !s_axi_bvalid;
    assign s_axi_arready = axi_resetn && !s_axi_rvalid;

    always @(posedge axi_clk) begin
        if (!axi_resetn) begin
            aw_pending <= 0;
            w_pending <= 0;
            aw_addr <= 0;
            w_data <= 0;
            w_strb <= 0;
            s_axi_bvalid <= 0;
            s_axi_bresp <= OKAY;
            s_axi_rvalid <= 0;
            s_axi_rresp <= OKAY;
            s_axi_rdata <= 0;
            argument_reg <= 0;
            result_reg <= 0;
            completed <= 0;
            overrun <= 0;
            request_toggle <= 0;
            response_seen <= 0;
            response_sync <= 0;
            ready_sync <= 0;
            debug_meta <= 0;
            debug_sync <= 0;
            debug_latched <= 0;
            mailbox_cmd <= 0;
            mailbox_argument <= 0;
            dma_base <= 0;
            dma_size <= 0;
            quiesce <= 1;
        end else begin
            response_sync <= {response_sync[0], response_toggle};
            ready_sync <= {ready_sync[0], core_ready};
            debug_meta <= core_debug;
            debug_sync <= debug_meta;
            if (response_sync[1] != response_seen) begin
                // Result has been stable throughout the two-stage sync.
                result_reg <= mailbox_result;
                response_seen <= response_sync[1];
                completed <= completed + 1'b1;
            end
            if (s_axi_bvalid && s_axi_bready) s_axi_bvalid <= 0;
            if (s_axi_rvalid && s_axi_rready) s_axi_rvalid <= 0;
            if (s_axi_awready && s_axi_awvalid) begin
                aw_addr <= s_axi_awaddr;
                aw_pending <= 1;
            end
            if (s_axi_wready && s_axi_wvalid) begin
                w_data <= s_axi_wdata;
                w_strb <= s_axi_wstrb;
                w_pending <= 1;
            end
            if (aw_pending && w_pending && !s_axi_bvalid) begin
                aw_pending <= 0;
                w_pending <= 0;
                s_axi_bvalid <= 1;
                s_axi_bresp <= OKAY;
                case (aw_addr)
                    8'h08: if (w_strb[0] && w_data[1]) overrun <= 0;
                    8'h10: begin
                        for (integer b = 0; b < 4; b = b + 1)
                            if (w_strb[b]) argument_reg[b*8 +: 8] <= w_data[b*8 +: 8];
                    end
                    8'h18: begin
                        if (w_strb != 4'hf || (w_data != 1 && w_data != 2)) begin
                            s_axi_bresp <= SLVERR;
                        end else if (busy || !ready_sync[1]) begin
                            // Refuse, never overwrite an outstanding command.
                            // Readiness can change after the host's status read.
                            // Report this through the sticky status bit, not an
                            // AXI error which can panic the PS with an SError.
                            overrun <= 1;
                        end else begin
                            mailbox_cmd <= w_data[1:0];
                            mailbox_argument <= argument_reg;
                            request_toggle <= ~request_toggle;
                        end
                    end
                    8'h20, 8'h24, 8'h28: begin
                        if (!quiesce || !dma_drained || w_strb != 4'hf) s_axi_bresp <= SLVERR;
                        else case (aw_addr)
                            8'h20: dma_base[31:0] <= w_data;
                            8'h24: begin
                                if (|w_data[31:8]) s_axi_bresp <= SLVERR;
                                else dma_base[39:32] <= w_data[7:0];
                            end
                            8'h28: dma_size <= w_data;
                        endcase
                    end
                    8'h2c: begin
                        if (w_strb != 4'hf || |w_data[31:1] || (!w_data[0] && dma_size == 0))
                            s_axi_bresp <= SLVERR;
                        else quiesce <= w_data[0];
                    end
                    default: s_axi_bresp <= SLVERR;
                endcase
            end
            if (s_axi_arready && s_axi_arvalid) begin
                s_axi_rvalid <= 1;
                s_axi_rresp <= OKAY;
                case (s_axi_araddr)
                    8'h00: s_axi_rdata <= MAGIC;
                    8'h04: s_axi_rdata <= ABI;
                    8'h08: s_axi_rdata <= {29'd0, ready_sync[1], overrun, busy};
                    8'h10: s_axi_rdata <= argument_reg;
                    8'h14: s_axi_rdata <= result_reg;
                    8'h1c: s_axi_rdata <= completed;
                    8'h20: s_axi_rdata <= dma_base[31:0];
                    8'h24: s_axi_rdata <= {24'd0, dma_base[39:32]};
                    8'h28: s_axi_rdata <= dma_size;
                    8'h2c: s_axi_rdata <= {31'd0, quiesce};
                    8'h30: s_axi_rdata <= {31'd0, dma_drained};
                    8'h34: s_axi_rdata <= debug_sync;
                    8'h38: begin
                        debug_latched <= debug_snapshot_axi;
                        s_axi_rdata <= N64_DEBUG ? 32'h4e363405 : 32'd0;
                        if (!N64_DEBUG) s_axi_rresp <= SLVERR;
                    end
                    8'h3c: begin
                        s_axi_rdata <= N64_DEBUG ? debug_latched[0 +: 32] : 32'd0;
                        if (!N64_DEBUG) s_axi_rresp <= SLVERR;
                    end
                    8'h40: begin
                        s_axi_rdata <= N64_DEBUG ? debug_latched[32 +: 32] : 32'd0;
                        if (!N64_DEBUG) s_axi_rresp <= SLVERR;
                    end
                    8'h44: begin
                        s_axi_rdata <= N64_DEBUG ? debug_latched[64 +: 32] : 32'd0;
                        if (!N64_DEBUG) s_axi_rresp <= SLVERR;
                    end
                    8'h48: begin
                        s_axi_rdata <= N64_DEBUG ? debug_latched[96 +: 32] : 32'd0;
                        if (!N64_DEBUG) s_axi_rresp <= SLVERR;
                    end
                    8'h4c: begin
                        s_axi_rdata <= N64_DEBUG ? debug_latched[128 +: 32] : 32'd0;
                        if (!N64_DEBUG) s_axi_rresp <= SLVERR;
                    end
                    8'h50: begin
                        s_axi_rdata <= N64_DEBUG ? debug_latched[160 +: 32] : 32'd0;
                        if (!N64_DEBUG) s_axi_rresp <= SLVERR;
                    end
                    8'h54: begin
                        s_axi_rdata <= N64_DEBUG ? debug_latched[192 +: 32] : 32'd0;
                        if (!N64_DEBUG) s_axi_rresp <= SLVERR;
                    end
                    8'h58: begin
                        s_axi_rdata <= N64_DEBUG ? debug_latched[224 +: 32] : 32'd0;
                        if (!N64_DEBUG) s_axi_rresp <= SLVERR;
                    end
                    8'h5c: begin
                        s_axi_rdata <= N64_DEBUG ? debug_latched[256 +: 32] : 32'd0;
                        if (!N64_DEBUG) s_axi_rresp <= SLVERR;
                    end
                    8'h60: begin
                        s_axi_rdata <= N64_DEBUG ? debug_latched[288 +: 32] : 32'd0;
                        if (!N64_DEBUG) s_axi_rresp <= SLVERR;
                    end
                    8'h64: begin
                        s_axi_rdata <= N64_DEBUG ? debug_latched[320 +: 32] : 32'd0;
                        if (!N64_DEBUG) s_axi_rresp <= SLVERR;
                    end
                    8'h68: begin
                        s_axi_rdata <= N64_DEBUG ? debug_latched[352 +: 32] : 32'd0;
                        if (!N64_DEBUG) s_axi_rresp <= SLVERR;
                    end
                    8'h6c: begin
                        s_axi_rdata <= N64_DEBUG ? debug_latched[384 +: 32] : 32'd0;
                        if (!N64_DEBUG) s_axi_rresp <= SLVERR;
                    end
                    8'h70: begin
                        s_axi_rdata <= N64_DEBUG ? debug_latched[416 +: 32] : 32'd0;
                        if (!N64_DEBUG) s_axi_rresp <= SLVERR;
                    end
                    8'h74: begin
                        s_axi_rdata <= N64_DEBUG ? debug_latched[448 +: 32] : 32'd0;
                        if (!N64_DEBUG) s_axi_rresp <= SLVERR;
                    end
                    8'h78: begin
                        s_axi_rdata <= N64_DEBUG ? debug_latched[480 +: 32] : 32'd0;
                        if (!N64_DEBUG) s_axi_rresp <= SLVERR;
                    end
                    8'h7c: begin
                        s_axi_rdata <= N64_DEBUG ? debug_latched[512 +: 32] : 32'd0;
                        if (!N64_DEBUG) s_axi_rresp <= SLVERR;
                    end
                    8'h80: begin
                        s_axi_rdata <= N64_DEBUG ? debug_latched[544 +: 32] : 32'd0;
                        if (!N64_DEBUG) s_axi_rresp <= SLVERR;
                    end
                    8'h84: begin
                        s_axi_rdata <= N64_DEBUG ? debug_latched[576 +: 32] : 32'd0;
                        if (!N64_DEBUG) s_axi_rresp <= SLVERR;
                    end
                    8'h88: begin
                        s_axi_rdata <= N64_DEBUG ? debug_latched[608 +: 32] : 32'd0;
                        if (!N64_DEBUG) s_axi_rresp <= SLVERR;
                    end
                    8'h8c: begin
                        s_axi_rdata <= N64_DEBUG ? debug_latched[640 +: 32] : 32'd0;
                        if (!N64_DEBUG) s_axi_rresp <= SLVERR;
                    end
                    default: begin
                        s_axi_rdata <= 0;
                        s_axi_rresp <= SLVERR;
                    end
                endcase
            end
        end
    end

    always @(posedge core_clk) begin
        if (!core_resetn) begin
            request_sync <= 0;
            request_seen <= 0;
            response_toggle <= 0;
            mailbox_result <= 0;
            core_cmd_valid <= 0;
            core_cmd <= 0;
            core_argument <= 0;
            core_waiting <= 0;
        end else begin
            request_sync <= {request_sync[0], request_toggle};
            if (!core_cmd_valid && !core_waiting && core_ready &&
                request_sync[1] != request_seen) begin
                // Payload remains stable until the response is consumed.
                core_cmd <= mailbox_cmd;
                core_argument <= mailbox_argument;
                core_cmd_valid <= 1;
                request_seen <= request_sync[1];
            end
            if (core_cmd_valid && core_cmd_accept) begin
                core_cmd_valid <= 0;
                core_waiting <= 1;
            end
            // Allow a response on the acceptance edge or at any later edge.
            if (core_rsp_valid && (core_waiting || (core_cmd_valid && core_cmd_accept))) begin
                mailbox_result <= core_result;
                response_toggle <= request_seen;
                core_waiting <= 0;
            end
        end
    end
endmodule
