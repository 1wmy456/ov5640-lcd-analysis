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
 function [34:0] glyph(input [7:0] c);
 begin case(c)
  "S":glyph={5'b01111,5'b10000,5'b10000,5'b01110,5'b00001,5'b00001,5'b11110};
  "E":glyph={5'b11111,5'b10000,5'b10000,5'b11110,5'b10000,5'b10000,5'b11111};
  "L":glyph={5'b10000,5'b10000,5'b10000,5'b10000,5'b10000,5'b10000,5'b11111};
  "C":glyph={5'b01111,5'b10000,5'b10000,5'b10000,5'b10000,5'b10000,5'b01111};
  "T":glyph={5'b11111,5'b00100,5'b00100,5'b00100,5'b00100,5'b00100,5'b00100};
  "R":glyph={5'b11110,5'b10001,5'b10001,5'b11110,5'b10100,5'b10010,5'b10001};
  "A":glyph={5'b01110,5'b10001,5'b10001,5'b11111,5'b10001,5'b10001,5'b10001};
  "K":glyph={5'b10001,5'b10010,5'b10100,5'b11000,5'b10100,5'b10010,5'b10001};
  "O":glyph={5'b01110,5'b10001,5'b10001,5'b10001,5'b10001,5'b10001,5'b01110};
  default:glyph=0;
 endcase end endfunction
 function [7:0] letter(input [1:0] state,input [2:0] index);
 begin
  letter=" ";
  case(state)
   0:case(index)0:letter="S";1:letter="E";2:letter="L";3:letter="E";4:letter="C";5:letter="T";endcase
   1:case(index)0:letter="T";1:letter="R";2:letter="A";3:letter="C";4:letter="K";endcase
   2:case(index)0:letter="L";1:letter="O";2:letter="S";3:letter="T";endcase
  endcase
 end endfunction
 wire [15:0] tx=px-8,ty=py-8;
 wire label=mk[28]&&valid&&px>=8&&px<56&&py>=8&&py<17;
 wire [34:0] bits=glyph(letter(mk[21:20],tx[5:3]));
 wire lit=tx[2:0]<5&&ty<7&&bits[34-ty[2:0]*5-tx[2:0]];
 wire [23:0] state_color=mk[21:20]==1?24'h00ff00:mk[21:20]==2?24'hff0000:24'hffff00;
 always @(posedge aclk)begin
  if(!aresetn)begin x<=0;y<=0;synced<=0;held<=0;m_axis_tvalid<=0;m_axis_tdata<=0;m_axis_tuser<=0;m_axis_tlast<=0;end
  else if(s_axis_tready)begin
   m_axis_tvalid<=s_axis_tvalid;
   if(s_axis_tvalid)begin
    m_axis_tdata<=label?(lit?state_color:24'h000000):(hit?24'hff00ff:s_axis_tdata);
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
