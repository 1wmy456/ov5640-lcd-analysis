// Combinational paint; the caller owns a frame-stable box snapshot.
module video_box_overlay #(
    parameter integer IMAGE_WIDTH = 800, IMAGE_HEIGHT = 480,
    parameter integer BORDER_WIDTH = 2, CENTER_CROSS = 0, CROSS_RADIUS = 4
)(
    input [23:0] pixel,
    input [15:0] x, y, xmin, xmax, ymin, ymax,
    input valid,
    output [23:0] painted
);
    wire inside_box = x >= xmin && x <= xmax && y >= ymin && y <= ymax;
    wire border = inside_box && BORDER_WIDTH > 0 &&
        (({1'b0,x} - {1'b0,xmin} < BORDER_WIDTH) ||
         ({1'b0,xmax} - {1'b0,x} < BORDER_WIDTH) ||
         ({1'b0,y} - {1'b0,ymin} < BORDER_WIDTH) ||
         ({1'b0,ymax} - {1'b0,y} < BORDER_WIDTH));
    wire [16:0] cx = ({1'b0,xmin} + {1'b0,xmax}) >> 1;
    wire [16:0] cy = ({1'b0,ymin} + {1'b0,ymax}) >> 1;
    wire cross_hit = CENTER_CROSS && inside_box &&
        ((x == cx && y + CROSS_RADIUS >= cy && y <= cy + CROSS_RADIUS) ||
         (y == cy && x + CROSS_RADIUS >= cx && x <= cx + CROSS_RADIUS));
    assign painted = valid && x < IMAGE_WIDTH && y < IMAGE_HEIGHT &&
                     xmax < IMAGE_WIDTH && ymax < IMAGE_HEIGHT &&
                     xmin <= xmax && ymin <= ymax && (border || cross_hit)
                     ? 24'h00ff00 : pixel;
endmodule
