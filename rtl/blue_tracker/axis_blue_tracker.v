module axis_blue_tracker #(
    parameter integer IMAGE_WIDTH = 800, IMAGE_HEIGHT = 480,
    parameter integer MODE = 2,
    parameter integer R_BYTE = 2, G_BYTE = 1, B_BYTE = 0,
    parameter integer BLUE_MIN = 80, BR_DELTA = 35, BG_DELTA = 20,
    parameter integer MIN_PIXELS = 24, MIN_WIDTH = 3, MIN_HEIGHT = 3,
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
    output [31:0] blue_pixel_count
);
    assign s_axis_tready = aresetn && (!m_axis_tvalid || m_axis_tready);
    wire accept = s_axis_tvalid && s_axis_tready;
    wire blue, pixel_valid, prior_usable;
    wire [15:0] x, y;
    blue_pixel_detect #(.R_BYTE(R_BYTE),.G_BYTE(G_BYTE),.B_BYTE(B_BYTE),
        .BLUE_MIN(BLUE_MIN),.BR_DELTA(BR_DELTA),.BG_DELTA(BG_DELTA)) detect(s_axis_tdata,blue);
    blue_bbox_stats #(.IMAGE_WIDTH(IMAGE_WIDTH),.IMAGE_HEIGHT(IMAGE_HEIGHT),
        .MIN_PIXELS(MIN_PIXELS),.MIN_WIDTH(MIN_WIDTH),.MIN_HEIGHT(MIN_HEIGHT)) stats(
        .clk(aclk),.resetn(aresetn),.accept(accept),.sof(s_axis_tuser[0]),
        .eol(s_axis_tlast),.is_blue(blue),.pixel_x(x),.pixel_y(y),
        .pixel_valid(pixel_valid),.prior_usable(prior_usable),.bbox_valid(bbox_valid),
        .result_pulse(result_pulse),.frame_error(frame_error),
        .xmin(bbox_xmin),.xmax(bbox_xmax),.ymin(bbox_ymin),.ymax(bbox_ymax),
        .blue_pixel_count(blue_pixel_count));
    reg draw_valid;
    reg [15:0] draw_xmin,draw_xmax,draw_ymin,draw_ymax;
    // SOF pixel uses the new snapshot immediately, all subsequent pixels use registers.
    wire dv = s_axis_tuser[0] ? prior_usable : draw_valid;
    wire [15:0] dx0 = s_axis_tuser[0] ? bbox_xmin : draw_xmin;
    wire [15:0] dx1 = s_axis_tuser[0] ? bbox_xmax : draw_xmax;
    wire [15:0] dy0 = s_axis_tuser[0] ? bbox_ymin : draw_ymin;
    wire [15:0] dy1 = s_axis_tuser[0] ? bbox_ymax : draw_ymax;
    wire [23:0] painted;
    video_box_overlay #(.IMAGE_WIDTH(IMAGE_WIDTH),.IMAGE_HEIGHT(IMAGE_HEIGHT),
        .BORDER_WIDTH(BORDER_WIDTH),.CENTER_CROSS(CENTER_CROSS)) overlay(
        .pixel(s_axis_tdata),.x(x),.y(y),.xmin(dx0),.xmax(dx1),.ymin(dy0),.ymax(dy1),
        .valid(dv && pixel_valid),.painted(painted));
    always @(posedge aclk) begin
        if (!aresetn) begin
            m_axis_tvalid <= 0; m_axis_tdata <= 0; m_axis_tuser <= 0; m_axis_tlast <= 0;
            draw_valid <= 0; draw_xmin <= 0; draw_xmax <= 0; draw_ymin <= 0; draw_ymax <= 0;
        end else begin
            if (s_axis_tready) begin
                m_axis_tvalid <= s_axis_tvalid;
                if (s_axis_tvalid) begin
                    m_axis_tdata <= MODE == 0 ? s_axis_tdata :
                                   MODE == 1 ? (blue ? 24'hffffff : 24'h000000) : painted;
                    m_axis_tuser <= s_axis_tuser; m_axis_tlast <= s_axis_tlast;
                end
            end
            if (accept && s_axis_tuser[0]) begin
                draw_valid <= prior_usable;
                draw_xmin <= bbox_xmin; draw_xmax <= bbox_xmax;
                draw_ymin <= bbox_ymin; draw_ymax <= bbox_ymax;
            end
        end
    end
endmodule
