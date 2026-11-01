#include "tracking_control.h"
#include <string.h>
#include <math.h>
static double bounded(double v,double lo,double hi){return v<lo?lo:(v>hi?hi:v);}
static double magnitude(double v){return v<0?-v:v;}
static void reset_pid_axis(PtControl *c,int a){
    c->integral[a]=c->derivative[a]=c->previous_error[a]=0;
    c->p_term[a]=c->d_term[a]=c->requested_velocity[a]=0;c->derivative_ready[a]=0;
}
static void stop_motion(PtControl *c){
    c->tracking=0;c->velocity[0]=c->velocity[1]=0;
    c->motion_active[0]=c->motion_active[1]=0;
    reset_pid_axis(c,0);reset_pid_axis(c,1);
}
void pt_control_init(PtControl *c,int dimensions_ok){
    int i;memset(c,0,sizeof(*c));c->dimensions_ok=dimensions_ok;c->deadband=15;
    c->deadband_outer=22;c->smooth_enabled=1;
    c->sample_gap_us=50000;
    for(i=0;i<2;i++){c->position[i]=1500;c->center[i]=1500;c->minimum[i]=1400;c->maximum[i]=1600;
        c->gain[i]=0.1;c->rate[i]=25;c->direction[i]=1;
        c->acceleration[i]=200;c->deceleration[i]=400;
        c->ki[i]=0;c->kd[i]=0.03;c->derivative_tau[i]=0.1;
        c->derivative_limit[i]=1000;c->integral_limit[i]=10;}
}
void pt_control_manual(PtControl *c){c->automatic=0;stop_motion(c);}
void pt_control_smooth(PtControl *c,int enabled){
    c->smooth_enabled=!!enabled;if(!enabled)c->controller=PT_CONTROL_P;stop_motion(c);
}
int pt_control_controller(PtControl *c,int mode){
    if(mode<PT_CONTROL_P||mode>PT_CONTROL_PID)return 0;
    c->controller=mode;if(mode!=PT_CONTROL_P)c->smooth_enabled=1;stop_motion(c);return 1;
}
int pt_control_sample_gap(PtControl *c,unsigned gap_us){
    if(gap_us<50000||gap_us>200000)return 0;
    c->sample_gap_us=gap_us;stop_motion(c);return 1;
}
int pt_control_pid_gains(PtControl *c,int a,double ki,double kd){
    if(a<0||a>1||!isfinite(ki)||!isfinite(kd)||ki<0||ki>0.5||kd<0||kd>1)return 0;
    c->ki[a]=ki;c->kd[a]=kd;stop_motion(c);return 1;
}
int pt_control_pid_filter(PtControl *c,int a,double tau_ms,double d_limit,double i_limit){
    if(a<0||a>1||!isfinite(tau_ms)||!isfinite(d_limit)||!isfinite(i_limit)||
       tau_ms<10||tau_ms>1000||d_limit<10||d_limit>10000||i_limit<0||i_limit>75)return 0;
    c->derivative_tau[a]=tau_ms/1000;c->derivative_limit[a]=d_limit;
    c->integral_limit[a]=i_limit;stop_motion(c);return 1;
}
/* Keep the existing acceleration/reversal rule common to P, PD and PID. */
static double slew_velocity(const PtControl *c,int a,double old_v,double goal,double dt){
    double step;
    if(old_v*goal<0)goal=0;
    step=(magnitude(goal)<magnitude(old_v)?c->deceleration[a]:c->acceleration[a])*dt;
    return old_v+bounded(goal-old_v,-step,step);
}
static double pid_goal(PtControl *c,int a,int e,double dt,double actual_dt){
    double raw,delta=0,candidate,goal,new_v,old_i=c->integral[a];
    double drive=c->direction[a]*e;
    /* Use actual sample time for D; cap dt only for motion/integration.
       Rebase after gaps instead of interpreting reacquisition as velocity. */
    double gap=(c->sample_gap_us?c->sample_gap_us:50000)/1000000.0;
    if(c->derivative_ready[a]&&actual_dt<=gap){
        double slope=bounded((e-c->previous_error[a])/actual_dt,
                            -c->derivative_limit[a],c->derivative_limit[a]);
        double alpha=actual_dt/(c->derivative_tau[a]+actual_dt);
        c->derivative[a]+=alpha*(slope-c->derivative[a]);
    }else{
        c->derivative[a]=0;
        if(actual_dt>gap)old_i=0;
    }
    c->previous_error[a]=e;c->derivative_ready[a]=1;
    c->p_term[a]=c->gain[a]*drive;
    c->d_term[a]=c->direction[a]*c->kd[a]*c->derivative[a];
    if(!c->motion_active[a]){
        reset_pid_axis(c,a);return 0; /* no latent I or D in the deadband */
    }
    if(c->controller==PT_CONTROL_PID&&c->ki[a]>0)delta=c->ki[a]*drive*dt;
    else old_i=0; /* PD, and PID with Ki=0, never retain an integral term */
    if((c->position[a]<=c->minimum[a]&&drive<0)||
       (c->position[a]>=c->maximum[a]&&drive>0))old_i=delta=0;
    candidate=bounded(old_i+delta,-c->integral_limit[a],c->integral_limit[a]);
    raw=c->p_term[a]+candidate+c->d_term[a];goal=bounded(raw,-c->rate[a],c->rate[a]);
    new_v=slew_velocity(c,a,bounded(c->velocity[a],-c->rate[a],c->rate[a]),goal,dt);
    /* Conditional integration against effective (rate AND slew limited)
       output. Permit unwinding, reject increments further into saturation. */
    if((raw-new_v)*(candidate-old_i)>1e-12){
        if(old_i*(candidate-old_i)<0)
            candidate=bounded(candidate,old_i<0?old_i:0,old_i>0?old_i:0);
        else candidate=old_i;
        raw=c->p_term[a]+candidate+c->d_term[a];
    }
    c->integral[a]=candidate;c->requested_velocity[a]=raw;
    return bounded(raw,-c->rate[a],c->rate[a]);
}
int pt_control_auto(PtControl *c){
    if(!c->dimensions_ok||!c->verified[0]||!c->verified[1]||c->enabled!=3)return 0;
    c->automatic=1;stop_motion(c);c->seen=0;return 1;
}
int pt_control_set_position(PtControl *c,int axis,int us){
    if(axis<0||axis>1||us<c->minimum[axis]||us>c->maximum[axis])return 0;
    pt_control_manual(c);c->position[axis]=us;return 1;
}
int pt_control_limits(PtControl *c,int axis,int lo,int hi){
    if(axis<0||axis>1||lo<500||hi>2500||lo>hi)return 0;
    pt_control_manual(c);c->minimum[axis]=lo;c->maximum[axis]=hi;c->verified[axis]=0;
    c->position[axis]=bounded(c->position[axis],lo,hi);
    c->center[axis]=(int)bounded(c->center[axis],lo,hi);return 1;
}
unsigned pt_control_pulse(const PtControl *c,int axis){return (unsigned)(c->position[axis]+0.5);}
int pt_control_update(PtControl *c,const PtTarget *t,uint64_t now){
    int fresh=!c->seen||t->frame_id!=c->last_frame;
    int e[2],a,changed=0;
    if(fresh){c->last_frame=t->frame_id;c->last_new_us=now;c->seen=1;}
    c->ex=(int)((uint32_t)t->xmin+t->xmax)/2-400;
    c->ey=(int)((uint32_t)t->ymin+t->ymax)/2-240;
    c->hold_reason=PT_HOLD_NONE;
    if(!c->automatic)c->hold_reason=PT_HOLD_MANUAL;
    else if(!c->dimensions_ok)c->hold_reason=PT_HOLD_DIMENSIONS;
    else if(c->enabled!=3)c->hold_reason=PT_HOLD_DISABLED;
    else if((t->flags&7)!=5||t->xmin>t->xmax||t->ymin>t->ymax||t->xmax>=800||t->ymax>=480)c->hold_reason=PT_HOLD_INVALID;
    else if(t->age_us>250000||now-c->last_new_us>250000)c->hold_reason=PT_HOLD_STALE;
    /* Safety holds have priority over the smooth deceleration trajectory. */
    if(c->hold_reason){stop_motion(c);return 0;}
    if(!fresh)return 0; /* never integrate the same frame_id twice */
    if(!c->tracking){c->tracking=1;c->last_update_us=now;c->hold_reason=PT_HOLD_BASELINE;return 0;}
    {
        uint64_t elapsed=now-c->last_update_us;
        if(now<=c->last_update_us)return 0;
        double dt=(double)(elapsed>50000?50000:elapsed)/1000000.0;
        c->last_update_us=now;e[0]=c->ex;e[1]=c->ey;
        for(a=0;a<2;a++){
            unsigned before=pt_control_pulse(c,a);
            if(!c->smooth_enabled){
              if(e[a]>c->deadband||e[a]<-c->deadband){
                double delta=c->direction[a]*c->gain[a]*e[a]*dt;
                double max_delta=c->rate[a]*dt;
                c->position[a]=bounded(c->position[a]+bounded(delta,-max_delta,max_delta),c->minimum[a],c->maximum[a]);
              }
            }else{
                double old_v,new_v,goal,next;
                int abs_e=e[a]<0?-e[a]:e[a];
                int outer=c->deadband_outer<c->deadband?c->deadband:c->deadband_outer;
                if(c->motion_active[a]){
                    if(abs_e<=c->deadband)c->motion_active[a]=0;
                }else if(abs_e>outer)c->motion_active[a]=1;
                goal=c->motion_active[a]?bounded(c->direction[a]*c->gain[a]*e[a],-c->rate[a],c->rate[a]):0;
                if(c->controller!=PT_CONTROL_P)goal=pid_goal(c,a,e[a],dt,elapsed/1000000.0);
                old_v=bounded(c->velocity[a],-c->rate[a],c->rate[a]);
                new_v=slew_velocity(c,a,old_v,goal,dt);
                next=c->position[a]+(old_v+new_v)*0.5*dt;
                if(next<c->minimum[a]||next>c->maximum[a]||
                   (c->controller!=PT_CONTROL_P&&((next<=c->minimum[a]&&new_v<0)||
                                                              (next>=c->maximum[a]&&new_v>0)))){
                    next=bounded(next,c->minimum[a],c->maximum[a]);new_v=0;c->motion_active[a]=0;
                    reset_pid_axis(c,a);
                }
                c->position[a]=next;c->velocity[a]=new_v;
            }
            if(before!=pt_control_pulse(c,a))changed=1;
        }
    }
    return changed;
}
