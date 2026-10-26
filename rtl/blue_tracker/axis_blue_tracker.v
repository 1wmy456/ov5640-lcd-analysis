module axis_blue_tracker #(
    parameter integer IMAGE_WIDTH = 800, IMAGE_HEIGHT = 480,
    parameter integer MODE = 2,
    parameter integer R_BYTE = 2, G_BYTE = 1, B_BYTE = 0,
    parameter integer BLUE_MIN = 80, BR_DELTA = 35, BG_DELTA = 20,
    parameter integer MIN_B_R_RATIO = 0, MIN_BLUE_RUN = 1,
    parameter integer MIN_PIXELS = 24, MIN_WIDTH = 3, MIN_HEIGHT = 3,
    parameter integer BBOX_FILTER_SHIFT = 0,
    parameter integer COMPONENT_MODE=0,MASK_BLOCK=4,MASK_CELL_MIN=4,
    parameter integer BORDER_WIDTH = 2, CENTER_CROSS = 0
)(
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 aclk CLK",
       X_INTERFACE_PARAMETER = "ASSOCIATED_BUSIF S_AXIS:M_AXIS, ASSOCIATED_RESET aresetn, FREQ_HZ 100000000" *)
    input aclk,
    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 aresetn RST",
       X_INTERFACE_PARAMETER = "POLARITY ACTIVE_LOW" *)
    input aresetn,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 S_AXIS TDATA" *) input [23:0] s_axis_tdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 S_AXIS TVALID" *) input s_axis_tvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 S_AXIS TREADY" *) output s_axis_tready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 S_AXIS TUSER" *) input [0:0] s_axis_tuser,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 S_AXIS TLAST" *) input s_axis_tlast,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS TDATA" *) output reg [23:0] m_axis_tdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS TVALID" *) output reg m_axis_tvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS TREADY" *) input m_axis_tready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS TUSER" *) output reg [0:0] m_axis_tuser,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS TLAST" *) output reg m_axis_tlast,
    output bbox_valid, result_pulse, frame_error,
    output [15:0] bbox_xmin, bbox_xmax, bbox_ymin, bbox_ymax,
    output [31:0] blue_pixel_count,
    output mask_start,mask_word_valid,mask_frame_done,
    output [9:0] mask_word_address,output [31:0] mask_word_data,
    input display_bbox_valid,
    input [15:0] display_xmin,display_xmax,display_ymin,display_ymax
);
    assign s_axis_tready = aresetn && (!m_axis_tvalid || m_axis_tready);
    wire accept = s_axis_tvalid && s_axis_tready;
    wire blue, pixel_valid, prior_usable;
    wire [15:0] x, y;
    blue_pixel_detect #(.R_BYTE(R_BYTE),.G_BYTE(G_BYTE),.B_BYTE(B_BYTE),
        .BLUE_MIN(BLUE_MIN),.BR_DELTA(BR_DELTA),.BG_DELTA(BG_DELTA),
        .MIN_B_R_RATIO(MIN_B_R_RATIO)) detect(s_axis_tdata,blue);
    generate if(!COMPONENT_MODE) begin:legacy_statistics
    blue_bbox_stats #(.IMAGE_WIDTH(IMAGE_WIDTH),.IMAGE_HEIGHT(IMAGE_HEIGHT),
        .MIN_PIXELS(MIN_PIXELS),.MIN_WIDTH(MIN_WIDTH),.MIN_HEIGHT(MIN_HEIGHT),
        .MIN_BLUE_RUN(MIN_BLUE_RUN),.BBOX_FILTER_SHIFT(BBOX_FILTER_SHIFT)) stats(
        .clk(aclk),.resetn(aresetn),.accept(accept),.sof(s_axis_tuser[0]),
        .eol(s_axis_tlast),.is_blue(blue),.pixel_x(x),.pixel_y(y),
        .pixel_valid(pixel_valid),.prior_usable(prior_usable),.bbox_valid(bbox_valid),
        .result_pulse(result_pulse),.frame_error(frame_error),
        .xmin(bbox_xmin),.xmax(bbox_xmax),.ymin(bbox_ymin),.ymax(bbox_ymax),
        .blue_pixel_count(blue_pixel_count));
    end else begin:component_frame_statistics
        blue_frame_stats #(.IMAGE_WIDTH(IMAGE_WIDTH),.IMAGE_HEIGHT(IMAGE_HEIGHT)) stats(
            .clk(aclk),.resetn(aresetn),.accept(accept),.sof(s_axis_tuser[0]),.eol(s_axis_tlast),.is_blue(blue),
            .pixel_x(x),.pixel_y(y),.pixel_valid(pixel_valid),.prior_usable(prior_usable),
            .bbox_valid(bbox_valid),.result_pulse(result_pulse),.frame_error(frame_error),
            .xmin(bbox_xmin),.xmax(bbox_xmax),.ymin(bbox_ymin),.ymax(bbox_ymax),.blue_pixel_count(blue_pixel_count));
    end endgenerate
    generate if(COMPONENT_MODE) begin:mask_capture
        blue_mask_sampler #(.IMAGE_WIDTH(IMAGE_WIDTH),.IMAGE_HEIGHT(IMAGE_HEIGHT),
            .BLOCK(MASK_BLOCK),.CELL_MIN(MASK_CELL_MIN)) sampler(
            .clk(aclk),.resetn(aresetn),.accept(accept),.sof(s_axis_tuser[0]),.eol(s_axis_tlast),
            .is_blue(blue),.pixel_valid(pixel_valid),.x(x),.y(y),
            .mask_start(mask_start),.mask_word_valid(mask_word_valid),.mask_frame_done(mask_frame_done),
            .mask_word_address(mask_word_address),.mask_word_data(mask_word_data));
    end else begin:no_mask_capture
        assign mask_start=0;assign mask_word_valid=0;assign mask_frame_done=0;
        assign mask_word_address=0;assign mask_word_data=0;
    end endgenerate
    reg frame_open;
    wire chosen_valid=COMPONENT_MODE?(display_bbox_valid&&!frame_open):prior_usable;
    wire [15:0] chosen_xmin=COMPONENT_MODE?display_xmin:bbox_xmin;
    wire [15:0] chosen_xmax=COMPONENT_MODE?display_xmax:bbox_xmax;
    wire [15:0] chosen_ymin=COMPONENT_MODE?display_ymin:bbox_ymin;
    wire [15:0] chosen_ymax=COMPONENT_MODE?display_ymax:bbox_ymax;
    reg draw_valid;
    reg [15:0] draw_xmin,draw_xmax,draw_ymin,draw_ymax;
    // SOF pixel uses the new snapshot immediately, all subsequent pixels use registers.
    wire dv = s_axis_tuser[0] ? chosen_valid : draw_valid;
    wire [15:0] dx0 = s_axis_tuser[0] ? chosen_xmin : draw_xmin;
    wire [15:0] dx1 = s_axis_tuser[0] ? chosen_xmax : draw_xmax;
    wire [15:0] dy0 = s_axis_tuser[0] ? chosen_ymin : draw_ymin;
    wire [15:0] dy1 = s_axis_tuser[0] ? chosen_ymax : draw_ymax;
    wire [23:0] painted;
    video_box_overlay #(.IMAGE_WIDTH(IMAGE_WIDTH),.IMAGE_HEIGHT(IMAGE_HEIGHT),
        .BORDER_WIDTH(BORDER_WIDTH),.CENTER_CROSS(CENTER_CROSS)) overlay(
        .pixel(s_axis_tdata),.x(x),.y(y),.xmin(dx0),.xmax(dx1),.ymin(dy0),.ymax(dy1),
        .valid(dv && pixel_valid),.painted(painted));
    always @(posedge aclk) begin
        if (!aresetn) begin
            m_axis_tvalid <= 0; m_axis_tdata <= 0; m_axis_tuser <= 0; m_axis_tlast <= 0;
            draw_valid <= 0; draw_xmin <= 0; draw_xmax <= 0; draw_ymin <= 0; draw_ymax <= 0;
            frame_open<=0;
        end else begin
            if (s_axis_tready) begin
                m_axis_tvalid <= s_axis_tvalid;
                if (s_axis_tvalid) begin
                    m_axis_tdata <= MODE == 0 ? s_axis_tdata :
                                   MODE == 1 ? (blue ? 24'hffffff : 24'h000000) : painted;
                    m_axis_tuser <= s_axis_tuser; m_axis_tlast <= s_axis_tlast;
                end
            end
            if(accept)begin
                if(!pixel_valid)frame_open<=0;
                else if(s_axis_tlast&&y==IMAGE_HEIGHT-1)frame_open<=0;
                else frame_open<=1;
            end
            if (accept && s_axis_tuser[0]) begin
                draw_valid <= chosen_valid;
                draw_xmin <= chosen_xmin; draw_xmax <= chosen_xmax;
                draw_ymin <= chosen_ymin; draw_ymax <= chosen_ymax;
            end
        end
    end
endmodule
