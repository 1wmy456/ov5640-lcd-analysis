#ifndef POSITION_TRAJECTORY_H
#define POSITION_TRAJECTORY_H
#include <stdint.h>
typedef struct {
 double start[2],goal[2],output[2];
 double velocity[2],rate[2],acceleration[2],deceleration[2];
 int minimum[2],maximum[2];
 uint64_t started,last_sample,duration;
 uint64_t last_tick;
 uint32_t frame;
 unsigned seen;
} PtTrajectory;
void pt_trajectory_reset(PtTrajectory *p,double yaw,double pitch,uint64_t now);
void pt_trajectory_limits(PtTrajectory *p,const double rate[2],const double acceleration[2],const double deceleration[2],const int minimum[2],const int maximum[2]);
/* A new frame defines one finite endpoint, never an unbounded held velocity. */
void pt_trajectory_plan(PtTrajectory *p,const double goal[2],uint32_t frame,uint64_t now);
void pt_trajectory_tick(PtTrajectory *p,uint64_t now);
#endif
