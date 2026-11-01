// Raw RGB fork before every overlay. One requested complete frame -> AXI DMA.
// Independent output handshakes; no branch can duplicate/lose an input pixel.
module axis_raw_capture #(parameter integer IMAGE_WIDTH=800,IMAGE_HEIGHT=480)(
 (* X_INTERFACE_INFO="xilinx.com:signal:clock:1.0 aclk CLK",X_INTERFACE_PARAMETER="ASSOCIATED_BUSIF S_AXIS:M_AXIS:CAPTURE, ASSOCIATED_RESET aresetn, FREQ_HZ 100000000" *) input aclk,
 (* X_INTERFACE_INFO="xilinx.com:signal:reset:1.0 aresetn RST",X_INTERFACE_PARAMETER="POLARITY ACTIVE_LOW" *) input aresetn,
 (* X_INTERFACE_INFO="xilinx.com:interface:axis:1.0 S_AXIS TDATA" *) input [23:0] s_axis_tdata,
 (* X_INTERFACE_INFO="xilinx.com:interface:axis:1.0 S_AXIS TVALID" *) input s_axis_tvalid,
 (* X_INTERFACE_INFO="xilinx.com:interface:axis:1.0 S_AXIS TREADY" *) output s_axis_tready,
 (* X_INTERFACE_INFO="xilinx.com:interface:axis:1.0 S_AXIS TUSER" *) input [0:0] s_axis_tuser,
 (* X_INTERFACE_INFO="xilinx.com:interface:axis:1.0 S_AXIS TLAST" *) input s_axis_tlast,
 (* X_INTERFACE_INFO="xilinx.com:interface:axis:1.0 M_AXIS TDATA" *) output reg [23:0] m_axis_tdata,
 (* X_INTERFACE_INFO="xilinx.com:interface:axis:1.0 M_AXIS TVALID" *) output reg m_axis_tvalid,
 (* X_INTERFACE_INFO="xilinx.com:interface:axis:1.0 M_AXIS TREADY" *) input m_axis_tready,
 (* X_INTERFACE_INFO="xilinx.com:interface:axis:1.0 M_AXIS TUSER" *) output reg [0:0] m_axis_tuser,
 (* X_INTERFACE_INFO="xilinx.com:interface:axis:1.0 M_AXIS TLAST" *) output reg m_axis_tlast,
 (* X_INTERFACE_INFO="xilinx.com:interface:axis:1.0 CAPTURE TDATA" *) output reg [31:0] capture_tdata,
 (* X_INTERFACE_INFO="xilinx.com:interface:axis:1.0 CAPTURE TKEEP" *) output [3:0] capture_tkeep,
 (* X_INTERFACE_INFO="xilinx.com:interface:axis:1.0 CAPTURE TVALID" *) output reg capture_tvalid,
 (* X_INTERFACE_INFO="xilinx.com:interface:axis:1.0 CAPTURE TREADY" *) input capture_tready,
 (* X_INTERFACE_INFO="xilinx.com:interface:axis:1.0 CAPTURE TLAST" *) output reg capture_tlast,
 input [31:0] control,
 output reg [31:0] result_frame_id,output reg result_valid,result_pulse
);
 assign capture_tkeep=4'hf;
 assign s_axis_tready=aresetn&&(!m_axis_tvalid||m_axis_tready)&&(control[29]||!capture_tvalid||capture_tready);
 reg active,used;reg [15:0] x,y;reg [31:0] frame_id,capture_id;reg [2:0] header;
 wire start=s_axis_tuser[0]&&control[30]&&!used&&!active;
 wire take=active||start;
 wire [15:0] px=start?16'd0:x,py=start?16'd0:y;
 wire bad=(active&&s_axis_tuser[0])||(s_axis_tlast!=(px==IMAGE_WIDTH-1))||px>=IMAGE_WIDTH||py>=IMAGE_HEIGHT;
 wire finish=bad||(px==IMAGE_WIDTH-1&&py==IMAGE_HEIGHT-1);
 wire [31:0] fid=start?frame_id+1:capture_id;
 wire [2:0] hn=start?3'd0:header;
 wire [7:0] meta=finish?{bad,7'h00}:(hn<4?(fid>>(hn*8)):8'h00);
 always @(posedge aclk)begin
  if(!aresetn)begin
   active<=0;used<=0;x<=0;y<=0;frame_id<=0;capture_id<=0;header<=0;result_frame_id<=0;result_valid<=0;result_pulse<=0;
   m_axis_tvalid<=0;m_axis_tdata<=0;m_axis_tuser<=0;m_axis_tlast<=0;
   capture_tvalid<=0;capture_tdata<=0;capture_tlast<=0;
  end else begin
   result_pulse<=0;
   if(capture_tvalid&&capture_tready&&capture_tlast)begin result_frame_id<=capture_id;result_valid<=!capture_tdata[31];result_pulse<=1;end
   if(!control[30])used<=0;
   if(m_axis_tready)m_axis_tvalid<=0;
   if(capture_tready)capture_tvalid<=0;
   if(s_axis_tvalid&&s_axis_tready)begin
    m_axis_tvalid<=1;m_axis_tdata<=s_axis_tdata;m_axis_tuser<=s_axis_tuser;m_axis_tlast<=s_axis_tlast;
    if(s_axis_tuser[0])frame_id<=frame_id+1;
    if(take&&!control[29])begin
     capture_tvalid<=1;capture_tdata<={meta,s_axis_tdata};capture_tlast<=finish;
     if(start)begin used<=1;capture_id<=frame_id+1;end
     active<=!finish;header<=hn<4?hn+1:hn;
     if(s_axis_tlast)begin x<=0;y<=py+1;end else begin x<=px+1;y<=py;end
    end
   end
   if(control[29])begin active<=0;used<=1;capture_tvalid<=0;end
  end
 end
endmodule
