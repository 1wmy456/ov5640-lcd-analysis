#include "../../vitis/ov5640_lcd/src/pan_tilt/tracking_control.h"
#include <stdio.h>
#include <stdlib.h>
#include <math.h>
static unsigned checks,frame;
static uint64_t stamp;
static double test_accel=200,test_decel=400;
#define CHECK(x) do{checks++;if(!(x)){fprintf(stderr,"FAIL smooth line=%d check=%s\n",__LINE__,#x);exit(1);}}while(0)
static PtTarget target(int ex,int ey){
    PtTarget t={0};t.frame_id=++frame;t.flags=5;
    t.xmin=398+ex;t.xmax=402+ex;t.ymin=238+ey;t.ymax=242+ey;return t;
}
static void init(PtControl *c){
    pt_control_init(c,1);c->enabled=3;c->verified[0]=c->verified[1]=1;
    for(int a=0;a<2;a++){c->minimum[a]=500;c->maximum[a]=2500;c->gain[a]=0.7;c->rate[a]=75;
        c->acceleration[a]=test_accel;c->deceleration[a]=test_decel;}
    CHECK(pt_control_auto(c));frame=0;stamp=0;
    PtTarget t=target(0,0);CHECK(!pt_control_update(c,&t,stamp));
}
static void tick(PtControl *c,int ex,int ey,unsigned dt){
    PtTarget t=target(ex,ey);stamp+=dt;pt_control_update(c,&t,stamp);
}
int main(int argc,char **argv){
    if(argc>3){test_accel=strtod(argv[2],NULL);test_decel=strtod(argv[3],NULL);}
    PtControl c,old;double p,v,previous,max_start=0,max_old_start=0;unsigned old_edges=0,new_edges=0;
    FILE *trace=argc>1?fopen(argv[1],"w"):NULL;
    if(argc>1)CHECK(trace!=NULL);
    if(trace)fprintf(trace,"sample,phase,error,position_us,velocity_us_s,legacy_position_us\n");
    init(&c);init(&old);pt_control_smooth(&old,0);
    /* A large target step: startup acceleration and speed bounds under 20/40ms sampling. */
    for(unsigned i=0;i<80;i++){
        unsigned dt=i%4==0?40000:20000;double seconds=dt/1000000.0;
        double before=c.position[0],old_before=old.position[0];previous=c.velocity[0];
        PtTarget t=target(200,-180);stamp+=dt;
        pt_control_update(&c,&t,stamp);pt_control_update(&old,&t,stamp);
        CHECK(c.velocity[0]>=0&&c.velocity[0]<=75);
        CHECK(c.velocity[0]-previous<=test_accel*seconds+1e-8);
        CHECK(fabs(c.velocity[1])<=75);
        CHECK(fabs(c.position[0]-before)<=75*seconds+1e-8);
        if(i==1){max_start=c.position[0]-before;max_old_start=old.position[0]-old_before;}
        if(trace)fprintf(trace,"%u,step,200,%.6f,%.6f,%.6f\n",i,c.position[0],c.velocity[0],old.position[0]);
    }
    CHECK(max_start<max_old_start);CHECK(fabs(c.velocity[0]-75)<1e-8);
    /* Sign reversal must brake through zero before opposite acceleration. */
    int saw_zero=0;
    for(unsigned i=0;i<80;i++){
        previous=c.velocity[0];tick(&c,-200,0,20000);v=c.velocity[0];
        CHECK(!(previous>0&&v<0));CHECK(fabs(v-previous)<=test_decel*0.02+1e-7);
        if(v==0)saw_zero=1;
        if(v<0)CHECK(saw_zero);
        if(previous<=0&&v<previous)CHECK(previous-v<=test_accel*0.02+1e-7);
        if(trace)fprintf(trace,"%u,reverse,-200,%.6f,%.6f,0\n",i,c.position[0],v);
    }
    CHECK(saw_zero&&c.velocity[0]==-75);
    /* Entering the inner band requests a bounded stop. No restart in the hysteresis band. */
    for(unsigned i=0;i<40;i++){
        previous=c.velocity[0];tick(&c,15,0,20000);
        CHECK(c.motion_active[0]==0);CHECK(fabs(c.velocity[0]-previous)<=test_decel*0.02+1e-7);
    }
    CHECK(c.velocity[0]==0);p=c.position[0];
    for(unsigned i=0;i<200;i++){tick(&c,16+(i%7),0,20000);CHECK(c.position[0]==p&&c.velocity[0]==0&&!c.motion_active[0]);}
    tick(&c,23,0,20000);CHECK(c.motion_active[0]&&c.velocity[0]>0);
    /* Frame gaps, duplicate reads, and hard holds must never integrate stale motion. */
    for(unsigned i=0;i<30;i++)tick(&c,200,0,20000);
    PtTarget t=target(200,0);stamp+=20000;pt_control_update(&c,&t,stamp);
    p=c.position[0];v=c.velocity[0];
    for(unsigned i=0;i<10;i++){stamp+=1000;CHECK(!pt_control_update(&c,&t,stamp));CHECK(c.position[0]==p&&c.velocity[0]==v);}
    t.flags=6;stamp+=1000;CHECK(!pt_control_update(&c,&t,stamp));
    CHECK(c.position[0]==p&&c.velocity[0]==0&&!c.tracking);
    t=target(200,0);stamp+=5000000;CHECK(!pt_control_update(&c,&t,stamp));CHECK(c.position[0]==p);
    tick(&c,200,0,20000);CHECK(c.velocity[0]<=test_accel*0.02+1e-6&&c.position[0]-p<=test_accel*0.0002+1e-6);
    t=target(200,0);t.age_us=250001;stamp+=20000;pt_control_update(&c,&t,stamp);
    CHECK(c.hold_reason==PT_HOLD_STALE&&c.velocity[0]==0);
    tick(&c,200,0,20000);p=c.position[0];
    t.frame_id=frame;t.flags=5;t.age_us=0;stamp+=300000;pt_control_update(&c,&t,stamp);
    CHECK(c.hold_reason==PT_HOLD_STALE&&c.position[0]==p&&c.velocity[0]==0);
    tick(&c,200,0,20000);CHECK(c.position[0]==p&&c.hold_reason==PT_HOLD_BASELINE);
    /* Manual and live smooth/legacy switching preserve position and reset motion. */
    for(unsigned i=0;i<10;i++)tick(&c,200,0,20000);
    p=c.position[0];pt_control_manual(&c);CHECK(c.velocity[0]==0&&c.position[0]==p);
    CHECK(pt_control_auto(&c));tick(&c,200,0,20000);CHECK(c.position[0]==p);
    tick(&c,200,0,20000);p=c.position[0];pt_control_smooth(&c,0);
    CHECK(c.velocity[0]==0&&c.position[0]==p);tick(&c,200,0,20000);CHECK(c.position[0]==p);
    tick(&c,200,0,20000);CHECK(c.position[0]>p);
    p=c.position[0];pt_control_smooth(&c,1);tick(&c,200,0,20000);CHECK(c.position[0]==p);
    /* Saturation cancels velocity; reversing away from the bound remains possible. */
    init(&c);c.minimum[0]=1499;c.maximum[0]=1501;
    for(unsigned i=0;i<400;i++){tick(&c,200,0,20000);CHECK(c.position[0]<=1501&&c.position[0]>=1499);}
    CHECK(c.position[0]==1501&&c.velocity[0]==0);
    for(unsigned i=0;i<100;i++)tick(&c,-200,0,20000);
    CHECK(c.position[0]==1499&&c.velocity[0]==0);
    /* Small fractional moves and direction reversal, plus frame ID wrap. */
    init(&c);c.gain[0]=0.01;c.direction[0]=-1;
    for(unsigned i=0;i<1000;i++)tick(&c,23,0,20000);
    CHECK(c.position[0]<1496&&pt_control_pulse(&c,0)<1497);
    init(&c);frame=0xfffffffeu;tick(&c,200,0,20000);tick(&c,200,0,20000);CHECK(frame==0&&c.velocity[0]>0);
    c.enabled=0;p=c.position[0];tick(&c,200,0,20000);CHECK(c.position[0]==p&&c.velocity[0]==0);
    init(&c);c.dimensions_ok=0;p=c.position[0];tick(&c,200,0,20000);CHECK(c.position[0]==p&&c.hold_reason==PT_HOLD_DIMENSIONS);
    /* Synthetic +/- threshold noise: compare emitted pulse chatter, not physical jitter. */
    init(&c);init(&old);pt_control_smooth(&old,0);
    for(unsigned i=0;i<600;i++){
        int e=(i/10)%2?-(16+(i%6)):(16+(i%6));
        unsigned a=pt_control_pulse(&c,0),b=pt_control_pulse(&old,0);
        PtTarget noisy=target(e,0);stamp+=20000;
        pt_control_update(&c,&noisy,stamp);pt_control_update(&old,&noisy,stamp);
        new_edges+=a!=pt_control_pulse(&c,0);old_edges+=b!=pt_control_pulse(&old,0);
        CHECK(c.position[0]==1500&&c.velocity[0]==0);
        if(trace)fprintf(trace,"%u,noise,%d,%.6f,%.6f,%.6f\n",i,e,c.position[0],c.velocity[0],old.position[0]);
    }
    CHECK(new_edges==0&&old_edges>30);
    if(trace)fclose(trace);
    printf("PASS SMOOTH_CONTROL A=%.0f D=%.0f checks=%u startup_delta=%.4f legacy_delta=%.4f noise_pulse_changes=%u legacy=%u; accel/decel/reverse/hysteresis/duplicate/error/stale/recovery/limits/manual/wrap\n",
        test_accel,test_decel,checks,max_start,max_old_start,new_edges,old_edges);return 0;
}
