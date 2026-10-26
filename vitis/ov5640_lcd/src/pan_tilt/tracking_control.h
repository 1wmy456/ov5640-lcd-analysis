#ifndef TRACKING_CONTROL_H
#define TRACKING_CONTROL_H
#include <stdint.h>
typedef struct {
    uint32_t frame_id,flags,age_us,count;
    uint16_t xmin,xmax,ymin,ymax;
} PtTarget;
typedef struct {
    double position[2],gain[2],rate[2]; /* gain us/(pixel*s); rate us/s */
    double velocity[2],acceleration[2],deceleration[2]; /* us/s; us/s^2 */
    int smooth_enabled,deadband_outer,motion_active[2];
    int minimum[2],maximum[2],center[2],direction[2],deadband;
    int automatic,dimensions_ok,enabled,verified[2],tracking,seen;
    int ex,ey,hold_reason;
    uint32_t last_frame;
    uint64_t last_new_us,last_update_us;
} PtControl;
enum { PT_HOLD_NONE,PT_HOLD_MANUAL,PT_HOLD_DISABLED,PT_HOLD_INVALID,PT_HOLD_STALE,PT_HOLD_DIMENSIONS,PT_HOLD_BASELINE };
void pt_control_init(PtControl *c,int dimensions_ok);
void pt_control_manual(PtControl *c);
void pt_control_smooth(PtControl *c,int enabled);
int pt_control_auto(PtControl *c);
int pt_control_update(PtControl *c,const PtTarget *t,uint64_t now_us);
int pt_control_set_position(PtControl *c,int axis,int us);
int pt_control_limits(PtControl *c,int axis,int lo,int hi);
unsigned pt_control_pulse(const PtControl *c,int axis);
#endif
