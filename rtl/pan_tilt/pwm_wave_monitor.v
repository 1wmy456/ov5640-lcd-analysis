// Observe the internal output net after reset/enable gating. This checks PL
// waveform generation, not voltage at the connector or servo terminal.
module pwm_wave_monitor(input clk,resetn,level,
    output reg [31:0] high_ticks,period_ticks,rise_count,
    output reg width_valid,period_valid);
    reg previous,seen_rise;
    reg [31:0] ticks,last_rise,high_count;
    always @(posedge clk) begin
        if(!resetn) begin
            previous<=0;seen_rise<=0;ticks<=0;last_rise<=0;high_count<=0;
            high_ticks<=0;period_ticks<=0;rise_count<=0;width_valid<=0;period_valid<=0;
        end else begin
            ticks<=ticks+1'b1;previous<=level;
            if(level&&!previous) begin
                high_count<=1;last_rise<=ticks;rise_count<=rise_count+1'b1;
                if(seen_rise) begin period_ticks<=ticks-last_rise;period_valid<=1;end
                seen_rise<=1;
            end else if(level) high_count<=high_count+1'b1;
            else if(previous) begin high_ticks<=high_count;width_valid<=1;end
        end
    end
endmodule
