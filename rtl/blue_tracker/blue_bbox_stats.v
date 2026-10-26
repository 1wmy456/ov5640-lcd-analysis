// Coordinates and statistics advance ONLY on an accepted input beat.
// Malformed frames are discarded; raw video/markers are never repaired here.
module blue_bbox_stats #(
    parameter integer IMAGE_WIDTH = 800, IMAGE_HEIGHT = 480,
    parameter integer MIN_PIXELS = 24, MIN_WIDTH = 3, MIN_HEIGHT = 3,
    parameter integer MIN_BLUE_RUN = 1,
    // 0 disables filtering; N uses 1/2^N of the new frame per update.
    parameter integer BBOX_FILTER_SHIFT = 0
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
    reg publish_pending, pending_valid;
    reg [15:0] pending_xmin, pending_xmax, pending_ymin, pending_ymax;
    reg [31:0] pending_count;
    // Only threshold attainment is needed internally; saturate these counters.
    // The externally reported raw blue count below remains a full 32-bit count.
    localparam integer Q_WIDTH = MIN_PIXELS < 2 ? 1 : $clog2(MIN_PIXELS+1);
    localparam integer RUN_WIDTH = MIN_BLUE_RUN < 2 ? 1 : $clog2(MIN_BLUE_RUN+1);
    reg [Q_WIDTH-1:0] qualified_count;
    reg [RUN_WIDTH-1:0] run_length;
    assign pixel_x = sof ? 16'd0 : x;
    assign pixel_y = sof ? 16'd0 : y;
    wire line_ok = (eol == (pixel_x == IMAGE_WIDTH-1));
    assign pixel_valid = (sof || active) && line_ok &&
                         pixel_x < IMAGE_WIDTH && pixel_y < IMAGE_HEIGHT;
    // Early SOF must not reuse an old result as though the interrupted frame completed.
    assign prior_usable = bbox_valid && !active;
    wire [31:0] next_count = (sof ? 32'd0 : count) + (is_blue ? 32'd1 : 32'd0);
    wire [16:0] next_run = is_blue ? (sof ? 17'd1 :
        (run_length < MIN_BLUE_RUN ? run_length+17'd1 : MIN_BLUE_RUN)) : 17'd0;
    wire qualified = is_blue && next_run >= MIN_BLUE_RUN;
    wire first_qualified = qualified && (sof || run_length < MIN_BLUE_RUN);
    // Upon reaching the minimum run, retroactively include its leading pixels.
    // This also covers a run which becomes qualified on EOL or the frame's last beat.
    wire [31:0] added = qualified ? (first_qualified ? MIN_BLUE_RUN : 32'd1) : 32'd0;
    wire [31:0] qualified_sum = (sof ? 32'd0 : qualified_count) + added;
    wire [31:0] next_qualified_count = qualified_sum >= MIN_PIXELS ? MIN_PIXELS : qualified_sum;
    wire [15:0] left_x = pixel_x - (first_qualified ? MIN_BLUE_RUN-1 : 0);
    wire [15:0] base_lx = sof ? 16'hffff : lo_x;
    wire [15:0] base_hx = sof ? 16'd0 : hi_x;
    wire [15:0] base_ly = sof ? 16'hffff : lo_y;
    wire [15:0] base_hy = sof ? 16'd0 : hi_y;
    wire [15:0] next_lx = qualified && left_x < base_lx ? left_x : base_lx;
    wire [15:0] next_hx = qualified && pixel_x > base_hx ? pixel_x : base_hx;
    wire [15:0] next_ly = qualified && pixel_y < base_ly ? pixel_y : base_ly;
    wire [15:0] next_hy = qualified && pixel_y > base_hy ? pixel_y : base_hy;
    wire next_bbox_valid = next_qualified_count != 0 && next_qualified_count >= MIN_PIXELS &&
        ({1'b0,next_hx} + 17'd1 >= {1'b0,next_lx} + MIN_WIDTH) &&
        ({1'b0,next_hy} + 17'd1 >= {1'b0,next_ly} + MIN_HEIGHT);
    localparam integer FILTER_ROUND = BBOX_FILTER_SHIFT > 0 ?
        (1 << (BBOX_FILTER_SHIFT-1)) : 0;
    function automatic [15:0] filtered_coord;
        input [15:0] previous_coord;
        input [15:0] current_coord;
        reg [16:0] delta;
        begin
            if (BBOX_FILTER_SHIFT == 0) filtered_coord = current_coord;
            else if (current_coord >= previous_coord) begin
                delta = current_coord - previous_coord;
                filtered_coord = previous_coord +
                    ((delta + FILTER_ROUND) >> BBOX_FILTER_SHIFT);
            end else begin
                delta = previous_coord - current_coord;
                filtered_coord = previous_coord -
                    ((delta + FILTER_ROUND) >> BBOX_FILTER_SHIFT);
            end
        end
    endfunction
    always @(posedge clk) begin
        if (!resetn) begin
            active <= 0; x <= 0; y <= 0; count <= 0; qualified_count <= 0; run_length <= 0;
            publish_pending <= 0; pending_valid <= 0; pending_count <= 0;
            pending_xmin <= 0; pending_xmax <= 0; pending_ymin <= 0; pending_ymax <= 0;
            lo_x <= 16'hffff; lo_y <= 16'hffff; hi_x <= 0; hi_y <= 0;
            bbox_valid <= 0; result_pulse <= 0; frame_error <= 0;
            xmin <= 0; xmax <= 0; ymin <= 0; ymax <= 0; blue_pixel_count <= 0;
        end else begin
            result_pulse <= 0; frame_error <= 0;
            // Filtering is deliberately one pipeline stage after frame close.
            // This keeps the last accepted pixel off the coordinate filter path.
            if (BBOX_FILTER_SHIFT != 0 && publish_pending) begin
                publish_pending <= 0;
                result_pulse <= 1;
                bbox_valid <= pending_valid;
                blue_pixel_count <= pending_count;
                if (!pending_valid) begin
                    xmin <= 0; xmax <= 0; ymin <= 0; ymax <= 0;
                end else if (bbox_valid) begin
                    xmin <= filtered_coord(xmin,pending_xmin);
                    xmax <= filtered_coord(xmax,pending_xmax);
                    ymin <= filtered_coord(ymin,pending_ymin);
                    ymax <= filtered_coord(ymax,pending_ymax);
                end else begin
                    xmin <= pending_xmin; xmax <= pending_xmax;
                    ymin <= pending_ymin; ymax <= pending_ymax;
                end
            end
            if (accept) begin
                if (!pixel_valid) begin
                    active <= 0; bbox_valid <= 0; blue_pixel_count <= 0; run_length <= 0;
                    xmin <= 0; xmax <= 0; ymin <= 0; ymax <= 0;
                    frame_error <= 1;
                end else begin
                    if (sof && active) begin
                        frame_error <= 1; bbox_valid <= 0; blue_pixel_count <= 0;
                    end
                    count <= next_count; lo_x <= next_lx; hi_x <= next_hx;
                    lo_y <= next_ly; hi_y <= next_hy;
                    qualified_count <= next_qualified_count;
                    run_length <= eol ? 0 : next_run[RUN_WIDTH-1:0];
                    active <= 1;
                    if (eol) begin x <= 0; y <= pixel_y + 1'b1; end
                    else begin x <= pixel_x + 1'b1; y <= pixel_y; end
                    if (eol && pixel_y == IMAGE_HEIGHT-1) begin
                        active <= 0;
                        // next_* includes this beat, including the last pixel in the frame.
                        if (BBOX_FILTER_SHIFT != 0) begin
                            publish_pending <= 1;
                            pending_valid <= next_bbox_valid;
                            pending_count <= next_count;
                            pending_xmin <= next_lx; pending_xmax <= next_hx;
                            pending_ymin <= next_ly; pending_ymax <= next_hy;
                        end else begin
                            result_pulse <= 1;
                            blue_pixel_count <= next_count;
                            bbox_valid <= next_bbox_valid;
                            if (!next_bbox_valid) begin
                                xmin <= 0; xmax <= 0; ymin <= 0; ymax <= 0;
                            end else begin
                                xmin <= next_lx; xmax <= next_hx;
                                ymin <= next_ly; ymax <= next_hy;
                            end
                        end
                    end
                end
            end
        end
    end
endmodule
