// SPDX-License-Identifier: GPL-3.0-or-later
// Portable subset of MiSTer sys_top's UIO system commands, preserving word
// ordering. Fixed 1080p60 output, nearest-neighbor scaling, 32-bit host FB.
// Framebuffer descriptors commit atomically after all ten words validate.
module km_sys_io (
    input wire clk, input wire resetn,
    input wire io_uio, input wire io_strobe, input wire [15:0] io_din,
    output reg [15:0] io_dout,
    input wire output_vs, input wire native_vs,
    input wire [12:0] aspect_x, input wire [12:0] aspect_y,
    output reg vs_wait, output reg [15:0] cfg,
    output reg [4:0] volume_attenuation, output reg [15:0] leds,
    output reg [11:0] hsize, output reg [11:0] vsize, output reg free_scale,
    output reg [12:0] custom_ar1x, custom_ar1y, custom_ar2x, custom_ar2y,
    output reg fb_enable, output reg [5:0] fb_format,
    output reg [31:0] fb_base, output reg [11:0] fb_width, fb_height,
    output reg [11:0] fb_hmin, fb_hmax, fb_vmin, fb_vmax,
    output reg [13:0] fb_stride, output reg fb_changed, output reg fb_error
);
    reg has_cmd;
    reg [7:0] cmd, count, frames;
    reg [15:0] staging [0:8];
    (* ASYNC_REG="TRUE" *) reg [1:0] output_vs_sync, native_vs_sync;
    reg old_output_vs, old_native_vs;
    wire [31:0] requested_base={staging[2],staging[1]};
    wire [31:0] requested_bytes={18'd0,io_din[13:0]} * {20'd0,staging[4][11:0]};
    wire [32:0] requested_end={1'b0,requested_base}+{1'b0,requested_bytes};
    wire valid_descriptor = staging[0][15] &&
        (staging[0][5:0] == 6'h06 || staging[0][5:0] == 6'h16) &&
        requested_base >= 32'h20000000 && requested_base[1:0] == 0 &&
        requested_end <= 33'h040000000 &&
        staging[3] > 0 && staging[3] <= 1920 &&
        staging[4] > 0 && staging[4] <= 1080 &&
        staging[5] <= staging[6] && staging[6] < 1920 &&
        staging[7] <= staging[8] && staging[8] < 1080 &&
        io_din[15:14] == 0 && io_din[1:0] == 0 &&
        {2'd0,io_din[13:0]} >= (staging[3] << 2);
    wire [7:0] fb_crc = {fb_enable,fb_enable,fb_format} ^
        fb_width[7:0] ^ {4'd0,fb_width[11:8]} ^ fb_height[7:0] ^ {4'd0,fb_height[11:8]} ^
        aspect_x[7:0] ^ {3'd0,aspect_x[12:8]} ^ aspect_y[7:0] ^ {3'd0,aspect_y[12:8]};

    always @(posedge clk) begin
        if (!resetn) begin
            has_cmd<=0; cmd<=0; count<=0; io_dout<=0; vs_wait<=0; cfg<=0;
            frames<=0; output_vs_sync<=0; native_vs_sync<=0;
            old_output_vs<=0; old_native_vs<=0; volume_attenuation<=31; leds<=0;
            hsize<=0; vsize<=0; free_scale<=0;
            custom_ar1x<=0; custom_ar1y<=0; custom_ar2x<=0; custom_ar2y<=0;
            fb_enable<=0; fb_format<=0; fb_base<=0; fb_width<=0; fb_height<=0;
            fb_hmin<=0; fb_hmax<=0; fb_vmin<=0; fb_vmax<=0; fb_stride<=0;
            fb_changed<=0; fb_error<=0;
            for(integer i=0;i<9;i=i+1) staging[i]<=0;
        end else begin
            output_vs_sync<={output_vs_sync[0],output_vs};
            native_vs_sync<={native_vs_sync[0],native_vs};
            old_output_vs<=output_vs_sync[1]; old_native_vs<=native_vs_sync[1];
            if(output_vs_sync[1] && !old_output_vs) vs_wait<=0;
            if(native_vs_sync[1] && !old_native_vs) frames<=frames+1'b1;
            fb_changed<=0;
            if(!io_uio) begin
                has_cmd<=0; cmd<=0; count<=0; io_dout<=0;
            end else if(io_strobe) begin
                io_dout<=0;
                if(!has_cmd) begin
                    has_cmd<=1; cmd<=io_din[7:0]; count<=0;
                    case(io_din[7:0])
                        8'h2f: io_dout<=1;
                        8'h30: vs_wait<=1;
                        8'h40: io_dout<={8'd0,fb_crc};
                        8'h42: io_dout<={7'd0,1'b1,frames};
                        // 20/2b/39/3e/44 return zero: no pixel repetition,
                        // VRR, custom filters, audio EQ or shadowmask capability.
                        default: ;
                    endcase
                end else begin
                    if(count != 255) count<=count+1'b1;
                    case(cmd)
                        8'h01: cfg<=io_din;
                        8'h25: leds<=io_din;
                        8'h26: volume_attenuation<=io_din[4:0];
                        8'h27: vsize<=io_din[11:0];
                        8'h37: begin hsize<=io_din[11:0]; free_scale<=io_din[15]; end
                        8'h3a: case(count)
                            0: custom_ar1x<=io_din[12:0];
                            1: custom_ar1y<=io_din[12:0];
                            2: custom_ar2x<=io_din[12:0];
                            3: custom_ar2y<=io_din[12:0];
                            default: ;
                        endcase
                        8'h2f: begin
                            if(count < 9) staging[count]<=io_din;
                            if(count == 0 && !io_din[15]) begin
                                fb_enable<=0; fb_changed<=1; fb_error<=0;
                            end
                            if(count == 9) begin
                                if(valid_descriptor) begin
                                    fb_enable<=1; fb_format<=staging[0][5:0];
                                    fb_base<=requested_base;
                                    fb_width<=staging[3][11:0]; fb_height<=staging[4][11:0];
                                    fb_hmin<=staging[5][11:0]; fb_hmax<=staging[6][11:0];
                                    fb_vmin<=staging[7][11:0]; fb_vmax<=staging[8][11:0];
                                    fb_stride<=io_din[13:0]; fb_changed<=1; fb_error<=0;
                                end else fb_error<=1;
                            end
                        end
                        8'h40: case(count)
                            0: io_dout<={3'd0,aspect_x};
                            1: io_dout<={3'd0,aspect_y};
                            2: io_dout<={8'd0,fb_enable,fb_enable,fb_format};
                            3: io_dout<={4'd0,fb_width};
                            4: io_dout<={4'd0,fb_height};
                            5: io_dout<=fb_base[15:0];
                            6: io_dout<=fb_base[31:16];
                            7: io_dout<={2'd0,fb_stride};
                            default: ;
                        endcase
                        default: ;
                    endcase
                end
            end
        end
    end
endmodule
