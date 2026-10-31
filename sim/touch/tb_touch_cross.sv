`timescale 1ns/1ps
module tb_touch_cross;
 reg clk=0;always #5 clk=~clk;
 reg resetn=0,iv=0,ready=0;reg [23:0] data;reg [0:0] user;reg last;
 reg [31:0] marker=0;wire ir,ov;wire [23:0] od;wire [0:0] ou;wire ol;
 axis_touch_cross #(.IMAGE_WIDTH(32),.IMAGE_HEIGHT(24)) dut(clk,resetn,data,iv,ir,user,last,od,ov,ready,ou,ol,marker);
 reg [25:0] expected[0:4095];integer wr=0,rd=0,checks=0,stalls=0;
 integer x=0,y=0,mx,my,dx,dy;reg [31:0] held=0,chosen;reg hit,stall=0;reg [25:0] saved;
 always @(posedge clk)if(resetn)begin
  if(stall)begin checks=checks+1;if(!ov||{od,ou,ol}!==saved)$fatal(1,"backpressure stability");end
  stall=ov&&!ready;saved={od,ou,ol};if(stall)stalls=stalls+1;
  if(ov&&ready)begin
   checks=checks+1;if(rd>=wr||{od,ou,ol}!==expected[rd])$fatal(1,"pixel/flags mismatch %d",rd);rd=rd+1;
  end
  if(iv&&ir)begin
   if(user[0])begin x=0;y=0;held=marker;end
   chosen=held;mx=chosen[9:0];my=chosen[18:10];dx=x>mx?x-mx:mx-x;dy=y>my?y-my:my-y;
   hit=chosen[31]&&mx<32&&my<24&&((dx<=12&&dy<=1)||(dy<=12&&dx<=1));
   expected[wr]={hit?24'hff00ff:data,user,last};wr=wr+1;
   if(last)begin x=0;y=y+1;end else x=x+1;
  end
 end
 always @(negedge clk)if(resetn)ready=($urandom_range(0,3)!=0);
 task send(input integer f,input integer n);
 begin
  repeat($urandom_range(0,2))begin @(negedge clk);iv=0;end
  @(negedge clk);iv=1;data=(f*768+n)^24'h123456;user=(n==0);last=(n%32==31);
  if(n==300)marker=32'h80000000|(10<<10)|5; // must only affect next frame
  do @(posedge clk);while(!ir);
  @(negedge clk);iv=0;
 end endtask
 integer f,n;
 initial begin
  repeat(5)@(negedge clk);resetn=1;
  for(f=0;f<4;f=f+1)begin
   marker=f==0?0:f==1?(32'h80000000|(12<<10)|16):f==2?32'h80000000:(32'h80000000|(23<<10)|31);
   for(n=0;n<768;n=n+1)send(f,n);
  end
  wait(rd==wr);repeat(5)@(negedge clk);
  if(wr!=3072||stalls==0)$fatal(1,"coverage");
  $display("PASS TOUCH_CROSS checks=%0d pixels=%0d stalls=%0d random-valid/ready frame-latch bypass edge flags",checks,wr,stalls);$finish;
 end
 initial begin #1000000;$fatal(1,"timeout");end
endmodule
