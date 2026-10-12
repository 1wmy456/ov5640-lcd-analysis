// Coordinates and statistics advance ONLY on an accepted input beat.
// Malformed frames are discarded; raw video/markers are never repaired here.
module blue_bbox_stats #(
    parameter integer IMAGE_WIDTH = 800, IMAGE_HEIGHT = 480,
    parameter integer MIN_PIXELS = 24, MIN_WIDTH = 3, MIN_HEIGHT = 3
)(
    input clk, resetn, accept, sof, eol, is_blue,
    output [15:0] pixel_x, pixel_y,
    output pixel_valid, prior_usable,
    output reg bbox_valid, result_pulse, frame_error,
    output reg [15:0] xmin, xmax, ymin, ymax,
    output reg [31:0] blue_pixel_count
);
    reg active;
    reg [15:0] x, y, lo_x, hi_x, lo_y, hi_y;
    reg [31:0] count;
    assign pixel_x = sof ? 16'd0 : x;
    assign pixel_y = sof ? 16'd0 : y;
    wire line_ok = (eol == (pixel_x == IMAGE_WIDTH-1));
    assign pixel_valid = (sof || active) && line_ok &&
                         pixel_x < IMAGE_WIDTH && pixel_y < IMAGE_HEIGHT;
    // Early SOF must not reuse an old result as though the interrupted frame completed.
    assign prior_usable = bbox_valid && !active;
    wire [31:0] next_count = (sof ? 32'd0 : count) + (is_blue ? 32'd1 : 32'd0);
    wire [15:0] next_lx = sof ? (is_blue ? 16'd0 : 16'hffff) :
                            ((is_blue && pixel_x < lo_x) ? pixel_x : lo_x);
    wire [15:0] next_hx = sof ? 16'd0 : ((is_blue && pixel_x > hi_x) ? pixel_x : hi_x);
    wire [15:0] next_ly = sof ? (is_blue ? 16'd0 : 16'hffff) :
                            ((is_blue && pixel_y < lo_y) ? pixel_y : lo_y);
    wire [15:0] next_hy = sof ? 16'd0 : ((is_blue && pixel_y > hi_y) ? pixel_y : hi_y);
    always @(posedge clk) begin
        if (!resetn) begin
            active <= 0; x <= 0; y <= 0; count <= 0;
            lo_x <= 16'hffff; lo_y <= 16'hffff; hi_x <= 0; hi_y <= 0;
            bbox_valid <= 0; result_pulse <= 0; frame_error <= 0;
            xmin <= 0; xmax <= 0; ymin <= 0; ymax <= 0; blue_pixel_count <= 0;
        end else begin
            result_pulse <= 0; frame_error <= 0;
            if (accept) begin
                if (!pixel_valid) begin
                    active <= 0; bbox_valid <= 0; blue_pixel_count <= 0;
                    xmin <= 0; xmax <= 0; ymin <= 0; ymax <= 0;
                    frame_error <= 1;
                end else begin
                    if (sof && active) begin
                        frame_error <= 1; bbox_valid <= 0; blue_pixel_count <= 0;
                    end
                    count <= next_count; lo_x <= next_lx; hi_x <= next_hx;
                    lo_y <= next_ly; hi_y <= next_hy;
                    active <= 1;
                    if (eol) begin x <= 0; y <= pixel_y + 1'b1; end
                    else begin x <= pixel_x + 1'b1; y <= pixel_y; end
                    if (eol && pixel_y == IMAGE_HEIGHT-1) begin
                        active <= 0; result_pulse <= 1;
                        blue_pixel_count <= next_count;
                        // next_* includes this beat, including the last pixel in the frame.
                        bbox_valid <= next_count != 0 && next_count >= MIN_PIXELS &&
                            ({1'b0,next_hx} + 17'd1 >= {1'b0,next_lx} + MIN_WIDTH) &&
                            ({1'b0,next_hy} + 17'd1 >= {1'b0,next_ly} + MIN_HEIGHT);
                        xmin <= next_count == 0 ? 16'd0 : next_lx;
                        xmax <= next_count == 0 ? 16'd0 : next_hx;
                        ymin <= next_count == 0 ? 16'd0 : next_ly;
                        ymax <= next_count == 0 ? 16'd0 : next_hy;
                    end
                end
            end
        end
    end
endmodule
