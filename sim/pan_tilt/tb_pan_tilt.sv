`timescale 1ns/1ps
module tb_pan_tilt;
 reg clk=0;always #500 clk=~clk; // parameterized 1MHz: 20,000 cycles/20ms
 reg rst=0;
 reg [11:0] aw=0,ar=0;reg av=0,wv=0,br=0,rvready=0,arv=0;
 reg [31:0] wd=0;reg[3:0] ws=15;wire awr,wr,bv,arr,rv;
 wire[31:0] rd;wire[1:0] bp,rr;wire yp,pp;
 reg valid=0,pulse=0,err=0;reg[15:0] x0=0,x1=0,y0=0,y1=0;reg[31:0] count=0;
 pan_tilt_ctrl #(.CLOCK_HZ(1000000)) dut(.s_axi_aclk(clk),.s_axi_aresetn(rst),
 .s_axi_awaddr(aw),.s_axi_awprot(0),.s_axi_awvalid(av),.s_axi_awready(awr),
 .s_axi_wdata(wd),.s_axi_wstrb(ws),.s_axi_wvalid(wv),.s_axi_wready(wr),
 .s_axi_bresp(bp),.s_axi_bvalid(bv),.s_axi_bready(br),
 .s_axi_araddr(ar),.s_axi_arprot(0),.s_axi_arvalid(arv),.s_axi_arready(arr),
 .s_axi_rdata(rd),.s_axi_rresp(rr),.s_axi_rvalid(rv),.s_axi_rready(rvready),
 .bbox_valid(valid),.result_pulse(pulse),.frame_error(err),.bbox_xmin(x0),.bbox_xmax(x1),
 .bbox_ymin(y0),.bbox_ymax(y1),.blue_pixel_count(count),.servo_yaw_pwm(yp),.servo_pitch_pwm(pp));
 integer checks=0;reg bstall=0,rstall=0;reg[1:0] bh;reg[33:0] rh;
 task check(input bit ok,input string s);begin checks++;assert(ok)else begin $display("FAIL %s",s);$fatal(1);end end endtask
 always @(posedge clk)if(rst)begin
  if(bstall)check(bv&&bp===bh,"B stable under backpressure");
  if(rstall)check(rv&&{rr,rd}===rh,"R stable under backpressure");
  bstall=bv&&!br;bh=bp;rstall=rv&&!rvready;rh={rr,rd};
 end else begin bstall=0;rstall=0;end
 task send_aw(input integer a);begin @(negedge clk);aw=a;av=1;do @(posedge clk);while(!awr);@(negedge clk);av=0;end endtask
 task send_w(input integer d,input integer strobes);begin @(negedge clk);wd=d;ws=strobes;wv=1;do @(posedge clk);while(!wr);@(negedge clk);wv=0;end endtask
 task write_reg(input integer a,d,strobes,order,expected);
 begin
  if(order==0)begin send_aw(a);repeat(3)@(negedge clk);send_w(d,strobes);end
  else if(order==1)begin send_w(d,strobes);repeat(4)@(negedge clk);send_aw(a);end
  else fork send_aw(a);send_w(d,strobes);join
  wait(bv);repeat(4)@(negedge clk);check(bp==expected,"write response");
  br=1;@(posedge clk);@(negedge clk);br=0;
 end endtask
 task read_reg(input integer a,expected,response);
 begin
  @(negedge clk);ar=a;arv=1;do @(posedge clk);while(!arr);@(negedge clk);arv=0;
  wait(rv);repeat(3)@(negedge clk);check(rd===expected&&rr==response,"read data/response");
  rvready=1;@(posedge clk);@(negedge clk);rvready=0;
 end endtask
 task publish(input bit v,input integer bx,by,c);
 begin
  @(posedge clk);valid<=v;x0<=bx;x1<=bx+9;y0<=by;y1<=by+7;count<=c;pulse<=1;
  @(posedge clk);pulse<=0;@(negedge clk);
 end endtask
 reg real_clk=0;always #5 real_clk=~real_clk;
 wire real_yaw,real_pitch;reg[1:0] real_en=0;
 dual_servo_pwm real_pwm(.clk(real_clk),.resetn(rst),.enable_request(real_en),.commit(1'b0),
 .yaw_us(16'd1500),.pitch_us(16'd1500),.yaw_min(16'd1400),.yaw_max(16'd1600),.pitch_min(16'd1400),.pitch_max(16'd1600),
 .servo_yaw_pwm(real_yaw),.servo_pitch_pwm(real_pitch));
 integer real_pulses=0;time real_start=0,previous_start=0;
 always @(posedge real_yaw)begin
  real_start=$time;if(previous_start)check($time-previous_start==20000000,"100MHz period exactly 2M cycles");previous_start=$time;
 end
 always @(negedge real_yaw)if(rst&&real_start)begin check($time-real_start==1500000,"100MHz center exactly 150000 cycles");real_pulses++;end
 time yaw_start=0,pitch_start=0;integer yw,pw;
 reg duration_checks=1;
 always @(posedge yp)begin yaw_start=$time;#1;yw=dut.active_yaw;end
 always @(negedge yp)if(rst&&yaw_start&&duration_checks)check($time-yaw_start==yw*1000,"yaw independent pulse width");
 always @(posedge pp)begin pitch_start=$time;#1;pw=dut.active_pitch;end
 always @(negedge pp)if(rst&&pitch_start&&duration_checks)check($time-pitch_start==pw*1000,"pitch independent pulse width");
 initial begin
  repeat(5)@(negedge clk);check(!yp&&!pp,"reset PWM disabled");rst=1;real_en=3;
  read_reg(0,32'h50544c54,0);read_reg(8,0,0);read_reg('h60,(480<<16)|800,0);
  write_reg('h0c,1505,15,0,0);write_reg('h10,1595,15,1,0);write_reg('h34,1,15,2,0);
  read_reg('h14,1500,0);read_reg('h18,1500,0); // not changed mid-period
  write_reg(8,3,1,2,0);wait(dut.applied_sequence==1);@(negedge clk);
  read_reg('h14,1505,0);read_reg('h18,1595,0);
  write_reg('h0c,'h000005c8,1,0,0);read_reg('h0c,1480,0); // WSTRB low byte only
  write_reg('h0c,0,0,1,0);read_reg('h0c,1480,0);
  write_reg('h0c,3000,15,1,0);write_reg('h10,100,15,0,0);write_reg('h34,1,15,2,0);
  wait(dut.applied_sequence==2);@(negedge clk);read_reg('h14,1600,0);read_reg('h18,1400,0);
  write_reg('h1c,1700,15,0,2);read_reg('h1c,1400,0);
  write_reg('h7c,1,15,1,2);read_reg('h7c,0,2);read_reg(1,0,2);
  publish(1,100,50,1234);write_reg('h40,1,1,0,0);
  read_reg('h44,1,0);read_reg('h48,5,0);read_reg('h4c,(109<<16)|100,0);read_reg('h54,1234,0);
  publish(0,200,70,0); // no-target frame still advances frame ID
  read_reg('h44,1,0);read_reg('h4c,(109<<16)|100,0); // old PS snapshot remains coherent
  write_reg('h40,1,1,1,0);read_reg('h44,2,0);read_reg('h48,4,0);read_reg('h54,0,0);
  @(posedge clk);err<=1;@(posedge clk);err<=0;@(negedge clk);
  write_reg('h40,1,1,2,0);read_reg('h48,6,0);read_reg('h5c,1,0);
  // Coincident publication and snapshot execution must include the new result/error.
  send_aw('h40);
  fork
   send_w(1,1);
   begin
    do @(posedge clk);while(!(wv&&wr));
    valid<=1;x0<=300;x1<=309;y0<=100;y1<=107;count<=4321;pulse<=1;
    @(posedge clk);pulse<=0;
   end
  join
  wait(bv);repeat(2)@(negedge clk);br=1;@(posedge clk);@(negedge clk);br=0;
  read_reg('h44,3,0);read_reg('h54,4321,0);read_reg('h4c,(309<<16)|300,0);
  write_reg('h80,32'h656e6165,15,0,0);write_reg('ha0,1,15,1,0);
  read_reg('h80,32'h656e6165,0);write_reg('h80,0,15,2,2); // cannot overwrite a pending command
  write_reg('ha0,2,15,0,2);write_reg('ha4,1,15,1,0);
  write_reg('h80,32'h000000ff,1,0,0);read_reg('h80,32'h656e61ff,0);
  repeat(22000)@(negedge clk); // multiple independent pulse periods
  read_reg('hb4,1600,0);read_reg('hb8,1400,0);
  read_reg('hbc,20000,0);read_reg('hc0,20000,0);read_reg('hb0,15,0);
  duration_checks=0;write_reg(8,0,1,0,0);check(!yp&&!pp,"disable immediate low, pulse values retained");
  read_reg('h14,1600,0);write_reg(8,1,1,1,0); // single yaw enable; pitch remains off
  repeat(21000)@(negedge clk);check(!pp,"single-axis enable");
  check(real_pulses>=3,"actual 100MHz waveform coverage");
  @(negedge clk);rst=0;#1;check(!yp&&!pp&&!real_yaw,"reset output gate");
  $display("PASS PAN_RTL checks=%0d actual_100MHz_pulses=%0d",checks,real_pulses);$finish;
 end
 initial begin #300000000;$display("FAIL watchdog");$fatal(1);end
endmodule
