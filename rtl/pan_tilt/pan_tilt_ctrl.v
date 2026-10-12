module pan_tilt_ctrl #(
    parameter integer CLOCK_HZ=100000000,IMAGE_WIDTH=800,IMAGE_HEIGHT=480,
    parameter integer C_S_AXI_ADDR_WIDTH=12,
    parameter [31:0] C_S_AXI_BASEADDR=0,C_S_AXI_HIGHADDR=4095
)(
    (* X_INTERFACE_INFO="xilinx.com:signal:clock:1.0 s_axi_aclk CLK", X_INTERFACE_PARAMETER="ASSOCIATED_BUSIF S_AXI, ASSOCIATED_RESET s_axi_aresetn, FREQ_HZ 100000000" *) input s_axi_aclk,
    (* X_INTERFACE_INFO="xilinx.com:signal:reset:1.0 s_axi_aresetn RST", X_INTERFACE_PARAMETER="POLARITY ACTIVE_LOW" *) input s_axi_aresetn,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI AWADDR" *) input [C_S_AXI_ADDR_WIDTH-1:0] s_axi_awaddr,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI AWPROT" *) input [2:0] s_axi_awprot,(* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI AWVALID" *) input s_axi_awvalid,(* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI AWREADY" *) output s_axi_awready,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI WDATA" *) input [31:0] s_axi_wdata,(* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI WSTRB" *) input [3:0] s_axi_wstrb,(* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI WVALID" *) input s_axi_wvalid,(* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI WREADY" *) output s_axi_wready,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI BRESP" *) output reg [1:0] s_axi_bresp,(* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI BVALID" *) output reg s_axi_bvalid,(* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI BREADY" *) input s_axi_bready,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI ARADDR" *) input [C_S_AXI_ADDR_WIDTH-1:0] s_axi_araddr,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI ARPROT" *) input [2:0] s_axi_arprot,(* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI ARVALID" *) input s_axi_arvalid,(* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI ARREADY" *) output s_axi_arready,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI RDATA" *) output reg [31:0] s_axi_rdata,(* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI RRESP" *) output reg [1:0] s_axi_rresp,(* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI RVALID" *) output reg s_axi_rvalid,(* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI RREADY" *) input s_axi_rready,
    input bbox_valid,result_pulse,frame_error,
    input [15:0] bbox_xmin,bbox_xmax,bbox_ymin,bbox_ymax,
    input [31:0] blue_pixel_count,
    output servo_yaw_pwm,servo_pitch_pwm
);
    localparam integer TICKS_PER_US=CLOCK_HZ/1000000;
    localparam integer US_WIDTH=TICKS_PER_US<2?1:$clog2(TICKS_PER_US);
    reg aw_full,w_full;
    reg [C_S_AXI_ADDR_WIDTH-1:0] aw_address;
    reg [31:0] w_data;reg [3:0] w_strobes;
    assign s_axi_awready=!aw_full&&!s_axi_bvalid&&s_axi_aresetn;
    assign s_axi_wready=!w_full&&!s_axi_bvalid&&s_axi_aresetn;
    assign s_axi_arready=(!s_axi_rvalid||s_axi_rready)&&s_axi_aresetn;
    reg [1:0] enables;
    reg [15:0] yaw_shadow,pitch_shadow,yaw_min,yaw_max,pitch_min,pitch_max,yaw_center,pitch_center;
    reg commit;
    wire [31:0] yaw_high_ticks,pitch_high_ticks,yaw_period_ticks,pitch_period_ticks,yaw_rises,pitch_rises;
    wire yaw_width_valid,pitch_width_valid,yaw_period_valid,pitch_period_valid;
    pwm_wave_monitor yaw_monitor(.clk(s_axi_aclk),.resetn(s_axi_aresetn),.level(servo_yaw_pwm),
        .high_ticks(yaw_high_ticks),.period_ticks(yaw_period_ticks),.rise_count(yaw_rises),
        .width_valid(yaw_width_valid),.period_valid(yaw_period_valid));
    pwm_wave_monitor pitch_monitor(.clk(s_axi_aclk),.resetn(s_axi_aresetn),.level(servo_pitch_pwm),
        .high_ticks(pitch_high_ticks),.period_ticks(pitch_period_ticks),.rise_count(pitch_rises),
        .width_valid(pitch_width_valid),.period_valid(pitch_period_valid));
    wire [15:0] active_yaw,active_pitch;wire [1:0] active_enable;wire pending;
    wire [31:0] applied_sequence;
    dual_servo_pwm #(.CLOCK_HZ(CLOCK_HZ)) pwm(
      .clk(s_axi_aclk),.resetn(s_axi_aresetn),.enable_request(enables),.commit(commit),
      .yaw_us(yaw_shadow),.pitch_us(pitch_shadow),.yaw_min(yaw_min),.yaw_max(yaw_max),
      .pitch_min(pitch_min),.pitch_max(pitch_max),.servo_yaw_pwm(servo_yaw_pwm),.servo_pitch_pwm(servo_pitch_pwm),
      .active_yaw_us(active_yaw),.active_pitch_us(active_pitch),.active_enable(active_enable),
      .pending(pending),.applied_sequence(applied_sequence));
    reg [31:0] live_frame,live_flags,live_x,live_y,live_count,age_us,error_count;
    reg [US_WIDTH-1:0] us_div;
    reg [31:0] snap_frame,snap_flags,snap_x,snap_y,snap_count,snap_age,snap_sequence;
    reg [31:0] command_words[0:7];
    reg [31:0] command_request,command_ack,app_status,app_command_result;
    integer ci;
    wire [31:0] next_frame=live_frame+(result_pulse?32'd1:32'd0);
    wire [31:0] next_flags=frame_error ? {29'd0,(live_flags[2]|result_pulse),1'b1,1'b0} :
                           (result_pulse?{29'd0,1'b1,1'b0,bbox_valid}:live_flags);
    function [31:0] merge;
        input [31:0] old_value,new_value;input [3:0] strobes;integer i;
        begin for(i=0;i<4;i=i+1)merge[i*8+:8]=strobes[i]?new_value[i*8+:8]:old_value[i*8+:8];end
    endfunction
    reg [31:0] merged;
    always @(posedge s_axi_aclk) begin
        if(!s_axi_aresetn) begin
            aw_full<=0;w_full<=0;aw_address<=0;w_data<=0;w_strobes<=0;
            s_axi_bvalid<=0;s_axi_bresp<=0;s_axi_rvalid<=0;s_axi_rdata<=0;s_axi_rresp<=0;
            enables<=0;commit<=0;yaw_shadow<=1500;pitch_shadow<=1500;
            yaw_min<=1400;yaw_max<=1600;pitch_min<=1400;pitch_max<=1600;
            yaw_center<=1500;pitch_center<=1500;
            live_frame<=0;live_flags<=0;live_x<=0;live_y<=0;live_count<=0;age_us<=0;us_div<=0;error_count<=0;
            snap_frame<=0;snap_flags<=0;snap_x<=0;snap_y<=0;snap_count<=0;snap_age<=0;snap_sequence<=0;
            command_request<=0;command_ack<=0;app_status<=0;app_command_result<=0;
            for(ci=0;ci<8;ci=ci+1)command_words[ci]<=0;
        end else begin
            commit<=0;
            if(us_div==TICKS_PER_US-1) begin
                us_div<=0;if(age_us!=32'hffffffff)age_us<=age_us+1'b1;
            end else us_div<=us_div+1'b1;
            // result_pulse was registered with the bbox on the preceding edge:
            // consuming it here reads the updated coherent result, not the old frame.
            if(result_pulse) begin
                live_frame<=next_frame;live_flags<=next_flags;
                live_x<={bbox_xmax,bbox_xmin};live_y<={bbox_ymax,bbox_ymin};
                live_count<=blue_pixel_count;age_us<=0;
            end
            if(frame_error) begin live_flags<=next_flags;error_count<=error_count+1'b1;end
            if(s_axi_awvalid&&s_axi_awready)begin aw_full<=1;aw_address<=s_axi_awaddr;end
            if(s_axi_wvalid&&s_axi_wready)begin w_full<=1;w_data<=s_axi_wdata;w_strobes<=s_axi_wstrb;end
            if(s_axi_bvalid&&s_axi_bready)s_axi_bvalid<=0;
            if(aw_full&&w_full&&!s_axi_bvalid) begin
                aw_full<=0;w_full<=0;s_axi_bvalid<=1;s_axi_bresp<=0;
                case(aw_address)
                    'h08:enables<=merge({30'd0,enables},w_data,w_strobes)&3;
                    'h0c:yaw_shadow<=merge({16'd0,yaw_shadow},w_data,w_strobes); // clamped at commit
                    'h10:pitch_shadow<=merge({16'd0,pitch_shadow},w_data,w_strobes);
                    'h1c:begin merged=merge({16'd0,yaw_min},w_data,w_strobes);
                        if(merged>=500&&merged<=yaw_max)yaw_min<=merged;else s_axi_bresp<=2;end
                    'h20:begin merged=merge({16'd0,yaw_max},w_data,w_strobes);
                        if(merged>=yaw_min&&merged<=2500)yaw_max<=merged;else s_axi_bresp<=2;end
                    'h24:begin merged=merge({16'd0,pitch_min},w_data,w_strobes);
                        if(merged>=500&&merged<=pitch_max)pitch_min<=merged;else s_axi_bresp<=2;end
                    'h28:begin merged=merge({16'd0,pitch_max},w_data,w_strobes);
                        if(merged>=pitch_min&&merged<=2500)pitch_max<=merged;else s_axi_bresp<=2;end
                    'h2c:begin merged=merge({16'd0,yaw_center},w_data,w_strobes);
                        if(merged>=yaw_min&&merged<=yaw_max)yaw_center<=merged;else s_axi_bresp<=2;end
                    'h30:begin merged=merge({16'd0,pitch_center},w_data,w_strobes);
                        if(merged>=pitch_min&&merged<=pitch_max)pitch_center<=merged;else s_axi_bresp<=2;end
                    'h34:if(w_strobes[0]&&w_data[0])commit<=1;
                    'h40:if(w_strobes[0]&&w_data[0]) begin
                        snap_frame<=next_frame;snap_flags<=next_flags;
                        snap_x<=result_pulse?{bbox_xmax,bbox_xmin}:live_x;
                        snap_y<=result_pulse?{bbox_ymax,bbox_ymin}:live_y;
                        snap_count<=result_pulse?blue_pixel_count:live_count;
                        snap_age<=result_pulse?0:age_us;snap_sequence<=snap_sequence+1'b1;
                    end
                    'ha0:begin
                        if(command_request==command_ack)command_request<=merge(command_request,w_data,w_strobes);
                        else s_axi_bresp<=2;
                    end
                    'ha4:begin
                        merged=merge(command_ack,w_data,w_strobes);
                        if(merged==command_request)command_ack<=merged;else s_axi_bresp<=2;
                    end
                    'ha8:app_status<=merge(app_status,w_data,w_strobes);
                    'hac:app_command_result<=merge(app_command_result,w_data,w_strobes);
                    default:begin
                        if(aw_address>='h80&&aw_address<='h9c&&aw_address[1:0]==0&&command_request==command_ack)
                            command_words[aw_address[4:2]]<=merge(command_words[aw_address[4:2]],w_data,w_strobes);
                        else s_axi_bresp<=2;
                    end
                endcase
            end
            if(s_axi_arvalid&&s_axi_arready) begin
                s_axi_rvalid<=1;s_axi_rresp<=0;
                case(s_axi_araddr)
                  'h00:s_axi_rdata<=32'h50544c54;
                  'h04:s_axi_rdata<=32'h00010000;
                  'h08:s_axi_rdata<={30'd0,enables};
                  'h0c:s_axi_rdata<=yaw_shadow;'h10:s_axi_rdata<=pitch_shadow;
                  'h14:s_axi_rdata<=active_yaw;'h18:s_axi_rdata<=active_pitch;
                  'h1c:s_axi_rdata<=yaw_min;'h20:s_axi_rdata<=yaw_max;
                  'h24:s_axi_rdata<=pitch_min;'h28:s_axi_rdata<=pitch_max;
                  'h2c:s_axi_rdata<=yaw_center;'h30:s_axi_rdata<=pitch_center;
                  'h34:s_axi_rdata<=pending|commit;
                  'h38:s_axi_rdata<={23'd0,(pending|commit),6'd0,active_enable};
                  'h3c:s_axi_rdata<=applied_sequence;
                  'h40:s_axi_rdata<=0;'h44:s_axi_rdata<=snap_frame;
                  'h48:s_axi_rdata<=snap_flags;'h4c:s_axi_rdata<=snap_x;
                  'h50:s_axi_rdata<=snap_y;'h54:s_axi_rdata<=snap_count;
                  'h58:s_axi_rdata<=snap_age;'h5c:s_axi_rdata<=error_count;
                  'h60:s_axi_rdata<=(IMAGE_HEIGHT<<16)|IMAGE_WIDTH;
                  'h64:s_axi_rdata<=CLOCK_HZ;'h68:s_axi_rdata<=20000;
                  'h6c:s_axi_rdata<=live_frame;'h70:s_axi_rdata<=snap_sequence;
                  'ha0:s_axi_rdata<=command_request;'ha4:s_axi_rdata<=command_ack;
                  'ha8:s_axi_rdata<=app_status;'hac:s_axi_rdata<=app_command_result;
                  'hb0:s_axi_rdata<={22'd0,servo_pitch_pwm,servo_yaw_pwm,4'd0,pitch_period_valid,yaw_period_valid,pitch_width_valid,yaw_width_valid};
                  'hb4:s_axi_rdata<=yaw_high_ticks;'hb8:s_axi_rdata<=pitch_high_ticks;
                  'hbc:s_axi_rdata<=yaw_period_ticks;'hc0:s_axi_rdata<=pitch_period_ticks;
                  'hc4:s_axi_rdata<=yaw_rises;'hc8:s_axi_rdata<=pitch_rises;
                  default:begin
                      if(s_axi_araddr>='h80&&s_axi_araddr<='h9c&&s_axi_araddr[1:0]==0)s_axi_rdata<=command_words[s_axi_araddr[4:2]];
                      else begin s_axi_rdata<=0;s_axi_rresp<=2;end
                  end
                endcase
            end else if(s_axi_rvalid&&s_axi_rready)s_axi_rvalid<=0;
        end
    end
endmodule
