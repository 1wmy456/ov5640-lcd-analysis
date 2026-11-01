`timescale 1ns/1ps
module tb_touch_feedback;
 reg clk=0;always #5 clk=~clk;reg resetn=0;
 reg [11:0] aw=0,ar=0;reg av=0,wv=0,br=0,arv=0,rrdy=0;reg [31:0] wd=0;reg [3:0] ws=15;
 wire awr,wr,bv,arr,rv,valid;wire [31:0] rd;wire [1:0] bp,rp;
 reg [31:0] frame=0;reg raw_valid=0,pulse=0,error=0,mask_start=0,mask_done=0;
 pan_tilt_ctrl #(.CLOCK_HZ(1000000),.COMPONENT_MODE(1),.TOUCH_MODE(1)) dut(
 .s_axi_aclk(clk),.s_axi_aresetn(resetn),.s_axi_awaddr(aw),.s_axi_awprot(3'd0),.s_axi_awvalid(av),.s_axi_awready(awr),
 .s_axi_wdata(wd),.s_axi_wstrb(ws),.s_axi_wvalid(wv),.s_axi_wready(wr),.s_axi_bresp(bp),.s_axi_bvalid(bv),.s_axi_bready(br),
 .s_axi_araddr(ar),.s_axi_arprot(3'd0),.s_axi_arvalid(arv),.s_axi_arready(arr),.s_axi_rdata(rd),.s_axi_rresp(rp),.s_axi_rvalid(rv),.s_axi_rready(rrdy),
 .bbox_valid(1'b0),.result_pulse(1'b0),.frame_error(error),.bbox_xmin(16'd0),.bbox_xmax(16'd0),.bbox_ymin(16'd0),.bbox_ymax(16'd0),.blue_pixel_count(32'd0),
 .mask_start(mask_start),.mask_word_valid(1'b0),.mask_frame_done(mask_done),.mask_word_address(10'd0),.mask_word_data(32'd0),
 .raw_result_frame(frame),.raw_result_valid(raw_valid),.raw_result_pulse(pulse),.display_bbox_valid(valid));
 integer checks=0;
 task check(input bit v);begin checks++;if(!v)$fatal(1,"feedback check %d",checks);end endtask
 task write(input [11:0] address,input [31:0] value);
 begin
  @(negedge clk);aw=address;av=1;do @(posedge clk);while(!awr);@(negedge clk);av=0;
  repeat(2)@(negedge clk);wd=value;wv=1;do @(posedge clk);while(!wr);@(negedge clk);wv=0;
  wait(bv);repeat(2)@(negedge clk);check(bp==0);br=1;@(posedge clk);@(negedge clk);br=0;
 end endtask
 task read(input [11:0] address,input [31:0] value);
 begin
  @(negedge clk);ar=address;arv=1;do @(posedge clk);while(!arr);@(negedge clk);arv=0;
  wait(rv);repeat(2)@(negedge clk);check(rp==0&&rd===value);rrdy=1;@(posedge clk);@(negedge clk);rrdy=0;
 end endtask
 task result(input [31:0] id,input bit v);
 begin
  @(posedge clk);frame<=id;raw_valid<=v;pulse<=1;mask_start<=1;
  @(posedge clk);pulse<=0;mask_start<=0;mask_done<=1;
  @(posedge clk);mask_done<=0;repeat(2)@(negedge clk);
 end endtask
 task commit(input [31:0] id,input [31:0] flags);
 begin write('h100,(439<<16)|360);write('h104,(267<<16)|212);write('h10c,id);write('h110,flags);write('h114,1);end endtask
 initial begin
  repeat(5)@(negedge clk);resetn=1;
  result(99,1);read('h128,99);read('h12c,1);
  commit(99,3);check(valid); // raw target succeeds even without any blue mask snapshot
  commit(98,3);check(!valid); // wrong raw frame cannot paint
  commit(99,1);check(!valid); // legacy still requires its own mask provenance
  commit(99,3);check(valid);
  result(100,0);commit(100,3);check(!valid);
  result(101,1);commit(101,3);check(valid);
  @(negedge clk);error=1;@(negedge clk);error=0;check(!valid);
  commit(101,3);check(!valid); // an intervening source error invalidates raw provenance
  result(102,1);commit(102,3);check(valid);
  repeat(250010)@(negedge clk);check(!valid);commit(102,3);check(!valid);
  read(8,0);$display("PASS TOUCH_FEEDBACK checks=%0d registered-frame/matching/error/age/legacy-isolation/PWM-off",checks);$finish;
 end
 initial begin #5000000;$fatal(1,"timeout");end
endmodule
