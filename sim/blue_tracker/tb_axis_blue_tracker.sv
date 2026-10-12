`timescale 1ns/1ps
module tb_axis_blue_tracker;
    parameter MIN_PIXELS=4, MIN_WIDTH=2, MIN_HEIGHT=2, CENTER_CROSS=0;
    localparam W=12,H=8,N=20000;
    reg clk=0; always #5 clk=~clk;
    reg rst=0,sv=0,su=0,sl=0,ready=0;
    reg [23:0] sd=0;
    wire [2:0] sr,mv,mu,ml,bv,rp,fe;
    wire [23:0] md[0:2];
    wire [15:0] bx0[0:2],bx1[0:2],by0[0:2],by1[0:2];
    wire [31:0] bc[0:2];
    genvar m;
    generate for(m=0;m<3;m=m+1) begin:duts
        axis_blue_tracker #(.IMAGE_WIDTH(W),.IMAGE_HEIGHT(H),.MODE(m),
            .MIN_PIXELS(MIN_PIXELS),.MIN_WIDTH(MIN_WIDTH),.MIN_HEIGHT(MIN_HEIGHT),
            .CENTER_CROSS(CENTER_CROSS)) dut(
            .aclk(clk),.aresetn(rst),.s_axis_tdata(sd),.s_axis_tvalid(sv),
            .s_axis_tready(sr[m]),.s_axis_tuser(su),.s_axis_tlast(sl),
            .m_axis_tdata(md[m]),.m_axis_tvalid(mv[m]),.m_axis_tready(ready),
            .m_axis_tuser(mu[m]),.m_axis_tlast(ml[m]),.bbox_valid(bv[m]),
            .result_pulse(rp[m]),.frame_error(fe[m]),.bbox_xmin(bx0[m]),
            .bbox_xmax(bx1[m]),.bbox_ymin(by0[m]),.bbox_ymax(by1[m]),.blue_pixel_count(bc[m]));
    end endgenerate
    // Independent byte-order and overflow boundary tests.
    reg [23:0] color;
    wire rgb_blue,bgr_blue;
    blue_pixel_detect rgb(color,rgb_blue);
    blue_pixel_detect #(.R_BYTE(0),.B_BYTE(2)) bgr(color,bgr_blue);
    integer checks=0,failures=0,frames=0,errors_seen=0,inputs=0,outputs=0,stalls=0,bubbles=0;
    integer head=0,tail=0,k,j;
    reg [25:0] expected[0:2][0:N-1];
    reg stalled[0:2]; reg [25:0] held[0:2];
    integer x=0,y=0,cnt=0,lx=W,hx=0,ly=H,hy=0;
    integer rx0=0,rx1=0,ry0=0,ry1=0,rc=0;
    integer dx0=0,dx1=0,dy0=0,dy1=0;
    reg active=0,rv=0,dv=0,blue,good,paint,exp_pulse,exp_error;
    reg [23:0] ep;
    reg random_ready=1;
    integer seed=32'h12345678;
    reg [31:0] ready_rng=32'hca153781;
    task check(input bit ok,input string msg);
        begin checks=checks+1; assert(ok) else begin
            failures=failures+1;
            $display("FAIL t=%0t input=%0d output=%0d %s",$time,inputs,outputs,msg); $fatal(1);
        end end
    endtask
    always @(negedge clk) if(random_ready) begin
        ready_rng={ready_rng[30:0],ready_rng[31]^ready_rng[21]^ready_rng[1]^ready_rng[0]};
        ready = (ready_rng[1:0] != 0);
    end
    always @(posedge clk) begin
        if(!rst) begin
            head=0; tail=0; active=0; rv=0;dv=0;x=0;y=0;rc=0;
            rx0=0;rx1=0;ry0=0;ry1=0;
            for(k=0;k<3;k=k+1) stalled[k]=0;
        end else begin
            check(sr=== {3{sr[0]}} && mv==={3{mv[0]}},"mode handshake agreement");
            for(k=0;k<3;k=k+1) begin
                if(stalled[k]) check(mv[k] && {mu[k],ml[k],md[k]}===held[k],"AXI output stable under backpressure");
                stalled[k]=mv[k]&&!ready;
                held[k]={mu[k],ml[k],md[k]};
            end
            if(mv[0]&&!ready) stalls=stalls+1;
            if(!sv) bubbles=bubbles+1;
            // Consume before enqueue: catches duplicates and unexpected latency-zero output.
            if(mv[0]&&ready) begin
                check(head<tail,"no extra output beats");
                for(k=0;k<3;k=k+1)
                    check({mu[k],ml[k],md[k]}===expected[k][head],"pixel/SOF/EOL scoreboard");
                head=head+1; outputs=outputs+1;
            end
            exp_pulse=0; exp_error=0;
            if(sv&&sr[0]) begin
                inputs=inputs+1;
                blue=(sd[7:0]>=80 && int'(sd[7:0])>int'(sd[23:16])+35 &&
                      int'(sd[7:0])>int'(sd[15:8])+20);
                if(su) begin
                    dv=rv&&!active;dx0=rx0;dx1=rx1;dy0=ry0;dy1=ry1;
                    exp_error=active; x=0;y=0;cnt=0;lx=W;hx=0;ly=H;hy=0;
                end
                good=(su||active) && x<W && y<H && (sl==(x==W-1));
                paint=dv&&good&&x>=dx0&&x<=dx1&&y>=dy0&&y<=dy1 &&
                    ((x-dx0<2)||(dx1-x<2)||(y-dy0<2)||(dy1-y<2)||
                     (CENTER_CROSS && ((x==(dx0+dx1)/2 &&
                       y>= (dy0+dy1)/2-4 && y<=(dy0+dy1)/2+4)||
                      (y==(dy0+dy1)/2 && x>=(dx0+dx1)/2-4 && x<=(dx0+dx1)/2+4))));
                expected[0][tail]={su,sl,sd};
                expected[1][tail]={su,sl,(blue ? 24'hffffff : 24'h000000)};
                expected[2][tail]={su,sl,(paint ? 24'h00ff00 : sd)};
                tail=tail+1;check(tail<N,"scoreboard capacity");
                if(!good) begin
                    active=0;rv=0;rc=0;rx0=0;rx1=0;ry0=0;ry1=0;exp_error=1;
                end else begin
                    if(exp_error) begin rv=0;rc=0; end
                    if(blue) begin
                        cnt=cnt+1;if(x<lx)lx=x;if(x>hx)hx=x;if(y<ly)ly=y;if(y>hy)hy=y;
                    end
                    active=1;
                    if(sl && y==H-1) begin
                        active=0;exp_pulse=1;frames=frames+1;rc=cnt;
                        rv=cnt>0&&cnt>=MIN_PIXELS&&hx-lx+1>=MIN_WIDTH&&hy-ly+1>=MIN_HEIGHT;
                        rx0=cnt ? lx:0;rx1=cnt ? hx:0;ry0=cnt ? ly:0;ry1=cnt ? hy:0;
                    end
                    if(sl) begin x=0;y=y+1;end else x=x+1;
                end
                if(exp_error)errors_seen=errors_seen+1;
            end
            #1;
            for(k=0;k<3;k=k+1) begin
                check(bv[k]===rv && bc[k]===rc && rp[k]===exp_pulse && fe[k]===exp_error,
                    "bbox valid/count/pulse/error and no-accept stability");
                check(bx0[k]==rx0 && bx1[k]==rx1 && by0[k]==ry0 && by1[k]==ry1,"bbox coordinates");
            end
        end
    end
    task beat(input [23:0] p,input bit sof,input bit eol,input bit gap);
        begin
            @(negedge clk);sd=p;su=sof;sl=eol;sv=1;
            do @(posedge clk); while(!sr[0]);
            @(negedge clk);sv=0;
            if(gap) repeat($urandom(seed)%3) @(negedge clk);
        end
    endtask
    function automatic [23:0] image(input integer kind,xx,yy);
        bit b;
        begin
            b=0;
            case(kind)
              1:b=xx>=3&&xx<=8&&yy>=2&&yy<=5;
              2:b=(xx-6)*(xx-6)+(yy-4)*(yy-4)<=9;
              3:b=xx<=3&&yy<=3;
              4:b=xx>=9&&yy>=5;
              5:b=xx>=5&&xx<=6;
              6,7,8:b=xx>=kind-5&&xx<=kind&&yy>=2&&yy<=5;
              9:b=xx==5&&yy==4;
              10:b=xx==W-1&&yy==H-1;
              11:begin
                  case(xx%6)
                    0:image=24'hff0000;1:image=24'h00ff00;2:image=24'h0000ff;
                    3:image=24'hffffff;4:image=24'h000000;5:image=24'hff00ff;
                  endcase
              end
              12:b=1;
              13:b=yy==3;
              14:b=xx==6;
              15:b=(xx<=2&&yy<=2)||(xx>=9&&yy>=5);
              16:b=(xx>=3&&xx<=8&&yy>=2&&yy<=5)||(xx==W-1&&yy==H-1);
            endcase
            if(kind!=11) image=b?24'h1020c8:24'h302010;
            if(kind==0)image=0;
        end
    endfunction
    task frame(input integer kind);
        integer xx,yy;
        begin
            $display("CASE kind=%0d",kind);
            for(yy=0;yy<H;yy=yy+1) for(xx=0;xx<W;xx=xx+1)
                beat(image(kind,xx,yy),xx==0&&yy==0,xx==W-1,1);
        end
    endtask
    initial begin
        color=24'h0000ff;#1;check(rgb_blue&&!bgr_blue,"RGB blue bar");
        color=24'hff0000;#1;check(!rgb_blue&&bgr_blue,"BGR blue bar");
        color=24'h00ff00;#1;check(!rgb_blue&&!bgr_blue,"green bar");
        color=24'hfa00ff;#1;check(!rgb_blue,"R+35 overflow rejection");
        color=24'h00faff;#1;check(!rgb_blue,"G+20 overflow rejection");
        color=24'h2d3b50;#1;check(!rgb_blue,"strict B=R+35 boundary");
        color=24'h003c50;#1;check(!rgb_blue,"strict B=G+20 boundary");
        color=24'h002050;#1;check(rgb_blue,"inclusive B=80 boundary");
        repeat(4)@(negedge clk);rst=1;
        frame(0);frame(1);frame(1);frame(2);frame(3);frame(4);frame(5);
        frame(6);frame(7);frame(8);frame(0);frame(0);frame(9);frame(10);frame(11);
        frame(13);frame(14);frame(15);frame(16);frame(0);
        // Early EOL, missing EOL, early SOF, excess height, missing initial SOF.
        beat(24'h0000ff,1,0,0);beat(24'h0000ff,0,1,0);frame(1);
        for(j=0;j<W;j=j+1)beat(24'h0000ff,j==0,0,0);frame(1);
        beat(24'h0000ff,1,0,0);beat(24'h0000ff,0,0,0);frame(3);
        beat(24'h0000ff,0,0,0);frame(0);
        // Consecutive frames with NO TVALID gaps, and extended stalls across SOF/EOL.
        random_ready=0;ready=1;
        @(negedge clk);sv=1;
        for(j=0;j<2*W*H;j=j+1)begin
            sd=image(12,j%W,(j/W)%H);su=(j%(W*H)==0);sl=(j%W==W-1);
            @(posedge clk);@(negedge clk);
        end
        sv=0;random_ready=1;frame(0);
        @(negedge clk);#1;random_ready=0;ready=0;
        beat(24'h0000ff,1,0,0);repeat(15)@(negedge clk);
        // Reset cancels the single pending output beat and clears first-frame result.
        rst=0;sv=0;repeat(3)@(negedge clk);rst=1;ready=1;
        frame(1);frame(1);frame(0);frame(0);
        repeat(5)@(negedge clk);
        check(head==tail,"all accepted beats drained");
        check(stalls>0&&bubbles>0&&errors_seen>=4,"stress coverage");
        $display("PASS checks=%0d failures=%0d complete_frames=%0d errors_seen=%0d accepted=%0d output=%0d stalls=%0d bubbles=%0d MIN=%0d/%0d/%0d CROSS=%0d",
                 checks,failures,frames,errors_seen,inputs,outputs,stalls,bubbles,MIN_PIXELS,MIN_WIDTH,MIN_HEIGHT,CENTER_CROSS);
        $finish;
    end
    initial begin #2000000;$fatal(1,"watchdog timeout");end
endmodule
module tb_single_pixel;
    tb_axis_blue_tracker #(.MIN_PIXELS(1),.MIN_WIDTH(1),.MIN_HEIGHT(1)) test();
endmodule
module tb_cross;
    tb_axis_blue_tracker #(.CENTER_CROSS(1)) test();
endmodule
