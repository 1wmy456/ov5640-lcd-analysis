// Side-band binary mask. Never participates in AXIS ready/valid generation.
// Each BLOCK x BLOCK cell is foreground when at least CELL_MIN pixels are blue.
module blue_mask_sampler #(
    parameter integer IMAGE_WIDTH=800, IMAGE_HEIGHT=480, BLOCK=4, CELL_MIN=4
)(
    input clk,resetn,accept,sof,eol,is_blue,pixel_valid,
    input [15:0] x,y,
    output reg mask_start,mask_word_valid,mask_frame_done,
    output reg [9:0] mask_word_address,
    output reg [31:0] mask_word_data
);
    localparam integer GW=IMAGE_WIDTH/BLOCK;
    localparam integer CW=$clog2(BLOCK*BLOCK+1);
    reg [CW-1:0] cells[0:GW-1];
    reg [31:0] packed_word;
    reg [4:0] bit_index;
    reg [9:0] word_index;
    reg [CW:0] sum;
    reg [31:0] next_word;
    wire cell_end=(x%BLOCK==BLOCK-1)&&(y%BLOCK==BLOCK-1);
    always @(posedge clk) begin
        if(!resetn) begin
            mask_start<=0;mask_word_valid<=0;mask_frame_done<=0;
            mask_word_address<=0;mask_word_data<=0;
            packed_word<=0;bit_index<=0;word_index<=0;
        end else begin
            mask_start<=0;mask_word_valid<=0;mask_frame_done<=0;
            if(accept&&pixel_valid) begin
                if(sof) begin
                    mask_start<=1;packed_word<=0;bit_index<=0;word_index<=0;
                end
                // Every column accumulator is initialized by its first cell pixel,
                // so no bulk RAM reset is needed, including recovery after bad frames.
                sum=(((y%BLOCK)==0)&&((x%BLOCK)==0)?0:cells[x/BLOCK])+(is_blue?1:0);
                cells[x/BLOCK]<=sum;
                if(cell_end) begin
                    next_word=packed_word;
                    next_word[bit_index]=(sum>=CELL_MIN);
                    if(bit_index==31||(eol&&y==IMAGE_HEIGHT-1)) begin
                        mask_word_valid<=1;mask_word_address<=word_index;
                        mask_word_data<=next_word;
                        word_index<=word_index+1'b1;bit_index<=0;packed_word<=0;
                    end else begin
                        bit_index<=bit_index+1'b1;packed_word<=next_word;
                    end
                end
                if(eol&&y==IMAGE_HEIGHT-1)mask_frame_done<=1;
            end
        end
    end
endmodule
