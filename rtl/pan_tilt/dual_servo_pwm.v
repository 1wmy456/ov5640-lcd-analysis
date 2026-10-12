module dual_servo_pwm #(
    parameter integer CLOCK_HZ=100000000, PERIOD_US=20000
)(input clk,resetn,
  input [1:0] enable_request,
  input commit,
  input [15:0] yaw_us,pitch_us,
  input [15:0] yaw_min,yaw_max,pitch_min,pitch_max,
  output servo_yaw_pwm,servo_pitch_pwm,
  output reg [15:0] active_yaw_us,active_pitch_us,
  output reg [1:0] active_enable,
  output reg pending,
  output reg [31:0] applied_sequence);
    localparam integer TICKS_PER_US=CLOCK_HZ/1000000;
    localparam integer PERIOD_TICKS=TICKS_PER_US*PERIOD_US;
    localparam integer COUNTER_WIDTH=$clog2(PERIOD_TICKS);
    reg [COUNTER_WIDTH-1:0] phase;
    reg [15:0] pending_yaw,pending_pitch;
    reg [COUNTER_WIDTH-1:0] yaw_ticks,pitch_ticks;
    reg yaw_level,pitch_level;
    function [15:0] clamp;
        input [15:0] v,lo,hi;
        begin clamp=v<lo?lo:(v>hi?hi:v);end
    endfunction
    assign servo_yaw_pwm=resetn && enable_request[0] && yaw_level;
    assign servo_pitch_pwm=resetn && enable_request[1] && pitch_level;
    always @(posedge clk) begin
        if(!resetn) begin
            phase<=0;active_enable<=0;pending<=0;applied_sequence<=0;
            yaw_level<=0;pitch_level<=0;
            active_yaw_us<=1500;active_pitch_us<=1500;
            pending_yaw<=1500;pending_pitch<=1500;
            yaw_ticks<=1500*TICKS_PER_US;pitch_ticks<=1500*TICKS_PER_US;
        end else begin
            if(phase==PERIOD_TICKS-1) begin
                phase<=0;active_enable<=enable_request;
                yaw_level<=enable_request[0]&&(pending?pending_yaw!=0:active_yaw_us!=0);
                pitch_level<=enable_request[1]&&(pending?pending_pitch!=0:active_pitch_us!=0);
                if(pending) begin
                    active_yaw_us<=pending_yaw;active_pitch_us<=pending_pitch;
                    yaw_ticks<=pending_yaw*TICKS_PER_US;pitch_ticks<=pending_pitch*TICKS_PER_US;
                    pending<=0;applied_sequence<=applied_sequence+1'b1;
                end
            end else begin
                phase<=phase+1'b1;active_enable<=active_enable&enable_request;
                yaw_level<=enable_request[0]&&active_enable[0]&&(phase+1'b1<yaw_ticks);
                pitch_level<=enable_request[1]&&active_enable[1]&&(phase+1'b1<pitch_ticks);
            end
            // Latest commit replaces a queued pair. A boundary-coincident commit
            // is queued for the NEXT boundary; an older pending pair applies now.
            if(commit) begin
                pending_yaw<=clamp(yaw_us,yaw_min,yaw_max);
                pending_pitch<=clamp(pitch_us,pitch_min,pitch_max);
                pending<=1;
            end
        end
    end
endmodule
