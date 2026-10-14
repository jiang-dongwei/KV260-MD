//============================================================================
//
//  MiSTer Audio mixing & filtering
//  (c)2020-2026 Alexey Melnikov
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 2 of the License, or (at your option)
//  any later version.
//
//  This program is distributed in the hope that it will be useful, but WITHOUT
//  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
//  FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
//  more details.
//
//  You should have received a copy of the GNU General Public License along
//  with this program; if not, write to the Free Software Foundation, Inc.,
//  51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
//
//============================================================================

// KV260 adaptation: expose PCM before serial outputs; coherent input arrives
// from km_audio. Filter, DC removal and mixing remain pinned upstream logic.
module km_audio_filter
#(
	parameter CLK_RATE = 24576000
)
(
	input        reset,
	input        clk,

	//0 - 48KHz, 1 - 96KHz
	input        sample_rate,

	input  [31:0] flt_rate,
	input  [39:0] cx,
	input   [7:0] cx0,
	input   [7:0] cx1,
	input   [7:0] cx2,
	input  [23:0] cy0,
	input  [23:0] cy1,
	input  [23:0] cy2,

	input  [4:0] att,
	input  [1:0] boost,
	input  [1:0] mix,

	input        is_signed,
	input [15:0] core_l,
	input [15:0] core_r,

	input [15:0] alsa_l,
	input [15:0] alsa_r,

    output [15:0] pcm_l,
    output [15:0] pcm_r
);
wire [15:0] al, ar, audio_l_pre, audio_r_pre;
assign pcm_l=al;
assign pcm_r=ar;

reg sample_ce;
reg [8:0] div = 0;
reg [1:0] add = 0;
always @(posedge clk) begin

	div <= div + add;
	if(!div) begin
		div <= 2'd1 << sample_rate;
		add <= 2'd1 << sample_rate;
	end

	sample_ce <= !div;
end

reg flt_ce;
reg [31:0] cnt = 0;
always @(posedge clk) begin

	flt_ce = 0;
	cnt = cnt + {flt_rate[30:0],1'b0};
	if(cnt >= CLK_RATE) begin
		cnt = cnt - CLK_RATE;
		flt_ce = 1;
	end
end

// Input samples are already transferred atomically into clk.
wire [15:0] cl=core_l, cr=core_r;

reg a_en1 = 0, a_en2 = 0;
reg [1:0] dly1 = 0;
reg [14:0] dly2 = 0;
always @(posedge clk, posedge reset) begin

	if(reset) begin
		dly1 <= 0;
		dly2 <= 0;
		a_en1 <= 0;
		a_en2 <= 0;
	end
	else begin
		if(flt_ce) begin
			if(~&dly1) dly1 <= dly1 + 1'd1;
			else a_en1 <= 1;
		end

		if(sample_ce) begin
			if(!dly2[13+sample_rate]) dly2 <= dly2 + 1'd1;
			else a_en2 <= 1;
		end
	end
end

wire [15:0] acl, acr;
IIR_filter #(.use_params(0)) IIR_filter
(
	.clk(clk),
	.reset(reset),

	.ce(flt_ce & a_en1),
	.sample_ce(sample_ce),

	.cx(cx),
	.cx0(cx0),
	.cx1(cx1),
	.cx2(cx2),
	.cy0(cy0),
	.cy1(cy1),
	.cy2(cy2),

	.input_l({~is_signed ^ cl[15], cl[14:0]}),
	.input_r({~is_signed ^ cr[15], cr[14:0]}),
	.output_l(acl),
	.output_r(acr)
);

wire [15:0] adl;
DC_blocker dcb_l
(
	.clk(clk),
	.ce(sample_ce),
	.sample_rate(sample_rate),
	.mute(~a_en2),
	.din(acl),
	.dout(adl)
);

wire [15:0] adr;
DC_blocker dcb_r
(
	.clk(clk),
	.ce(sample_ce),
	.sample_rate(sample_rate),
	.mute(~a_en2),
	.din(acr),
	.dout(adr)
);

km_aud_mix audmix_l
(
	.clk(clk),
	.ce(sample_ce),
	.att(att),
	.boost(boost),
	.mix(mix),

	.core_audio(adl),
	.pre_in(audio_r_pre),
	.linux_audio(alsa_l),

	.pre_out(audio_l_pre),
	.out(al)
);

km_aud_mix audmix_r
(
	.clk(clk),
	.ce(sample_ce),
	.att(att),
	.boost(boost),
	.mix(mix),

	.core_audio(adr),
	.pre_in(audio_l_pre),
	.linux_audio(alsa_r),

	.pre_out(audio_r_pre),
	.out(ar)
);

endmodule

module km_aud_mix
(
	input             clk,
	input             ce,

	input       [4:0] att,
	input       [1:0] boost,
	input       [1:0] mix,

	input      [15:0] core_audio,
	input      [15:0] linux_audio,
	input      [15:0] pre_in,

	output reg [15:0] pre_out = 0,
	output reg [15:0] out = 0
);

localparam boost_f1 = 4;
localparam boost_a1 = 2;
localparam boost_x1 = ((32767 * (boost_f1 - 1)) / ((boost_f1 * boost_a1) - 1)) + 1;
localparam boost_b1 = boost_x1 * boost_a1;

localparam boost_f2 = 8;
localparam boost_a2 = 4;
localparam boost_x2 = ((32767 * (boost_f2 - 1)) / ((boost_f2 * boost_a2) - 1)) + 1;
localparam boost_b2 = boost_x2 * boost_a2;

localparam  [1:0][2:0] boost_f = '{$clog2(boost_f2), $clog2(boost_f1)};
localparam  [1:0][2:0] boost_a = '{$clog2(boost_a2), $clog2(boost_a1)};
localparam [1:0][15:0] boost_x = '{boost_x2[15:0], boost_x1[15:0]};
localparam [1:0][15:0] boost_b = '{boost_b2[15:0], boost_b1[15:0]};

reg signed [15:0] a1;
reg signed [16:0] a2, a3, a4;
reg [15:0] v0, v1;
reg s0,s1;
always @(posedge clk) if (ce) begin

	v0 <= core_audio[15] ? (~core_audio) + 1'd1 : core_audio;
	s0 <= core_audio[15];
	v1 <= (v0 < boost_x[boost[1]]) ? (v0 << boost_a[boost[1]]) : (((v0 - boost_x[boost[1]]) >> boost_f[boost[1]]) + boost_b[boost[1]]);
	s1 <= s0;

	a1 <= boost ? (s1 ? ~(v1-1'd1) : v1) : core_audio;
	a2 <= {a1[15],a1} + {linux_audio[15],linux_audio};

	pre_out <= a2[16:1];

	case(mix)
		0: a3 <= a2;
		1: a3 <= $signed(a2) - $signed(a2[16:3]) + $signed(pre_in[15:2]);
		2: a3 <= $signed(a2) - $signed(a2[16:2]) + $signed(pre_in[15:1]);
		3: a3 <= {a2[16],a2[16:1]} + {pre_in[15],pre_in};
	endcase

	if(att[4]) a4 <= 0;
	else a4 <= a3 >>> att[3:0];

	//clamping
	out <= ^a4[16:15] ? {a4[16],{15{a4[15]}}} : a4[15:0];
end

endmodule
