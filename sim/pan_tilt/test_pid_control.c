#include "../../vitis/ov5640_lcd/src/pan_tilt/tracking_control.h"
#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <string.h>
static unsigned checks,frame;
static uint64_t stamp;
#define CHECK(x) do{checks++;if(!(x)){fprintf(stderr,"FAIL PID line=%d: %s\n",__LINE__,#x);exit(1);}}while(0)
#define NEAR(x,y) CHECK(fabs((x)-(y))<1e-8)
static PtTarget target(int ex,int ey){
    PtTarget t={0};t.frame_id=++frame;t.flags=5;
    t.xmin=398+ex;t.xmax=402+ex;t.ymin=238+ey;t.ymax=242+ey;return t;
}
static void tick(PtControl *c,int ex,int ey,unsigned us){
    PtTarget t=target(ex,ey);stamp+=us;pt_control_update(c,&t,stamp);
}
static void init(PtControl *c,int mode){
    pt_control_init(c,1);c->enabled=3;c->verified[0]=c->verified[1]=1;
    for(int a=0;a<2;a++){
        c->minimum[a]=500;c->maximum[a]=2500;c->gain[a]=0.7;c->rate[a]=75;
        c->acceleration[a]=400;c->deceleration[a]=600;
    }
    CHECK(pt_control_controller(c,mode));CHECK(pt_control_auto(c));
    frame=0;stamp=0;tick(c,0,0,20000);
}
static void basic(void){
    PtControl c,p,zero;double pos,v,d,i;
    pt_control_init(&c,1);CHECK(c.controller==PT_CONTROL_P&&c.ki[0]==0&&!c.enabled&&!c.automatic);
    CHECK(!pt_control_controller(&c,-1)&&!pt_control_controller(&c,3));
    CHECK(!pt_control_pid_gains(&c,-1,0,0)&&!pt_control_pid_gains(&c,2,0,0));
    CHECK(!pt_control_pid_gains(&c,0,NAN,0)&&!pt_control_pid_gains(&c,0,0,INFINITY));
    CHECK(!pt_control_pid_gains(&c,0,-0.1,0)&&!pt_control_pid_gains(&c,0,0.51,0));
    CHECK(!pt_control_pid_filter(&c,0,9,1000,10)&&!pt_control_pid_filter(&c,0,1001,1000,10));
    CHECK(!pt_control_pid_filter(&c,0,100,9,10)&&!pt_control_pid_filter(&c,0,100,1000,76));
    CHECK(!pt_control_pid_filter(&c,0,NAN,1000,10));
    init(&c,PT_CONTROL_PD);c.gain[0]=0;
    tick(&c,40,0,20000);NEAR(c.derivative[0],0); /* initial D never kicks */
    tick(&c,60,0,20000);NEAR(c.derivative[0],1000.0/6);NEAR(c.d_term[0],5);
    tick(&c,60,0,40000);NEAR(c.derivative[0],1000.0/6*5/7);
    CHECK(c.integral[0]==0);c.direction[0]=-1;
    tick(&c,80,0,20000);CHECK(c.d_term[0]<0);
    CHECK(fabs(c.derivative[0])<=1000);
    /* Clip an image discontinuity BEFORE the derivative low pass. */
    init(&c,PT_CONTROL_PD);c.gain[0]=0;
    tick(&c,-300,0,20000);tick(&c,300,0,20000);NEAR(c.derivative[0],1000.0/6);
    pos=c.position[0];v=c.velocity[0];d=c.derivative[0];i=c.integral[0];
    PtTarget t=target(300,0);t.frame_id=c.last_frame;stamp+=10000;
    CHECK(!pt_control_update(&c,&t,stamp));NEAR(c.position[0],pos);NEAR(c.derivative[0],d);
    NEAR(c.integral[0],i);NEAR(c.velocity[0],v);
    /* Timestamp equality and a 100ms gap cannot cause an exploding D. */
    t=target(-300,0);CHECK(!pt_control_update(&c,&t,c.last_update_us));NEAR(c.derivative[0],d);
    tick(&c,-300,0,100000);NEAR(c.derivative[0],0);
    /* Zero additional gains is exactly the old smooth P, including deadband. */
    init(&p,PT_CONTROL_P);zero=p;
    CHECK(pt_control_pid_gains(&zero,0,0,0)&&pt_control_pid_gains(&zero,1,0,0));
    CHECK(pt_control_controller(&zero,PT_CONTROL_PID));pt_control_controller(&p,PT_CONTROL_P);
    for(unsigned k=0;k<1200;k++){
        int ex=k<100?200:k<200?-180:k<600?(int)(k%9)+14:40;
        int ey=k<400?-100:k<800?15:60;
        t=target(ex,ey);stamp+=k%4?20000:40000;
        pt_control_update(&p,&t,stamp);pt_control_update(&zero,&t,stamp);
        for(int a=0;a<2;a++){NEAR(p.position[a],zero.position[a]);NEAR(p.velocity[a],zero.velocity[a]);}
    }
}
static void integral(void){
    PtControl c;init(&c,PT_CONTROL_PID);CHECK(pt_control_pid_gains(&c,0,0.2,0));
    tick(&c,30,0,20000); /* rebase after gain setter */
    for(unsigned k=0;k<300;k++){
        tick(&c,30,0,20000);CHECK(c.integral[0]>=0&&c.integral[0]<=10);
    }
    CHECK(c.integral[0]>9);double old=c.integral[0];
    tick(&c,-30,0,20000);CHECK(c.integral[0]<old); /* unwind during reverse braking */
    init(&c,PT_CONTROL_PID);pt_control_pid_gains(&c,0,0.2,0);
    for(unsigned k=0;k<200;k++){tick(&c,200,0,20000);NEAR(c.integral[0],0);CHECK(c.velocity[0]<=75);}
    init(&c,PT_CONTROL_PID);pt_control_pid_gains(&c,0,0.2,0);
    tick(&c,30,0,20000);tick(&c,30,0,20000);NEAR(c.integral[0],0); /* slew saturation */
    /* At both hard endpoints: cancel outward velocity/I, allow inward motion. */
    for(int sign=-1;sign<=1;sign+=2){
        init(&c,PT_CONTROL_PID);pt_control_pid_gains(&c,0,0.2,0.03);
        c.minimum[0]=1499;c.maximum[0]=1501;
        for(unsigned k=0;k<200;k++){
            tick(&c,200*sign,0,20000);CHECK(c.position[0]>=1499&&c.position[0]<=1501);
        }
        NEAR(c.position[0],sign>0?1501:1499);NEAR(c.integral[0],0);NEAR(c.velocity[0],0);
        for(unsigned k=0;k<5;k++)tick(&c,-200*sign,0,20000);
        CHECK(sign>0?c.position[0]<1501:c.position[0]>1499);
    }
    init(&c,PT_CONTROL_PID);pt_control_pid_gains(&c,0,0.2,0.03);
    for(unsigned k=0;k<100;k++)tick(&c,30,0,20000);
    CHECK(c.integral[0]>0);tick(&c,15,0,20000);NEAR(c.integral[0],0);NEAR(c.derivative[0],0);
    for(unsigned k=0;k<100;k++)tick(&c,15,0,20000);
    double pos=c.position[0];
    for(unsigned k=0;k<200;k++){tick(&c,16+(int)(k%7),0,20000);NEAR(c.position[0],pos);}
}
static void holds(void){
    PtControl c;PtTarget t;double pos;
    for(int why=0;why<7;why++){
        init(&c,PT_CONTROL_PID);pt_control_pid_gains(&c,0,0.2,0.03);
        for(unsigned k=0;k<100;k++)tick(&c,30,0,20000);
        CHECK(c.integral[0]>0&&c.velocity[0]>0);pos=c.position[0];t=target(50,0);
        if(why==0)t.flags=4;
        if(why==1)t.flags=6;
        if(why==2)t.age_us=250001;
        if(why==3){t.frame_id=c.last_frame;stamp+=300000;}
        if(why==4)c.enabled=0;
        if(why==5)c.dimensions_ok=0;
        if(why==6)pt_control_manual(&c);
        stamp+=20000;CHECK(!pt_control_update(&c,&t,stamp));
        NEAR(c.position[0],pos);NEAR(c.integral[0],0);NEAR(c.derivative[0],0);NEAR(c.velocity[0],0);
        CHECK(!c.derivative_ready[0]);
        c.enabled=3;c.dimensions_ok=1;CHECK(pt_control_auto(&c));
        tick(&c,-300,0,2000000);NEAR(c.position[0],pos);NEAR(c.derivative[0],0);
        tick(&c,-300,0,20000);NEAR(c.derivative[0],0);CHECK(fabs(c.position[0]-pos)<=0.080001);
    }
    init(&c,PT_CONTROL_PID);for(unsigned k=0;k<50;k++)tick(&c,100,0,20000);
    pos=c.position[0];int en=c.enabled;CHECK(pt_control_controller(&c,PT_CONTROL_PD));
    NEAR(c.position[0],pos);CHECK(c.enabled==en);NEAR(c.integral[0],0);NEAR(c.velocity[0],0);
    tick(&c,-200,0,20000);NEAR(c.position[0],pos);
    CHECK(pt_control_controller(&c,PT_CONTROL_P));NEAR(c.position[0],pos);
    pt_control_smooth(&c,0);CHECK(c.controller==PT_CONTROL_P&&!c.smooth_enabled);
    pt_control_controller(&c,PT_CONTROL_PD);CHECK(c.smooth_enabled);
    frame=0xfffffffeu;tick(&c,100,0,20000);tick(&c,100,0,20000);CHECK(frame==0&&c.tracking);
}
static void independent_axes(void){
    PtControl c;init(&c,PT_CONTROL_PID);
    CHECK(pt_control_pid_gains(&c,1,0.1,0.06));c.direction[1]=-1;
    for(unsigned k=0;k<150;k++){
        tick(&c,0,30,20000);NEAR(c.position[0],1500);NEAR(c.integral[0],0);
        CHECK(c.position[1]<1500||k==0);CHECK(c.integral[1]<=0);
    }
    CHECK(c.integral[1]<-5);double before=c.integral[1];
    tick(&c,0,-30,20000);CHECK(c.integral[1]>before);
    /* Derivative noise is attenuated while the target remains active. */
    init(&c,PT_CONTROL_PD);tick(&c,100,0,20000);
    double maximum=0;
    for(unsigned k=0;k<200;k++){
        tick(&c,k%2?102:98,0,20000);
        double v=fabs(c.derivative[0]);if(v>maximum)maximum=v;
        CHECK(c.integral[0]==0&&fabs(c.velocity[0])<=75);
    }
    CHECK(maximum<50); /* raw difference reaches 200 px/s */
}
/* Synthetic camera/servo plant, not a physical trajectory measurement.
   Scene pixel coordinate = initial offset - scale*(actual servo - start).
   First-order servo lag and delayed camera samples exercise a closed loop. */
static void plant(FILE *trace,int mode,int direction,double scale){
    PtControl c;double actual=1500,history[16],lastpos=1500,lastv=0;unsigned near=0;
    init(&c,mode);c.direction[0]=direction;
    CHECK(pt_control_pid_gains(&c,0,mode==PT_CONTROL_PID?0.01:0,0.03));
    for(int j=0;j<16;j++)history[j]=1500;
    for(unsigned k=0;k<1200;k++){
        double sensed=history[(k+16-4)%16];
        int ex=(int)lround(150-direction*scale*(sensed-1500));
        if(ex>395)ex=395;
        if(ex< -395)ex=-395;
        double before=c.position[0],oldv=c.velocity[0];
        tick(&c,ex,0,20000);
        CHECK(isfinite(c.position[0])&&isfinite(c.integral[0])&&isfinite(c.derivative[0]));
        CHECK(fabs(c.velocity[0])<=75.000001);
        CHECK(fabs(c.velocity[0]-oldv)<=12.000001);
        CHECK(fabs(c.position[0]-before)<=1.500001);
        CHECK(c.position[0]>=500&&c.position[0]<=2500);
        actual+=(c.position[0]-actual)*0.02/0.12;history[k%16]=actual;
        if(k>900&&abs(ex)<=22)near++;
        if(trace)fprintf(trace,"%d,%d,%.2f,%u,%d,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f\n",
            mode,direction,scale,k,ex,c.position[0],actual,c.velocity[0],c.p_term[0],c.integral[0],c.d_term[0]);
        lastpos=c.position[0];lastv=c.velocity[0];
    }
    CHECK(near>280);CHECK(fabs(lastv)<1e-8);
    printf("PLANT synthetic mode=%d direction=%d scale=%.2f final_us=%.3f settled_samples=%u\n",mode,direction,scale,lastpos,near);
}
int main(int argc,char **argv){
    FILE *trace=argc>1?fopen(argv[1],"w"):NULL;if(argc>1)CHECK(trace!=NULL);
    if(trace)fprintf(trace,"mode,direction,assumed_px_per_us,sample,error_px,command_us,assumed_actual_us,velocity_us_s,p_us_s,i_us_s,d_us_s\n");
    basic();integral();holds();independent_axes();
    for(int mode=PT_CONTROL_P;mode<=PT_CONTROL_PID;mode++)
        for(int direction=-1;direction<=1;direction+=2)
            for(int s=0;s<3;s++)plant(direction==1&&s==1?trace:NULL,mode,direction,0.8+0.5*s);
    if(trace)fclose(trace);
    printf("PASS VISUAL_PID checks=%u; P/PD/PID/filter/sign/actual-dt/anti-windup/slew/limits/hysteresis/holds/recovery/switch/wrap/synthetic-plants\n",checks);
    return 0;
}
