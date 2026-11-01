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
    /* Visual velocity PID: Kp=gain; Ki us/(pixel*s^2); Kd us/pixel.
       integral and all three reported terms are servo-domain us/s. */
    double ki[2],kd[2],derivative_tau[2],derivative_limit[2],integral_limit[2];
    double integral[2],derivative[2],previous_error[2];
    double p_term[2],d_term[2],requested_velocity[2];
    int controller,derivative_ready[2];
    int smooth_enabled,deadband_outer,motion_active[2];
    int minimum[2],maximum[2],center[2],direction[2],deadband;
    int automatic,dimensions_ok,enabled,verified[2],tracking,seen;
    int ex,ey,hold_reason;
    uint32_t last_frame;
    unsigned motion_dt_cap_us; /* 50ms legacy, 100ms touch; finite output trajectory */
    unsigned sample_gap_us; /* default 50ms; bounded raw-frame pipeline may use 150ms */
    uint64_t last_new_us,last_update_us;
} PtControl;
enum { PT_CONTROL_P,PT_CONTROL_PD,PT_CONTROL_PID };
enum { PT_HOLD_NONE,PT_HOLD_MANUAL,PT_HOLD_DISABLED,PT_HOLD_INVALID,PT_HOLD_STALE,PT_HOLD_DIMENSIONS,PT_HOLD_BASELINE };
void pt_control_init(PtControl *c,int dimensions_ok);
void pt_control_manual(PtControl *c);
void pt_control_smooth(PtControl *c,int enabled);
int pt_control_controller(PtControl *c,int mode);
int pt_control_sample_gap(PtControl *c,unsigned gap_us);
/* Checked setters reset motion/history without changing pulse or enables. */
int pt_control_pid_gains(PtControl *c,int axis,double ki,double kd);
int pt_control_pid_filter(PtControl *c,int axis,double tau_ms,double derivative_limit,double integral_limit);
int pt_control_auto(PtControl *c);
int pt_control_update(PtControl *c,const PtTarget *t,uint64_t now_us);
int pt_control_set_position(PtControl *c,int axis,int us);
int pt_control_limits(PtControl *c,int axis,int lo,int hi);
unsigned pt_control_pulse(const PtControl *c,int axis);
#endif
