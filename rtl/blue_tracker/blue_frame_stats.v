// Component mode needs frame validation and mask coordinates, not a second,
// whole-image bounding box. Keep this short path separate from legacy stats.
module blue_frame_stats #(
    parameter integer IMAGE_WIDTH=800,IMAGE_HEIGHT=480
)(
    input clk,resetn,accept,sof,eol,is_blue,
    output [15:0] pixel_x,pixel_y,
    output pixel_valid,prior_usable,
    output bbox_valid,
    output reg result_pulse,frame_error,
    output [15:0] xmin,xmax,ymin,ymax,
    output reg [31:0] blue_pixel_count
);
    localparam integer XW=IMAGE_WIDTH<2?1:$clog2(IMAGE_WIDTH+1);
    localparam integer YW=IMAGE_HEIGHT<2?1:$clog2(IMAGE_HEIGHT+1);
    localparam integer CW=$clog2(IMAGE_WIDTH*IMAGE_HEIGHT+1);
    reg [XW-1:0] x;
    reg [YW-1:0] y;
    reg [CW-1:0] count;
    reg active;
    assign pixel_x=sof?16'd0:x;assign pixel_y=sof?16'd0:y;
    assign pixel_valid=(sof||active)&&pixel_x<IMAGE_WIDTH&&pixel_y<IMAGE_HEIGHT&&
        (eol==(pixel_x==IMAGE_WIDTH-1));
    assign bbox_valid=0;assign prior_usable=0;
    assign xmin=0;assign xmax=0;assign ymin=0;assign ymax=0;
    wire [CW-1:0] next_count=(sof?{CW{1'b0}}:count)+(is_blue?1'b1:1'b0);
    always @(posedge clk)begin
        if(!resetn)begin
            x<=0;y<=0;count<=0;active<=0;result_pulse<=0;frame_error<=0;blue_pixel_count<=0;
        end else begin
            result_pulse<=0;frame_error<=0;
            if(accept)begin
                if(!pixel_valid)begin active<=0;frame_error<=1;blue_pixel_count<=0;end
                else begin
                    if(sof&&active)begin frame_error<=1;blue_pixel_count<=0;end
                    count<=next_count;active<=1;
                    if(eol)begin x<=0;y<=pixel_y+1'b1;end
                    else begin x<=pixel_x+1'b1;y<=pixel_y;end
                    if(eol&&pixel_y==IMAGE_HEIGHT-1)begin
                        active<=0;result_pulse<=1;blue_pixel_count<=next_count;
                    end
                end
            end
        end
    end
endmodule
