`timescale 1ns/1ps
module tb_mask_words;
 reg clk=0;always #5 clk=~clk;
 reg rst=0,accept=0,sof=0,eol=0,blue=0;reg[15:0] x=0,y=0;
 wire start,wvalid,done;wire[9:0] address;wire[31:0] data;
 blue_mask_sampler #(.IMAGE_WIDTH(40),.IMAGE_HEIGHT(16)) dut(
 .clk(clk),.resetn(rst),.accept(accept),.sof(sof),.eol(eol),.is_blue(blue),.pixel_valid(1'b1),.x(x),.y(y),
 .mask_start(start),.mask_word_valid(wvalid),.mask_frame_done(done),.mask_word_address(address),.mask_word_data(data));
 reg[39:0] expected;integer checks=0,words=0,frames=0;
 task check(input bit ok,input string msg);begin checks++;if(!ok)begin $display("FAIL MASK_WORDS %s addr=%0d data=%h expected=%h",msg,address,data,expected);$fatal(1);end end endtask
 always @(posedge clk)if(rst)begin
  if(wvalid)begin
   check(address==words,"word index");
   check(data==(address==0?expected[31:0]:{24'd0,expected[39:32]}),"32-bit pack and final partial word");words++;
  end
  if(done)begin check(words==2,"complete only after both words");frames++;end
 end
 task frame(input[39:0] pattern,input integer count);
 begin
  expected=pattern;words=0;
  for(integer yy=0;yy<16;yy++)for(integer xx=0;xx<40;xx++)begin
   @(negedge clk);accept=1;x=xx;y=yy;sof=xx==0&&yy==0;eol=xx==39;
   blue=pattern[(yy/4)*10+xx/4]&&((xx%4+4*(yy%4)<count-1)||(xx%4==3&&yy%4==3));
   @(posedge clk);@(negedge clk);accept=0;
   if((xx+yy)%3==0)repeat(2)@(negedge clk);
  end
  repeat(3)@(negedge clk);check(words==2,"all words seen");
 end endtask
 initial begin
  repeat(3)@(negedge clk);rst=1;
  frame(40'hAB12345678,16);frame(0,16);
  frame(40'hFFFFFFFFFF,4); // every cell qualifies only on its final pixel
  frame(40'h8000000000,4); // last frame pixel makes the last cell foreground
  check(frames==4,"frame coverage");$display("PASS MASK_WORDS checks=%0d frames=%0d multiple-words/partial-last/reset-cells/bubbles/final-pixel",checks,frames);$finish;
 end
 initial begin #1000000;$fatal(1,"mask watchdog");end
endmodule
