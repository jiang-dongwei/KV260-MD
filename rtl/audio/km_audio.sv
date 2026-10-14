// SPDX-License-Identifier: GPL-3.0-or-later
// Coherent stereo CDC -> upstream filtering/DC removal/mix -> PS live audio.
// audio_clk must be 24.576 MHz. DPSUB TREADY paces stereo pairs at 48 kHz;
// filtered output and sink therefore share the same frequency reference.
module km_audio #(parameter DIRECT_AUDIO_CLOCK=0)(
    input wire core_clk,core_resetn,audio_clk,audio_resetn,
    input wire [15:0] core_l,core_r,
    input wire is_signed,input wire [1:0] mix,input wire [4:0] attenuation,
    output wire [31:0] m_axis_tdata,output wire [7:0] m_axis_tid,
    output wire m_axis_tvalid,input wire m_axis_tready
);
    reg phase;
    always @(posedge audio_clk) if(!audio_resetn) phase<=0;else phase<=~phase;
    wire [39:0] audio_snapshot;
    // Continuous latest-value snapshots, with the entire stereo pair and its
    // interpretation held through acknowledgment. No independent data-bit CDC.
    generate if(DIRECT_AUDIO_CLOCK) begin: direct_samples
        // A logical-time queue already crossed into audio_clk (SNES).
        assign audio_snapshot={is_signed,mix,attenuation,core_l,core_r};
    end else begin: coherent_samples
    km_frame_config_cdc #(.WIDTH(40),.RESET_VALUE({1'b1,2'b00,5'b11111,32'd0})) samples(
        .src_clk(core_clk),.src_resetn(core_resetn),
        .src_data({is_signed,mix,attenuation,core_l,core_r}),.src_busy(),
        .dst_clk(audio_clk),.dst_resetn(audio_resetn),.dst_frame(phase),
        .dst_data(audio_snapshot),.dst_changed());
    end endgenerate
    wire [15:0] pcm_l,pcm_r;
    km_audio_filter filter(.reset(!audio_resetn),.clk(audio_clk),.sample_rate(1'b0),
        .flt_rate(32'd7056000),.cx(40'd4258969),.cx0(8'd3),.cx1(8'd3),.cx2(8'd1),
        .cy0(-24'd6216759),.cy1(24'd6143386),.cy2(-24'd2023767),
        .att(audio_snapshot[36:32]),.boost(2'd0),.mix(audio_snapshot[38:37]),
        .is_signed(audio_snapshot[39]),.core_l(audio_snapshot[31:16]),.core_r(audio_snapshot[15:0]),
        .alsa_l(16'd0),.alsa_r(16'd0),.pcm_l(pcm_l),.pcm_r(pcm_r));
    // Reuse prior-art IEC60958 channel-status, parity and AXIS backpressure.
    z486_dp_audio packetizer(.clk(audio_clk),.resetn(audio_resetn),
        .sample_l(pcm_l),.sample_r(pcm_r),.boost(2'd0),
        .m_axis_tdata(m_axis_tdata),.m_axis_tid(m_axis_tid),
        .m_axis_tvalid(m_axis_tvalid),.m_axis_tready(m_axis_tready));
endmodule
