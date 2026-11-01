`timescale 1ns/1ps
module tb_raw_capture;
 reg clk=0;always #5 clk=~clk;
 reg resetn=0,iv=0,mr=0,cr=0;reg [23:0] id;reg [0:0] iu;reg il;reg [31:0] control=0;
 wire ir,mv,cv,ml,cl;wire [23:0] md;wire [0:0] mu;wire [31:0] cd;wire [3:0] ck;
 wire [31:0] result_id;wire result_valid,result_pulse;
 axis_raw_capture #(.IMAGE_WIDTH(8),.IMAGE_HEIGHT(6)) dut(clk,resetn,id,iv,ir,iu,il,md,mv,mr,mu,ml,cd,ck,cv,cr,cl,control,result_id,result_valid,result_pulse);
 reg [25:0] qm[0:1023];reg [32:0] qc[0:1023];
 integer wm=0,rm=0,wc=0,rc=0,checks=0,f,n,selected,stalls=0,results=0;
 reg ms=0,cs=0;reg [25:0] pm;reg [36:0] pc;
 always @(negedge clk)if(resetn)begin mr=$urandom_range(0,3)!=0;cr=$urandom_range(0,2)!=0;end
 always @(posedge clk)if(resetn)begin
  if(result_pulse)begin
   if(result_id!==(results==0?32'd2:results==1?32'd5:32'd8)||result_valid!==(results<2))$fatal(1,"registered result metadata");
   results++;checks++;
  end
  if(ms)begin checks++;if(!mv||{md,mu,ml}!==pm)$fatal(1,"main stalled data changed");end
  if(cs)begin checks++;if(!cv||{cd,ck,cl}!==pc)$fatal(1,"capture stalled data changed");end
  ms=mv&&!mr;cs=cv&&!cr;pm={md,mu,ml};pc={cd,ck,cl};if(ms||cs)stalls++;
  if(mv&&mr)begin checks++;if(rm>=wm||{md,mu,ml}!==qm[rm])$fatal(1,"main alignment %d",rm);rm++;end
  if(cv&&cr)begin checks++;if(rc>=wc||{cd,cl}!==qc[rc]||ck!=15)$fatal(1,"raw packet %d got %h expected %h",rc,{cd,cl},qc[rc]);rc++;end
 end
 task send(input integer ff,input integer nn);
 reg [7:0] meta;reg ending;
 begin
  repeat($urandom_range(0,2))begin @(negedge clk);iv=0;end
  @(negedge clk);iv=1;id=ff*48+nn;iu=(nn==0);il=nn%8==7||(ff==7&&nn==3);
  do @(posedge clk);while(!ir);
  qm[wm]={id,iu,il};wm++;
  if(ff==1||ff==4||(ff==7&&nn<4))begin
   ending=ff==7?nn==3:nn==47;
   meta=ending?(ff==7?8'h80:0):(nn<4?((ff+1)>>(8*nn)):0);
   qc[wc]={{meta,id},ending};wc++;
  end
  @(negedge clk);iv=0;
 end endtask
 initial begin
  repeat(5)@(negedge clk);resetn=1;
  for(f=0;f<8;f++)begin
   control=(f==1||f==2||f==4||f==5||f==7)?32'h40000000:0;
   for(n=0;n<48;n++)send(f,n);
  end
  wait(rm==wm&&rc==wc);repeat(5)@(negedge clk);
  if(wm!=384||wc!=100||stalls==0||results!=3)$fatal(1,"coverage");
  $display("PASS RAW_CAPTURE checks=%0d main=%0d raw=%0d stalls=%0d independent handshakes/one-shot/metadata/malformed-EOL",checks,wm,wc,stalls);$finish;
 end
 initial begin #500000;$fatal(1,"timeout");end
endmodule
