// SPDX-License-Identifier: GPL-3.0-or-later
// Clock wizard supplies the unbuffered 85.9090909 MHz NES clock. Identical
// BUFGCE_DIV paths and common CLR/CE keep memory, video and core clocks related.
// Source: AMD UG572 BUFGCE_DIV; physical implementation must check the clocks.
// build.tcl generates these nominal interface frequencies for the actual PS
// reference rate; the three buffer primitives and their ratios are unchanged.
module km_core_clocks(
    (* X_INTERFACE_INFO="xilinx.com:signal:clock:1.0 clk_in CLK" *)
    (* X_INTERFACE_PARAMETER="XIL_INTERFACENAME clk_in, FREQ_HZ 85909091" *)
    input wire clk_in,
    (* X_INTERFACE_INFO="xilinx.com:signal:reset:1.0 reset RST" *)
    (* X_INTERFACE_PARAMETER="XIL_INTERFACENAME reset, POLARITY ACTIVE_HIGH" *)
    input wire reset,
    (* X_INTERFACE_INFO="xilinx.com:signal:clock:1.0 mem_clk CLK" *)
    (* X_INTERFACE_PARAMETER="XIL_INTERFACENAME mem_clk, FREQ_HZ 85909091" *)
    output wire mem_clk,
    (* X_INTERFACE_INFO="xilinx.com:signal:clock:1.0 video_clk CLK" *)
    (* X_INTERFACE_PARAMETER="XIL_INTERFACENAME video_clk, FREQ_HZ 42954545" *)
    output wire video_clk,
    (* X_INTERFACE_INFO="xilinx.com:signal:clock:1.0 core_clk CLK" *)
    (* X_INTERFACE_PARAMETER="XIL_INTERFACENAME core_clk, FREQ_HZ 21477273" *)
    output wire core_clk
);
    BUFGCE_DIV #(.BUFGCE_DIVIDE(1)) mem_buffer(.I(clk_in),.CE(1'b1),.CLR(reset),.O(mem_clk));
    BUFGCE_DIV #(.BUFGCE_DIVIDE(2)) video_buffer(.I(clk_in),.CE(1'b1),.CLR(reset),.O(video_clk));
    BUFGCE_DIV #(.BUFGCE_DIVIDE(4)) core_buffer(.I(clk_in),.CE(1'b1),.CLR(reset),.O(core_clk));
endmodule
