`timescale 1ns/1ps
// Exercise the installed Vivado 2020.2 Video In RTL, including its async FIFO.
// No vendor source is copied into this repository.
module tb_video_in_color_order;
    reg aclk=0,vclk=0;always #5 aclk=~aclk;always #7 vclk=~vclk;
    reg resetn=0,vreset=1,de=0,vs=0;
    reg [23:0] data=0;
    wire [23:0] axis_data,mask;
    wire av,ar,au,al,mv,mu,ml,overflow;
    reg ready=1;
    integer n=0,frames=0,pixels=0,checks=0,xx,yy,f;
    reg [31:0] rng=32'h541acd89;
    function automatic [23:0] bars(input integer x);
        case(x%6)
            0:bars=24'hff0000;1:bars=24'h00ff00;2:bars=24'h0000ff;
            3:bars=24'hffffff;4:bars=24'h000000;5:bars=24'hff00ff;
        endcase
    endfunction
    v_vid_in_axi4s_v4_0_9 #(.C_FAMILY("zynq"),.C_HAS_ASYNC_CLK(1),.C_ADDR_WIDTH(10),
        .C_NATIVE_COMPONENT_WIDTH(8),.C_M_AXIS_COMPONENT_WIDTH(8),
        .C_PIXELS_PER_CLOCK(1),.C_COMPONENTS_PER_PIXEL(3),
        .C_INCLUDE_PIXEL_DROP(0),.C_INCLUDE_PIXEL_REMAP_420(0)) video_in(
        .vid_io_in_clk(vclk),.vid_io_in_ce(1'b1),.vid_io_in_reset(vreset),
        .vid_active_video(de),.vid_vblank(1'b0),.vid_hblank(1'b0),
        .vid_vsync(vs),.vid_hsync(1'b0),.vid_field_id(1'b0),.vid_data(data),
        .aclk(aclk),.aclken(1'b1),.aresetn(resetn),.m_axis_video_tdata(axis_data),
        .m_axis_video_tvalid(av),.m_axis_video_tready(ar),.m_axis_video_tuser(au),
        .m_axis_video_tlast(al),.axis_enable(1'b1),.drop_en(1'b0),.remap_420_en(1'b0),
        .overflow(overflow));
    axis_blue_tracker #(.IMAGE_WIDTH(12),.IMAGE_HEIGHT(8),.MODE(1)) tracker(
        .aclk(aclk),.aresetn(resetn),.s_axis_tdata(axis_data),.s_axis_tvalid(av),
        .s_axis_tready(ar),.s_axis_tuser(au),.s_axis_tlast(al),.m_axis_tdata(mask),
        .m_axis_tvalid(mv),.m_axis_tready(ready),.m_axis_tuser(mu),.m_axis_tlast(ml));
    task check(input bit ok,input string message);
        begin checks=checks+1;assert(ok) else begin $display("FAIL IP color %s",message);$fatal(1);end end
    endtask
    integer idx=0;
    reg [25:0] q[0:1023];integer head=0,tail=0;
    always @(negedge aclk)begin
        rng={rng[30:0],rng[31]^rng[21]^rng[1]^rng[0]};ready=(rng[1:0]!=0);
    end
    always @(posedge aclk) if(resetn)begin
        check(!overflow,"native FIFO overflow");
        if(mv&&ready)begin
            check(head<tail,"mask output queue");
            check({mu,ml,mask}===q[head],"mask and markers aligned");head=head+1;
        end
        if(av&&ar)begin
            if(au)begin check(n==0||n==96,"full preceding frame");n=0;frames=frames+1;end
            check(frames>0,"first beat SOF");
            check(axis_data===bars(n%12),"native bytes preserved through Video In");
            check(al==(n%12==11),"EOL at pixel 11");
            q[tail]={au,al,(n%6==2 ? 24'hffffff:24'h000000)};tail=tail+1;
            n=n+1;pixels=pixels+1;
        end
    end
    initial begin
        repeat(30)@(negedge vclk);vreset=0;resetn=1;
        repeat(30)@(negedge vclk);
        for(f=0;f<3;f=f+1)begin
            vs=1;repeat(8)@(negedge vclk);vs=0;repeat(8)@(negedge vclk);
            for(yy=0;yy<8;yy=yy+1)begin
                for(xx=0;xx<12;xx=xx+1)begin de=1;data=bars(xx);@(negedge vclk);end
                de=0;data=0;repeat(8)@(negedge vclk);
            end
            repeat(20)@(negedge vclk);
        end
        repeat(100)@(negedge vclk);
        check(frames==3&&pixels==288&&head==tail&&n==96,"three frames fully received");
        $display("PASS IP_COLOR checks=%0d frames=%0d pixels=%0d RGB byte order R=2 G=1 B=0 async CDC preserved",checks,frames,pixels);$finish;
    end
    initial begin #200000;$display("FAIL IP color watchdog");$fatal(1);end
endmodule
