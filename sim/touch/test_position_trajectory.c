#include "../../vitis/ov5640_lcd/src/pan_tilt/position_trajectory.h"
#include "../../vitis/ov5640_lcd/src/pan_tilt/tracking_control.h"
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
static unsigned checks;
#define CHECK(v) do{checks++;if(!(v)){printf("FAIL TRAJECTORY line=%d\n",__LINE__);exit(1);}}while(0)
int main(void){
 PtTrajectory p;double goal[2]={1500,1500};pt_trajectory_reset(&p,1500,1500,0);
 pt_trajectory_plan(&p,goal,1,0);goal[0]=1504;goal[1]=1496;pt_trajectory_plan(&p,goal,2,80000);
 double last[2]={1500,1500};
 for(unsigned i=1;i<=4;i++){
  pt_trajectory_tick(&p,80000+i*20000);
  CHECK(p.output[0]>=last[0]&&p.output[0]<=1504);CHECK(p.output[1]<=last[1]&&p.output[1]>=1496);
  CHECK(p.output[0]-last[0]<=1.5);CHECK(last[1]-p.output[1]<=1.5);
  last[0]=p.output[0];last[1]=p.output[1];
 }
 /* Duplicate frame cannot change the endpoint or extend its trajectory. */
 goal[0]=2500;goal[1]=500;pt_trajectory_plan(&p,goal,2,160000);
 for(unsigned now=180000;now<=1000000;now+=20000)pt_trajectory_tick(&p,now);
 CHECK(p.output[0]==1504&&p.output[1]==1496&&p.duration==80000);
 pt_trajectory_reset(&p,1501,1499,1000000);pt_trajectory_tick(&p,2000000);CHECK(p.output[0]==1501&&p.output[1]==1499);
 /* Exercise actual PD endpoint generation at 80ms and output at 20ms. */
 PtControl c;PtTarget t={0};pt_control_init(&c,1);c.enabled=3;c.verified[0]=c.verified[1]=1;
 c.minimum[0]=c.minimum[1]=1400;c.maximum[0]=c.maximum[1]=1600;
 c.rate[0]=c.rate[1]=75;c.gain[0]=c.gain[1]=0.7;
 c.acceleration[0]=c.acceleration[1]=400;c.deceleration[0]=c.deceleration[1]=600;
 pt_control_sample_gap(&c,150000);pt_control_controller(&c,PT_CONTROL_PD);pt_control_auto(&c);
 t.flags=5;t.xmin=590;t.xmax=610;t.ymin=230;t.ymax=250;t.frame_id=1;
 pt_control_update(&c,&t,20000);pt_trajectory_reset(&p,1500,1500,20000);pt_trajectory_plan(&p,c.position,1,20000);
 double previous=1500;
 for(uint64_t now=40000;now<=600000;now+=20000){
  if((now-20000)%80000==0)t.frame_id++;
  pt_control_update(&c,&t,now);pt_trajectory_plan(&p,c.position,t.frame_id,now);pt_trajectory_tick(&p,now);
  CHECK(p.output[0]>=previous);CHECK(p.output[0]-previous<=1.5+1e-9);CHECK(p.output[0]<=c.position[0]);previous=p.output[0];
 }
 /* Invalid/stale frames cancel remaining planned displacement immediately. */
 t.flags=4;pt_control_update(&c,&t,620000);pt_trajectory_reset(&p,previous,1500,620000);
 pt_trajectory_tick(&p,1000000);CHECK(p.output[0]==previous&&c.velocity[0]==0);
 CHECK(!c.tracking);
 pt_trajectory_reset(&p,1500,1500,0);
 double rate[2]={20,30},accel[2]={100,120},decel[2]={200,240};
 int minimum[2]={1450,1450},maximum[2]={1550,1550};
 pt_trajectory_limits(&p,rate,accel,decel,minimum,maximum);
 unsigned id=0;double last_x=1500,last_y=1500;
 for(unsigned i=1;i<=300;i++){
  if(i%2==0||i%5==0){id++;goal[0]=i%40<20?1550:1450;goal[1]=3000-goal[0];pt_trajectory_plan(&p,goal,id,i*20000);}
  pt_trajectory_tick(&p,i*20000);
  CHECK(fabs(p.output[0]-last_x)<=0.4+1e-9);CHECK(fabs(p.output[1]-last_y)<=0.6+1e-9);
  CHECK(p.output[0]>=1450&&p.output[0]<=1550&&p.output[1]>=1450&&p.output[1]<=1550);
  last_x=p.output[0];last_y=p.output[1];pt_trajectory_tick(&p,i*20000);CHECK(last_x==p.output[0]&&last_y==p.output[1]);
 }
 goal[0]=2500;goal[1]=500;pt_trajectory_plan(&p,goal,++id,6200000);
 CHECK(p.goal[0]==1550&&p.goal[1]==1450);
 p.output[0]=1549.9;p.velocity[0]=20;p.output[1]=1450.1;p.velocity[1]=-30;
 goal[0]=1450;goal[1]=1550;pt_trajectory_plan(&p,goal,++id,6200000);
 pt_trajectory_tick(&p,6220000);CHECK(p.output[0]<=1550&&p.output[1]>=1450);
 /* Faster profile: both signs, reversal, endpoint and loss hold at 150us/s. */
 pt_trajectory_reset(&p,1500,1500,0);
 rate[0]=rate[1]=150;accel[0]=accel[1]=800;decel[0]=decel[1]=1200;
 minimum[0]=minimum[1]=1100;maximum[0]=maximum[1]=1800;
 pt_trajectory_limits(&p,rate,accel,decel,minimum,maximum);
 last_x=last_y=1500;id=0;
 for(unsigned i=1;i<=200;i++){
  if(i%5==0){goal[0]=i<100?1700:1300;goal[1]=3000-goal[0];pt_trajectory_plan(&p,goal,++id,i*20000);}
  pt_trajectory_tick(&p,i*20000);
  CHECK(fabs(p.output[0]-last_x)<=3.0+1e-9&&fabs(p.output[1]-last_y)<=3.0+1e-9);
  CHECK(fabs(p.velocity[0])<=150+1e-9&&fabs(p.velocity[1])<=150+1e-9);
  CHECK(p.output[0]>=1100&&p.output[0]<=1800&&p.output[1]>=1100&&p.output[1]<=1800);
  last_x=p.output[0];last_y=p.output[1];
 }
 pt_trajectory_reset(&p,last_x,last_y,4000000);
 pt_trajectory_tick(&p,4500000);CHECK(p.output[0]==last_x&&p.output[1]==last_y);
 printf("PASS TRAJECTORY checks=%u 80ms-PD/20ms-output/finite-endpoint/duplicate/no-extrapolation/loss-cancel/variable-cadence/rate/reversal/faster150\n",checks);
 return 0;
}
