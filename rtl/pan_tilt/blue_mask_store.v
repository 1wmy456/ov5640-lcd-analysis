// Three banks: current capture, latest complete frame, and PS locked snapshot.
// Snapshot reads can stall indefinitely without backpressuring the camera.
module blue_mask_store #(
    parameter integer IMAGE_WIDTH=800,IMAGE_HEIGHT=480,BLOCK=4
)(
    input clk,resetn,us_tick,frame_error,
    input mask_start,mask_word_valid,mask_frame_done,
    input [9:0] mask_word_address,
    input [31:0] mask_word_data,
    input acquire,release_snapshot,
    input read_enable,input [9:0] read_index,
    output reg [31:0] read_data,
    output reg locked,
    output reg [31:0] snap_frame,snap_flags,snap_age,snap_errors,
    output reg [31:0] live_frame,live_age,error_count,
    output reg live_error,
    output reg [31:0] snapshot_current_age
);
    localparam integer WORDS=((IMAGE_WIDTH/BLOCK)*(IMAGE_HEIGHT/BLOCK)+31)/32;
    (* ram_style="block" *) reg [31:0] memory[0:3*WORDS-1];
    reg [1:0] capture_bank,latest_bank,read_bank;
    reg capturing,initialized;
    reg [1:0] free_bank;
    always @(*) begin
        if((!initialized||latest_bank!=0)&&(!locked||read_bank!=0))free_bank=0;
        else if((!initialized||latest_bank!=1)&&(!locked||read_bank!=1))free_bank=1;
        else free_bank=2;
    end
    // One synchronous read port and one write port, both on the video AXI clock.
    always @(posedge clk) begin
        if(mask_word_valid&&capturing&&mask_word_address<WORDS)
            memory[capture_bank*WORDS+mask_word_address]<=mask_word_data;
        if(read_enable&&locked&&read_index<WORDS)
            read_data<=memory[read_bank*WORDS+read_index];
    end
    always @(posedge clk) begin
        if(!resetn) begin
            capture_bank<=0;latest_bank<=0;read_bank<=0;capturing<=0;initialized<=0;
            locked<=0;snap_frame<=0;snap_flags<=0;snap_age<=0;snap_errors<=0;
            live_frame<=0;live_age<=32'hffffffff;error_count<=0;live_error<=0;
            snapshot_current_age<=32'hffffffff;
        end else begin
            if(us_tick) begin
                if(live_age!=32'hffffffff)live_age<=live_age+1'b1;
                if(snapshot_current_age!=32'hffffffff)snapshot_current_age<=snapshot_current_age+1'b1;
            end
            if(mask_start) begin capture_bank<=free_bank;capturing<=1;end
            if(mask_frame_done&&capturing) begin
                latest_bank<=capture_bank;live_frame<=live_frame+1'b1;
                initialized<=1;live_age<=0;live_error<=0;capturing<=0;
            end
            if(frame_error) begin
                capturing<=0;live_error<=1;error_count<=error_count+1'b1;
            end
            if(release_snapshot)locked<=0;
            if(acquire&&!locked) begin
                // Concurrent frame completion intentionally snapshots the previous
                // complete bank. It never races the final write into capture_bank.
                locked<=1;read_bank<=latest_bank;snap_frame<=live_frame;
                snap_flags<={29'd0,initialized,(live_error|frame_error),(initialized&&!live_error&&!frame_error)};
                snap_age<=live_age;snapshot_current_age<=live_age;
                snap_errors<=error_count+(frame_error?1:0);
            end
        end
    end
endmodule
