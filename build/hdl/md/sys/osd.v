// A simple OSD implementation. Can be hooked up between a cores
// VGA output and the physical VGA pins

module osd
(
	input         clk_sys,
	input         io_osd,
	input         io_strobe,
	input  [15:0] io_din,

	input         clk_video,
	input  [23:0] din,
	input         de_in,
	input         vs_in,
	input         hs_in,
	output [23:0] dout,
	output reg    de_out,
	output reg    vs_out,
	output reg    hs_out,

	output reg    osd_status
);

parameter  OSD_COLOR    =  3'd4;

localparam OSD_WIDTH    = 12'd256;
localparam OSD_HEIGHT   = 12'd64;

`ifdef MENU_CORE
localparam OSD_HDR      = 12'd24;
`else
localparam OSD_HDR      = 12'd0;
`endif

reg        osd_enable;
(* ramstyle="no_rw_check" *) reg  [7:0] osd_buffer[OSD_HDR ? (4096+1024) : 4096];

reg        info = 0;
reg  [8:0] infoh;
reg  [8:0] infow;
reg [21:0] infox;
reg [21:0] infoy;
reg [21:0] osd_h;
reg [21:0] osd_t;
reg [21:0] osd_w;

reg  [1:0] rot = 0;

// Explicit module-scope initialization preserves state across clock edges.
reg        km_init_0_highres = 0;
always@(posedge clk_sys) begin
	reg [12:0] bcnt;
	reg  [7:0] cmd;
	reg        has_cmd;
	reg        old_strobe;


	osd_t <= rot[0] ? OSD_WIDTH : (OSD_HEIGHT<<1);
	osd_h <= rot[0] ? (info ? infow : OSD_WIDTH) : info ? infoh : (OSD_HEIGHT<<km_init_0_highres);
	osd_w <= rot[0] ? (info ? infoh : (OSD_HEIGHT<<km_init_0_highres)) : (info ? infow : OSD_WIDTH);

	old_strobe <= io_strobe;

	if(~io_osd) begin
		bcnt <= 0;
		has_cmd <= 0;
		cmd <= 0;
		if(cmd[7:4] == 4) osd_enable <= cmd[0];
	end else begin
		if(~old_strobe & io_strobe) begin
			if(!has_cmd) begin
				has_cmd <= 1;
				cmd <= io_din[7:0];
				// command 0x40: OSDCMDENABLE, OSDCMDDISABLE
				if(io_din[7:4] == 4) begin
					if(!io_din[0]) {osd_status,km_init_0_highres} <= 0;
					else {osd_status,info} <= {~io_din[2] & ~io_din[3],io_din[2]};
					bcnt  <= 0;
				end
				// command 0x20: OSDCMDWRITE
				if(io_din[7:5] == 'b001) begin
					if(io_din[3]) km_init_0_highres <= 1;
					bcnt <= {io_din[4:0], 8'h00};
				end
			end else begin
				// command 0x40: OSDCMDENABLE, OSDCMDDISABLE
				if(cmd[7:4] == 4) begin
					if(bcnt == 0) infox <= io_din[11:0];
					if(bcnt == 1) infoy <= io_din[11:0];
					if(bcnt == 2) infow <= {io_din[5:0], 3'b000};
					if(bcnt == 3) infoh <= {io_din[5:0], 3'b000};
					if(bcnt == 4) rot   <= io_din[1:0];
				end

				// command 0x20: OSDCMDWRITE
				if(cmd[7:5] == 'b001) osd_buffer[bcnt] <= io_din[7:0];

				bcnt <= bcnt + 1'd1;
			end
		end
	end
end

// Transfer the completed OSD geometry as one held snapshot. Registers are
// initialized by FPGA configuration, matching the upstream OSD lifetime.
// Payload paths require a one-pixel-period datapath-only max-delay bound.
wire [113:0] km_osd_source = {osd_enable,info,rot,infox,infoy,osd_h,osd_t,osd_w};
reg [113:0] km_osd_held = 0;
reg [113:0] km_osd_pixel = 0;
reg km_osd_request = 0, km_osd_ack = 0, km_osd_first = 1;
(* ASYNC_REG="TRUE" *) reg km_osd_ack_meta = 0, km_osd_ack_sync = 0;
(* ASYNC_REG="TRUE" *) reg km_osd_req_meta = 0, km_osd_req_sync = 0;
reg [1:0] km_osd_idle = 0;
reg km_osd_old_vs = 0;
wire km_pixel_osd_enable,km_pixel_info;
wire [1:0] km_pixel_rot;
wire [21:0] km_pixel_infox,km_pixel_infoy,km_pixel_osd_h,km_pixel_osd_t,km_pixel_osd_w;
assign {km_pixel_osd_enable,km_pixel_info,km_pixel_rot,km_pixel_infox,
        km_pixel_infoy,km_pixel_osd_h,km_pixel_osd_t,km_pixel_osd_w}=km_osd_pixel;
always @(posedge clk_sys) begin
    km_osd_ack_meta <= km_osd_ack;
    km_osd_ack_sync <= km_osd_ack_meta;
    km_osd_idle <= {km_osd_idle[0],!io_osd};
    // Wait for the command to end and the derived geometry to settle.
    if (&km_osd_idle && !io_osd && km_osd_request==km_osd_ack_sync &&
        (km_osd_first || km_osd_held!=km_osd_source)) begin
        km_osd_held <= km_osd_source;
        km_osd_request <= ~km_osd_request;
        km_osd_first <= 0;
    end
end
always @(posedge clk_video) begin
    km_osd_req_meta <= km_osd_request;
    km_osd_req_sync <= km_osd_req_meta;
    km_osd_old_vs <= vs_in;
    if (vs_in && !km_osd_old_vs && km_osd_req_sync!=km_osd_ack) begin
        km_osd_pixel <= km_osd_held;
        km_osd_ack <= km_osd_req_sync;
    end
end

(* direct_enable *) reg ce_pix;
// Explicit module-scope initialization preserves state across clock edges.
reg [21:0] km_init_1_cnt = 0;
always @(posedge clk_video) begin

	reg [21:0] pixsz, pixcnt;
	reg deD;

	km_init_1_cnt <= km_init_1_cnt + 1'd1;
	deD <= de_in;

	pixcnt <= pixcnt + 1'd1;
	if(pixcnt == pixsz) pixcnt <= 0;
	ce_pix <= !pixcnt;

	if(~deD && de_in) km_init_1_cnt <= 0;

	if(deD && ~de_in) begin
		pixsz  <= (((km_init_1_cnt+1'b1) >> (9-km_pixel_rot[0])) > 1) ? (((km_init_1_cnt+1'b1) >> (9-km_pixel_rot[0])) - 1'd1) : 22'd0;
		pixcnt <= 0;
	end
end

reg  [2:0] osd_de;
reg        osd_pixel;
reg [21:0] v_cnt;
reg        v_cnt_h, v_cnt_1, v_cnt_2, v_cnt_3, v_cnt_4;
reg [21:0] v_osd_start_h, v_osd_start_1, v_osd_start_2, v_osd_start_3, v_osd_start_4, v_osd_start_5;
reg [21:0] v_info_start_h, v_info_start_1, v_info_start_2, v_info_start_3, v_info_start_4, v_info_start_5;

wire [21:0] osd_h_hdr = (km_pixel_info || km_pixel_rot) ? km_pixel_osd_h : (km_pixel_osd_h + OSD_HDR);

// pipeline the comparisons a bit
always @(posedge clk_video) if(ce_pix) begin
	v_cnt_h <= v_cnt <= km_pixel_osd_t;
	v_cnt_1 <= v_cnt < 320;
	v_cnt_2 <= v_cnt < 640;
	v_cnt_3 <= v_cnt < 960;
	v_cnt_4 <= v_cnt < 1280;

	v_osd_start_h <= (v_cnt-(osd_h_hdr>>1))>>1;
	v_osd_start_1 <= (v_cnt-osd_h_hdr)>>1;
	v_osd_start_2 <= (v_cnt-(osd_h_hdr<<1))>>1;
	v_osd_start_3 <= (v_cnt-(osd_h_hdr + (osd_h_hdr<<1)))>>1;
	v_osd_start_4 <= (v_cnt-(osd_h_hdr<<2))>>1;
	v_osd_start_5 <= (v_cnt-(osd_h_hdr + (osd_h_hdr<<2)))>>1;

	v_info_start_h <= km_pixel_rot[0] ? km_pixel_infox : km_pixel_infoy;
	v_info_start_1 <= km_pixel_rot[0] ? km_pixel_infox : km_pixel_infoy;
	v_info_start_2 <= km_pixel_rot[0] ? (km_pixel_infox<<1) : (km_pixel_infoy<<1);
	v_info_start_3 <= km_pixel_rot[0] ? (km_pixel_infox + (km_pixel_infox << 1)) : (km_pixel_infoy + (km_pixel_infoy << 1));
	v_info_start_4 <= km_pixel_rot[0] ? (km_pixel_infox << 2) : (km_pixel_infoy << 2);
	v_info_start_5 <= km_pixel_rot[0] ? (km_pixel_infox + (km_pixel_infox << 2)) : (km_pixel_infoy + (km_pixel_infoy << 2));
end

always @(posedge clk_video) begin
	reg        deD;
	reg  [2:0] osd_div;
	reg  [2:0] multiscan;
	reg  [7:0] osd_byte; 
	reg [23:0] h_cnt;
	reg [21:0] dsp_width;
	reg [21:0] osd_vcnt;
	reg [21:0] h_osd_start;
	reg [21:0] v_osd_start;
	reg [21:0] osd_hcnt;
	reg [21:0] osd_hcnt2;
	reg        osd_de1,osd_de2;
	reg  [1:0] osd_en;
	reg        f1;
	reg        half;

	if(ce_pix) begin

		deD <= de_in;
		if(~&h_cnt) h_cnt <= h_cnt + 1'd1;

		if(~&osd_hcnt)  osd_hcnt  <= osd_hcnt + 1'd1;
		if(~&osd_hcnt2) osd_hcnt2 <= osd_hcnt2 + 1'd1;

		if (h_cnt == h_osd_start) begin
			osd_de[0] <= osd_en[1] && km_pixel_osd_h && (
		                  osd_vcnt[11] ? (osd_vcnt[7] && (osd_vcnt[6:0] >= 4) && (osd_vcnt[6:0] < 19)) :
								(km_pixel_info && (km_pixel_rot == 3)) ? !osd_vcnt[21:8] :
			               (osd_vcnt < km_pixel_osd_h)
								);
			osd_hcnt <= 0;
			osd_hcnt2 <= 0;
			// In rotated info mode osd_w is infoh, already in the coherent
			// pixel-domain snapshot. Do not read the live sys-domain dimension.
			if(km_pixel_info && km_pixel_rot == 1) osd_hcnt2 <= 22'd128-km_pixel_osd_w;
		end
		if (osd_hcnt+1 == km_pixel_osd_w) osd_de[0] <= 0;

		// falling edge of de
		if(!de_in && deD) dsp_width <= h_cnt[21:0];

		// rising edge of de
		if(de_in && !deD) begin
			h_cnt <= 0;
			v_cnt <= v_cnt + 1'd1;
			h_osd_start <= km_pixel_info ? (km_pixel_rot[0] ? km_pixel_infoy : km_pixel_infox) : (((dsp_width - km_pixel_osd_w)>>1) - 2'd2);

			if(h_cnt > {dsp_width, 2'b00}) begin
				v_cnt <= 1;
				f1 <= ~f1; // skip every other frame for interlace compatibility.
				if(~f1) begin

					osd_en <= (osd_en << 1) | km_pixel_osd_enable;
					if(~km_pixel_osd_enable) osd_en <= 0;

					half <= 0;
					if(v_cnt_h) begin
						multiscan <= 0;
						v_osd_start <= km_pixel_info ? v_info_start_h : v_osd_start_h;
						half <= 1;
					end
					else if(v_cnt_1 | (km_pixel_rot[0] & v_cnt_2)) begin
						multiscan <= 0;
						v_osd_start <= km_pixel_info ? v_info_start_1 : v_osd_start_1;
					end
					else if(km_pixel_rot[0] ? v_cnt_3 : v_cnt_2) begin
						multiscan <= 1;
						v_osd_start <= km_pixel_info ? v_info_start_2 : v_osd_start_2;
					end
					else if(km_pixel_rot[0] ? v_cnt_4 : v_cnt_3) begin
						multiscan <= 2;
						v_osd_start <= km_pixel_info ? v_info_start_3 : v_osd_start_3;
					end
					else if(km_pixel_rot[0] | v_cnt_4) begin
						multiscan <= 3;
						v_osd_start <= km_pixel_info ? v_info_start_4 : v_osd_start_4;
					end
					else begin
						multiscan <= 4;
						v_osd_start <= km_pixel_info ? v_info_start_5 : v_osd_start_5;
					end
				end
			end

			osd_div <= osd_div + 1'd1;
			if(osd_div == multiscan) begin
				osd_div <= 0;
				if(~osd_vcnt[10]) osd_vcnt <= osd_vcnt + 1'd1 + half;
				if(osd_vcnt == 'b100010011111 && ~km_pixel_info) osd_vcnt <= 0;
			end
			if(v_osd_start == v_cnt) begin
				{osd_div,osd_vcnt} <= 0;
				// Likewise, rotated info osd_h is the snapshotted infow.
				if(km_pixel_info && km_pixel_rot == 3) osd_vcnt <= 22'd256-km_pixel_osd_h;
				else if(OSD_HDR && !km_pixel_rot) osd_vcnt <= {~km_pixel_info, 3'b000, ~km_pixel_info, 7'b0000000};
			end
		end

		osd_byte  <= osd_buffer[km_pixel_rot[0] ? ({osd_hcnt2[6:3], osd_vcnt[7:0]} ^ { {4{~km_pixel_rot[1]}}, {8{km_pixel_rot[1]}} }) : {osd_vcnt[7:3], osd_hcnt[7:0]}];
		osd_pixel <= osd_byte[km_pixel_rot[0] ? ((osd_hcnt2[2:0]-1'd1) ^ {3{~km_pixel_rot[1]}}) : osd_vcnt[2:0]];
		osd_de[2:1] <= osd_de[1:0];
	end
end

reg [23:0] rdout;
assign dout = rdout;

always @(posedge clk_video) begin
	reg [23:0] ordout1, nrdout1, rdout2, rdout3;
	reg de1,de2,de3;
	reg osd_mux;
	reg vs1,vs2,vs3;
	reg hs1,hs2,hs3;

	nrdout1 <= din;
	ordout1 <= {{osd_pixel, osd_pixel, OSD_COLOR[2], din[23:19]},// 23:16
	            {osd_pixel, osd_pixel, OSD_COLOR[1], din[15:11]},// 15:8
	            {osd_pixel, osd_pixel, OSD_COLOR[0], din[7:3]}}; //  7:0

	osd_mux <= ~osd_de[2];
	rdout2  <= osd_mux ? nrdout1 : ordout1;
	rdout3  <= rdout2;

	de1 <= de_in; de2 <= de1; de3 <= de2;
	hs1 <= hs_in; hs2 <= hs1; hs3 <= hs2;
	vs1 <= vs_in; vs2 <= vs1; vs3 <= vs2;

	rdout   <= rdout3;
	de_out  <= de3;
	hs_out  <= hs3;
	vs_out  <= vs3;
end

endmodule
