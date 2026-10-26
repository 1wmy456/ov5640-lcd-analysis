#include "../../vitis/ov5640_lcd/src/pan_tilt/tracking_control.h"
#include <assert.h>
#include <stdio.h>
#include <math.h>
static PtTarget target(unsigned f,int xc,int yc){PtTarget t={0};t.frame_id=f;t.flags=5;t.xmin=xc-2;t.xmax=xc+2;t.ymin=yc-2;t.ymax=yc+2;return t;}
int main(void){
 PtControl c;PtTarget t;double p;unsigned f;
 pt_control_init(&c,1);pt_control_smooth(&c,0);assert(!c.automatic&&!c.enabled&&c.position[0]==1500);
 assert(!pt_control_auto(&c));c.enabled=3;c.verified[0]=c.verified[1]=1;assert(pt_control_auto(&c));
 t=target(1,600,100);assert(!pt_control_update(&c,&t,0));
 t.frame_id++;pt_control_update(&c,&t,20000);assert(c.position[0]>1500&&c.position[1]<1500);
 p=c.position[0];pt_control_update(&c,&t,40000);assert(c.position[0]==p); // repeated frame
 t=target(3,415,225);p=c.position[0];pt_control_update(&c,&t,60000);assert(c.position[0]==p); // +/-15 inclusive
 c.direction[0]=-1;t=target(4,600,240);pt_control_update(&c,&t,80000);assert(c.position[0]<p);
 c.direction[0]=1;c.gain[0]=2;c.rate[0]=25;t=target(5,790,240);p=c.position[0];pt_control_update(&c,&t,100000);assert(fabs(c.position[0]-p-0.5)<1e-9);
 p=c.position[0];t.flags=4;t.frame_id++;pt_control_update(&c,&t,120000);assert(c.position[0]==p&&!c.tracking);
 t.flags=5;t.frame_id++;pt_control_update(&c,&t,10000000);assert(c.position[0]==p); // regained baseline, no lost-time jump
 t.frame_id++;pt_control_update(&c,&t,10020000);assert(c.position[0]-p<=0.500001);
 p=c.position[0];t.age_us=250001;t.frame_id++;pt_control_update(&c,&t,10040000);assert(c.position[0]==p&&c.hold_reason==PT_HOLD_STALE);
 t.age_us=0;t.flags=6;pt_control_update(&c,&t,10060000);assert(c.position[0]==p&&c.hold_reason==PT_HOLD_INVALID);
 t.flags=5;t.frame_id++;pt_control_update(&c,&t,10080000);p=c.position[0];
 pt_control_update(&c,&t,10500000);assert(c.position[0]==p&&c.hold_reason==PT_HOLD_STALE); // frozen ID with fake zero hardware age
 t.frame_id++;pt_control_update(&c,&t,10520000);assert(c.position[0]==p);
 for(f=20;f<1000;f++){t.frame_id=f;pt_control_update(&c,&t,10540000+(f-20)*20000ull);}
 assert(c.position[0]<=1600);assert(!pt_control_set_position(&c,0,1605));assert(pt_control_set_position(&c,0,1505));
 assert(!c.automatic);assert(pt_control_auto(&c));assert(c.position[0]==1505); // manual->auto no recenter
 c.enabled=0;t.frame_id++;p=c.position[0];pt_control_update(&c,&t,40000000);assert(c.position[0]==p);
 assert(pt_control_limits(&c,0,1490,1510));assert(!c.verified[0]);
 assert(!pt_control_limits(&c,0,499,1600));assert(!pt_control_limits(&c,0,1600,1400));
 pt_control_init(&c,0);c.enabled=3;c.verified[0]=c.verified[1]=1;assert(!pt_control_auto(&c));
 // Small fractional steps must accumulate instead of truncating every update.
 pt_control_init(&c,1);pt_control_smooth(&c,0);c.enabled=3;c.verified[0]=c.verified[1]=1;c.gain[0]=0.01;assert(pt_control_auto(&c));
 for(f=1;f<=200;f++){t=target(f,420,240);pt_control_update(&c,&t,f*20000ull);}
 assert(c.position[0]>1500.5&&pt_control_pulse(&c,0)>1500);
 c.gain[0]=2;
 for(f=201;f<2000;f++){t=target(f,5,475);pt_control_update(&c,&t,f*20000ull);}
 assert(c.position[0]==1400&&c.position[1]<=1600); // negative error cannot underflow
 pt_control_init(&c,1);pt_control_smooth(&c,0);c.enabled=3;c.verified[0]=c.verified[1]=1;assert(pt_control_auto(&c));
 t=target(0xffffffffu,500,240);pt_control_update(&c,&t,0);t.frame_id=0;pt_control_update(&c,&t,20000);
 assert(c.position[0]>1500); // frame ID wrap is a new frame
 puts("PASS PAN_CONTROL sign/deadband/direction/rate/limits/fraction/repeat/stale/loss/recovery/manual-auto");return 0;
}
