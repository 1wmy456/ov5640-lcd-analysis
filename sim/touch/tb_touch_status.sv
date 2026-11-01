`timescale 1ns/1ps
module tb_touch_status;
 reg clk=0;always #5 clk=~clk;reg resetn=0,iv=0;reg [23:0] data=0;reg [0:0] sof=0;reg last=0;reg [31:0] control=0;
 wire ready,ov,ol;wire [23:0] out;wire [0:0] os;
 axis_touch_cross #(.IMAGE_WIDTH(64),.IMAGE_HEIGHT(24)) dut(clk,resetn,data,iv,ready,sof,last,out,ov,1'b1,os,ol,control);
 integer received=0,checks=0,f,n,x,y,state;reg [23:0] c,expected;
 always @(posedge clk)if(resetn&&ov)begin
  n=received%1536;state=received/1536;x=n%64;y=n/64;c=state==0?24'hffff00:state==1?24'h00ff00:24'hff0000;
  if(os!==(n==0)||ol!==(x==63))$fatal(1,"status flags");
  if(x<8||x>=56||y<8||y>=17)begin
   checks++;if(out!==(24'h120000+state*4096+n))$fatal(1,"status outside region");
  end else if((y==8&&(x==8||x==9||x==48))||(y==14&&x==10)||x==13)begin
   if(x==13)expected=0;
   else if(x==48)expected=state==0?c:0;
   else if(y==14)expected=c;
   else if(x==8)expected=state==0?0:c;
   else expected=state==2?0:c;
   checks++;if(out!==expected)$fatal(1,"status glyph state=%d x=%d y=%d got=%h expected=%h",state,x,y,out,expected);
  end
  received++;
 end
 initial begin
  repeat(5)@(negedge clk);resetn=1;
  for(f=0;f<3;f++)begin
   control=32'h10000000|(f<<20);
   for(integer p=0;p<1536;p++)begin @(negedge clk);iv=1;data=24'h120000+f*4096+p;sof=p==0;last=p%64==63;end
  end
  @(negedge clk);iv=0;repeat(4)@(negedge clk);
  if(received!=4608)$fatal(1,"status pixel count");
  $display("PASS TOUCH_STATUS checks=%0d SELECT/TRACK/LOST glyph/color/outside-region/flags",checks);$finish;
 end
endmodule
