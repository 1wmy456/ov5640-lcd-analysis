`timescale 1ns/1ps
module tb_component_video;
 localparam W=16,H=12;
 reg clk=0;always #5 clk=~clk;
 reg rst=0,sv=0,su=0,sl=0,ready=1;reg[23:0] sd=0;
 wire sr,mv,mu,ml;wire[23:0] md;
 wire ms,mwv,mfd;wire[9:0] ma;wire[31:0] mw;
 wire raw_valid,rp,err;wire[15:0] x0,x1,y0,y1;wire[31:0] bc;
 wire dv;wire[15:0] dx0,dx1,dy0,dy1;
 axis_blue_tracker #(.IMAGE_WIDTH(W),.IMAGE_HEIGHT(H),.MODE(2),.MIN_PIXELS(1),.MIN_WIDTH(1),.MIN_HEIGHT(1),.COMPONENT_MODE(1)) video(
 .aclk(clk),.aresetn(rst),.s_axis_tdata(sd),.s_axis_tvalid(sv),.s_axis_tready(sr),.s_axis_tuser(su),.s_axis_tlast(sl),
 .m_axis_tdata(md),.m_axis_tvalid(mv),.m_axis_tready(ready),.m_axis_tuser(mu),.m_axis_tlast(ml),
 .bbox_valid(raw_valid),.result_pulse(rp),.frame_error(err),.bbox_xmin(x0),.bbox_xmax(x1),.bbox_ymin(y0),.bbox_ymax(y1),.blue_pixel_count(bc),
 .mask_start(ms),.mask_word_valid(mwv),.mask_frame_done(mfd),.mask_word_address(ma),.mask_word_data(mw),
 .display_bbox_valid(dv),.display_xmin(dx0),.display_xmax(dx1),.display_ymin(dy0),.display_ymax(dy1));
 reg[11:0] aw=0,ar=0;reg av=0,wv=0,br=0,arv=0,rrdy=0;reg[31:0] wd=0;reg[3:0] ws=15;
 wire awr,wr,bv,arr,rv;wire[31:0] rd;wire[1:0] bp,rr;
 pan_tilt_ctrl #(.CLOCK_HZ(1000000),.IMAGE_WIDTH(W),.IMAGE_HEIGHT(H),.COMPONENT_MODE(1)) ctrl(
 .s_axi_aclk(clk),.s_axi_aresetn(rst),.s_axi_awaddr(aw),.s_axi_awprot(3'd0),.s_axi_awvalid(av),.s_axi_awready(awr),
 .s_axi_wdata(wd),.s_axi_wstrb(ws),.s_axi_wvalid(wv),.s_axi_wready(wr),.s_axi_bresp(bp),.s_axi_bvalid(bv),.s_axi_bready(br),
 .s_axi_araddr(ar),.s_axi_arprot(3'd0),.s_axi_arvalid(arv),.s_axi_arready(arr),.s_axi_rdata(rd),.s_axi_rresp(rr),.s_axi_rvalid(rv),.s_axi_rready(rrdy),
 .bbox_valid(raw_valid),.result_pulse(rp),.frame_error(err),.bbox_xmin(x0),.bbox_xmax(x1),.bbox_ymin(y0),.bbox_ymax(y1),.blue_pixel_count(bc),
 .mask_start(ms),.mask_word_valid(mwv),.mask_frame_done(mfd),.mask_word_address(ma),.mask_word_data(mw),
 .display_bbox_valid(dv),.display_xmin(dx0),.display_xmax(dx1),.display_ymin(dy0),.display_ymax(dy1));
 integer checks=0,accepted=0,outputs=0,head=0,tail=0,stalls=0,green=0,tbx=0,tby=0;
 reg[25:0] fifo[0:8191];reg outstall=0,bstall=0,rstall=0;reg[25:0] held;reg[1:0] bh;reg[33:0] rh;
 reg frame_dv=0;integer fx0,fx1,fy0,fy1;
 reg[31:0] rng=32'h475346;
 task check(input bit ok,input string msg);begin checks++;if(!ok)begin $display("FAIL COMPONENT %s t=%0t",msg,$time);$fatal(1);end end endtask
 always @(negedge clk)begin rng={rng[30:0],rng[31]^rng[21]^rng[1]^rng[0]};ready=rng[1:0]!=0;end
 always @(posedge clk)if(rst)begin
  if(outstall)check(mv&&{mu,ml,md}===held,"video stable under backpressure");
  outstall=mv&&!ready;held={mu,ml,md};if(outstall)stalls++;
  if(bstall)check(bv&&bp===bh,"B stable");bstall=bv&&!br;bh=bp;
  if(rstall)check(rv&&{rr,rd}===rh,"R stable");rstall=rv&&!rrdy;rh={rr,rd};
  if(mv&&ready)begin check(head<tail,"no extra video");check({mu,ml,md}===fifo[head],"pixel/SOF/EOL alignment, frame-latched overlay");head++;outputs++;if(md==24'h00ff00)green++;end
  if(sv&&sr)begin
   reg paint;reg[23:0] expected;
   if(su)begin tbx=0;tby=0;frame_dv=dv&&!video.frame_open;fx0=dx0;fx1=dx1;fy0=dy0;fy1=dy1;end
   paint=frame_dv&&tbx>=fx0&&tbx<=fx1&&tby>=fy0&&tby<=fy1&&
     ((tbx-fx0<2)||(fx1-tbx<2)||(tby-fy0<2)||(fy1-tby<2))&&sl==(tbx==W-1);
   expected=paint?24'h00ff00:sd;fifo[tail]={su,sl,expected};tail++;accepted++;
   if(sl)begin tbx=0;tby++;end else tbx++;
  end
 end
 task send_aw(input integer a);begin @(negedge clk);aw=a;av=1;do @(posedge clk);while(!awr);@(negedge clk);av=0;end endtask
 task send_w(input integer value,strobe);begin @(negedge clk);wd=value;ws=strobe;wv=1;do @(posedge clk);while(!wr);@(negedge clk);wv=0;end endtask
 task write_reg(input integer a,value,strobe,order);
 begin
  if(order==0)begin send_aw(a);repeat(3)@(negedge clk);send_w(value,strobe);end
  else if(order==1)begin send_w(value,strobe);repeat(2)@(negedge clk);send_aw(a);end
  else fork send_aw(a);send_w(value,strobe);join
  wait(bv);repeat(4)@(negedge clk);check(bp==0,"write OK");br=1;@(posedge clk);@(negedge clk);br=0;
 end endtask
 task read_reg(input integer a,expected,response);
 begin
  @(negedge clk);ar=a;arv=1;do @(posedge clk);while(!arr);@(negedge clk);arv=0;
  wait(rv);repeat(7)@(negedge clk);
  if(rd!==expected||rr!=response)$display("READ a=%h got=%h response=%h expected=%h/%h",a,rd,rr,expected,response);
  check(rd===expected&&rr==response,"AXI read");rrdy=1;@(posedge clk);@(negedge clk);rrdy=0;
 end endtask
 task beat(input bit blue,sof,eol);
 begin
  @(negedge clk);sd=blue?24'h1020c8:24'h302010;su=sof;sl=eol;sv=1;
  do @(posedge clk);while(!sr);
  @(negedge clk);sv=0;
  if(rng[2])@(negedge clk);
 end endtask
 task frame(input [11:0] bits);
 begin
  for(integer yy=0;yy<H;yy++)for(integer xx=0;xx<W;xx++)beat(bits[(yy/4)*4+xx/4],xx==0&&yy==0,xx==W-1);
  repeat(8)@(negedge clk);
 end endtask
 task select_box(input integer xmin,xmax,ymin,ymax,frameid,valid);
 begin
  write_reg('h100,(xmax<<16)|xmin,15,0);write_reg('h104,(ymax<<16)|ymin,15,1);
  write_reg('h10c,frameid,15,2);write_reg('h110,valid,15,0);write_reg('h114,1,1,1);
 end endtask
 initial begin
  repeat(5)@(negedge clk);rst=1;
  read_reg(4,'h10100,0);read_reg('hfc,'h43434c31,0);read_reg('he8,1,0);read_reg('h200,0,2);
  frame('hA35);write_reg('hd0,1,0,0);read_reg('hd0,0,0); // WSTRB ignored
  write_reg('hd0,1,1,1);read_reg('hd4,1,0);read_reg('hd8,5,0);read_reg('h200,'hA35,0);
  fork
   begin frame('h123);frame('h456);frame('h789);end
   begin repeat(3)read_reg('h200,'hA35,0);end
  join
  read_reg('h200,'hA35,0);read_reg('hd4,1,0); // PS snapshot survived newer captures
  write_reg('hd0,0,1,2);write_reg('hd0,1,1,0);read_reg('hd4,4,0);read_reg('h200,'h789,0);
  select_box(0,7,0,7,4,1);read_reg('h118,1,0);
  frame(0);check(green>0,"selected rectangle visible");
  fork
   frame(0);
   begin wait(tby==3);select_box(8,15,4,11,4,1);end
  join
  frame(0); // scoreboard verifies that mid-frame writes only apply at the next SOF
  beat(1,1,0);beat(1,0,1);repeat(5)@(negedge clk);
  read_reg('h118,0,0);read_reg('hf0,1,0);
  frame('hABC);select_box(0,7,0,7,4,1);read_reg('h118,0,0); // stale error epoch rejected
  write_reg('hd0,0,1,0);write_reg('hd0,1,1,1);read_reg('hd8,5,0);
  // 8 complete frames: IDs 1..7 plus the clean frame after malformed input.
  read_reg('hd4,8,0);read_reg('h200,'hABC,0);
  select_box(0,7,0,7,8,1);read_reg('h118,1,0);
  repeat(250010)@(negedge clk);read_reg('h118,0,0); // expired CPU result cannot keep a stale box
  write_reg('hd0,0,1,0);
  // Last cell qualifies only on the frame's final accepted pixel.
  for(integer yy=0;yy<H;yy++)for(integer xx=0;xx<W;xx++)beat(yy==H-1&&xx>=W-4,xx==0&&yy==0,xx==W-1);
  repeat(8)@(negedge clk);write_reg('hd0,1,1,0);read_reg('h200,'h800,0);
  repeat(4)@(negedge clk);check(head==tail&&accepted==outputs&&stalls>0,"all video accepted once and drained");
  $display("PASS COMPONENT_VIDEO checks=%0d accepted=%0d outputs=%0d stalls=%0d green=%0d triple-bank/AXI/overlay/error/stale/last-pixel",checks,accepted,outputs,stalls,green);$finish;
 end
 initial begin #10000000;$display("FAIL COMPONENT watchdog");$fatal(1);end
endmodule
