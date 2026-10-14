// SPDX-License-Identifier: GPL-3.0-or-later
// Fixed 1080p viewport using the same aspect/custom-size semantics as MiSTer.
// Calculate infrequent settings with upstream serial arithmetic, keeping a
// divider off the pixel path. Feed the completed box through frame_config_cdc.
module km_viewport(
    input wire clk, resetn,
    input wire [12:0] aspect_x, aspect_y,
    input wire [12:0] custom_ar1x, custom_ar1y, custom_ar2x, custom_ar2y,
    input wire [11:0] hsize, vsize,
    input wire free_scale,
    output reg [11:0] hmin,hmax,vmin,vmax
);
    reg [3:0] state;
    reg [11:0] ax,ay,limit_w,limit_h,w,h;
    reg direct_size, stretch;
    reg start;
    wire busy;
    reg [11:0] mul1,mul2,divisor;
    wire [23:0] quotient;
    wire [12:0] selected_x=aspect_y!=0 ? aspect_x :
        aspect_x==1 ? custom_ar1x : aspect_x==2 ? custom_ar2x : 13'd0;
    wire [12:0] selected_y=aspect_y!=0 ? aspect_y :
        aspect_x==1 ? custom_ar1y : aspect_x==2 ? custom_ar2y : 13'd0;
    function automatic [11:0] bounded(input [23:0] value,input [11:0] maximum);
        bounded=value==0 ? 12'd1 : value>maximum ? maximum : value[11:0];
    endfunction
    sys_umuldiv #(12,12,12) arithmetic(.clk(clk),.start(start),.busy(busy),
        .mul1(mul1),.mul2(mul2),.div(divisor),.result(quotient),.remainder());
    always @(posedge clk) begin
        if(!resetn) begin
            state<=0;start<=0;hmin<=0;hmax<=1919;vmin<=0;vmax<=1079;
            ax<=0;ay<=0;limit_w<=1920;limit_h<=1080;w<=1920;h<=1080;
            direct_size<=0;stretch<=0;mul1<=0;mul2<=0;divisor<=1;
        end else begin
            start<=0;
            case(state)
                0: begin
                    ax<=selected_x[11:0];ay<=selected_y[11:0];
                    direct_size<=selected_x[12] | selected_y[12];stretch<=free_scale;
                    limit_w<=hsize!=0 && hsize<1920 ? hsize : 12'd1920;
                    limit_h<=vsize!=0 && vsize<1080 ? vsize : 12'd1080;
                    state<=1;
                end
                1: begin
                    if(stretch || ax==0 || ay==0) begin w<=limit_w;h<=limit_h;state<=7;end
                    else if(direct_size) begin
                        w<=bounded({12'd0,ax},limit_w);h<=bounded({12'd0,ay},limit_h);state<=7;
                    end else begin mul1<=limit_h;mul2<=ax;divisor<=ay;start<=1;state<=2;end
                end
                2: state<=3;
                3: if(!busy) begin
                    w<=bounded(quotient,limit_w);
                    mul1<=limit_w;mul2<=ay;divisor<=ax;start<=1;state<=4;
                end
                4: state<=5;
                5: if(!busy) begin h<=bounded(quotient,limit_h);state<=7;end
                7: begin
                    hmin<=(1920-w)>>1;hmax<=((1920-w)>>1)+w-1'b1;
                    vmin<=(1080-h)>>1;vmax<=((1080-h)>>1)+h-1'b1;
                    state<=0;
                end
                default: state<=0;
            endcase
        end
    end
endmodule
