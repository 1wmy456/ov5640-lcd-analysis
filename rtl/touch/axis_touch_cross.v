// Single elastic stage. Marker coordinates latch at accepted SOF, never mid-frame.
module axis_touch_cross #(
 parameter integer IMAGE_WIDTH=800,IMAGE_HEIGHT=480
)(
 (* X_INTERFACE_INFO="xilinx.com:signal:clock:1.0 aclk CLK",X_INTERFACE_PARAMETER="ASSOCIATED_BUSIF S_AXIS:M_AXIS, ASSOCIATED_RESET aresetn, FREQ_HZ 100000000" *) input aclk,
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
 input [31:0] marker
);
 assign s_axis_tready=aresetn&&(!m_axis_tvalid||m_axis_tready);
 reg [15:0] x,y;reg synced;reg [31:0] held;
 wire sof=s_axis_tuser[0];
 wire [15:0] px=sof?16'd0:x,py=sof?16'd0:y;
 wire [31:0] mk=sof?marker:held;
 wire [15:0] mx={6'd0,mk[9:0]},my={7'd0,mk[18:10]};
 wire [15:0] dx=px>mx?px-mx:mx-px,dy=py>my?py-my:my-py;
 wire line_ok=s_axis_tlast==(px==IMAGE_WIDTH-1);
 wire valid=(sof||synced)&&px<IMAGE_WIDTH&&py<IMAGE_HEIGHT&&line_ok;
 wire hit=mk[31]&&mx<IMAGE_WIDTH&&my<IMAGE_HEIGHT&&valid&&((dx<=12&&dy<=1)||(dy<=12&&dx<=1));
 always @(posedge aclk)begin
  if(!aresetn)begin x<=0;y<=0;synced<=0;held<=0;m_axis_tvalid<=0;m_axis_tdata<=0;m_axis_tuser<=0;m_axis_tlast<=0;end
  else if(s_axis_tready)begin
   m_axis_tvalid<=s_axis_tvalid;
   if(s_axis_tvalid)begin
    m_axis_tdata<=hit?24'hff00ff:s_axis_tdata;
    m_axis_tuser<=s_axis_tuser;m_axis_tlast<=s_axis_tlast;
    if(sof)held<=marker;
    if(!valid)begin synced<=0;x<=0;y<=0;end
    else begin
     synced<=!(s_axis_tlast&&py==IMAGE_HEIGHT-1);
     if(s_axis_tlast)begin x<=0;y<=py+1;end else begin x<=px+1;y<=py;end
    end
   end
  end
 end
endmodule
