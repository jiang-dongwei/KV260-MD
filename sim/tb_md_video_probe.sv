`timescale 1ns/1ps
module tb_md_video_probe;
 reg clk=0;always #5 clk=~clk;
 reg reset=1,ce=0,hb=1,vb=1;
 reg [3:0] r=0,g=0,b=0;
 reg sce=0,shb=1,svb=1;
 reg [7:0] sr=0,sg=0,sb=0;
 wire [31:0] value;
 reg axi_clk=0;always #3.7 axi_clk=~axi_clk;
 wire [31:0] snapshot;wire changed;
 km_frame_config_cdc #(.WIDTH(32),.FRAME_BOUNDARY(0)) video_snapshot(
  .src_clk(clk),.src_resetn(!reset),.src_data(value),.src_busy(),
  .dst_clk(axi_clk),.dst_resetn(!reset),.dst_frame(1'b0),
  .dst_data(snapshot),.dst_changed(changed));
 function automatic bit allowed(input [31:0] word);
  allowed=word=={4'hc,10'd256,10'd256,8'ha5} || word=={4'hd,10'd256,10'd256,8'h5a} ||
   word=={4'hc,10'd320,10'd320,8'ha5} || word=={4'hd,10'd320,10'd320,8'h5a} ||
   word=={4'he,10'd256,9'd3,9'd0} || word=={4'he,10'd320,9'd3,9'd1} ||
   word=={4'hf,10'd256,9'd3,9'd3} || word=={4'hf,10'd320,9'd3,9'd3};
 endfunction
 always @(negedge axi_clk) if(!reset && changed && snapshot!=0 && !allowed(snapshot))
  $fatal(1,"torn or unexpected diagnostic snapshot: %h",snapshot);
 km_md_video_probe dut(clk,reset,ce,hb,vb,r,g,b,sce,shb,svb,sr,sg,sb,value);
 // Intentionally swap R/G after a clock delay: the stream must report its own
 // colors and its own three bad rows rather than borrowing the native result.
 always @(posedge clk) begin sce<=ce;shb<=hb;svb<=vb;sr<={g,g};sg<={r,r};sb<={b,b};end
 task pixel(input integer x,input integer width,input bit vertical,input bit corrupt);
 begin
  @(negedge clk);ce=1;hb=x>=width;vb=vertical;
  r=x<width/2 ? 14 : 0;g=x>=width/2 && x<width ? 14 : 0;b=x>=width ? 14 : 0;
  if(corrupt) begin r=0;g=0;b=14;end
  @(negedge clk);ce=0;repeat(8) @(negedge clk);
 end endtask
 reg [31:0] expected;
 initial begin
  repeat(3) @(negedge clk);reset=0;
  for(integer width=256;width<=320;width+=64) begin
   for(integer frame=0;frame<4;frame++) begin
    // VDP may release VBL inside a line: exclude this seven-pixel tail.
    if(width!=256 || frame!=0) begin
     pixel(width-8,width,1,0);
     for(integer x=width-7;x<width;x++) pixel(x,width,0,0);
     pixel(width,width,0,0);
    end
    for(integer line=0;line<3;line++)
     for(integer x=0;x<width+85;x++)
      pixel(x,width,0,width==320 && frame==2 && line==1 && x==17);
    pixel(width,width,1,0);repeat(3) @(negedge clk);
    case(frame)
     0: expected={4'hc,10'(width),10'(width),8'ha5};
     1: expected={4'hd,10'(width),10'(width),8'h5a};
     2: expected={4'he,10'(width),9'd3,9'(width==320 ? 1 : 0)};
     3: expected={4'hf,10'(width),9'd3,9'd3};
    endcase
    if(value!==expected) $fatal(1,"probe wrong: %h != %h width %d frame %d",value,expected,width,frame);
    repeat(30) @(negedge clk);
    if(snapshot!==value) $fatal(1,"mailbox failed to commit held word: %h != %h",snapshot,value);
    if(value!==expected) $fatal(1,"probe did not hold");
   end
  end
  $display("PASS video probe: full-frame clean/corrupt-row counts, independent stream and coherent unequal-clock mailbox");$finish;
 end
endmodule
