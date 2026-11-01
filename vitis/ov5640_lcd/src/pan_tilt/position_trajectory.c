#include "position_trajectory.h"
#include <string.h>
#include <math.h>
static double clamp(double v,double lo,double hi){return v<lo?lo:(v>hi?hi:v);}
void pt_trajectory_reset(PtTrajectory *p,double yaw,double pitch,uint64_t now){
 memset(p,0,sizeof(*p));p->output[0]=p->start[0]=p->goal[0]=yaw;
 p->output[1]=p->start[1]=p->goal[1]=pitch;p->started=p->last_tick=now;
 for(unsigned a=0;a<2;a++){p->rate[a]=75;p->acceleration[a]=400;p->deceleration[a]=600;}
}
void pt_trajectory_limits(PtTrajectory *p,const double rate[2],const double acceleration[2],const double deceleration[2]){
 for(unsigned a=0;a<2;a++){p->rate[a]=rate[a];p->acceleration[a]=acceleration[a];p->deceleration[a]=deceleration[a];}
}
void pt_trajectory_tick(PtTrajectory *p,uint64_t now){
 if(now<=p->last_tick)return;
 uint64_t elapsed=now-p->last_tick;p->last_tick=now;
 if(!p->duration)return;
 double dt=(elapsed>50000?50000:elapsed)/1000000.0;
 uint64_t age=now-p->started;
 double remaining=(age<p->duration?p->duration-age:20000)/1000000.0;
 if(remaining<0.02)remaining=0.02;
 for(unsigned a=0;a<2;a++){
  double distance=p->goal[a]-p->output[a],old=p->velocity[a];
  double braking=sqrt(2*p->deceleration[a]*fabs(distance));
  double speed=fmin(p->rate[a],braking),goal=clamp(distance/remaining,-speed,speed);
  if(old*goal<0)goal=0;
  double step=(fabs(goal)<fabs(old)?p->deceleration[a]:p->acceleration[a])*dt;
  double velocity=clamp(old+clamp(goal-old,-step,step),-p->rate[a],p->rate[a]);
  double delta=(old+velocity)*0.5*dt;
  if((distance>=0&&delta>=distance)||(distance<=0&&delta<=distance)){p->output[a]=p->goal[a];p->velocity[a]=0;}
  else{p->output[a]+=delta;p->velocity[a]=velocity;}
 }
}
void pt_trajectory_plan(PtTrajectory *p,const double goal[2],uint32_t frame,uint64_t now){
 if(p->seen&&p->frame==frame)return;
 pt_trajectory_tick(p,now);
 uint64_t interval=p->seen&&now>p->last_sample?now-p->last_sample:20000;
 if(interval<20000)interval=20000;
 if(interval>100000)interval=100000;
 for(unsigned a=0;a<2;a++){p->start[a]=p->output[a];p->goal[a]=goal[a];}
 p->started=p->last_sample=now;p->duration=interval;p->frame=frame;p->seen=1;
}
