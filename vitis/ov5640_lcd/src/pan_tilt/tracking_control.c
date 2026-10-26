#include "tracking_control.h"
#include <string.h>
static double bounded(double v,double lo,double hi){return v<lo?lo:(v>hi?hi:v);}
static double magnitude(double v){return v<0?-v:v;}
static void stop_motion(PtControl *c){
    c->tracking=0;c->velocity[0]=c->velocity[1]=0;
    c->motion_active[0]=c->motion_active[1]=0;
}
void pt_control_init(PtControl *c,int dimensions_ok){
    int i;memset(c,0,sizeof(*c));c->dimensions_ok=dimensions_ok;c->deadband=15;
    c->deadband_outer=22;c->smooth_enabled=1;
    for(i=0;i<2;i++){c->position[i]=1500;c->center[i]=1500;c->minimum[i]=1400;c->maximum[i]=1600;
        c->gain[i]=0.1;c->rate[i]=25;c->direction[i]=1;
        c->acceleration[i]=200;c->deceleration[i]=400;}
}
void pt_control_manual(PtControl *c){c->automatic=0;stop_motion(c);}
void pt_control_smooth(PtControl *c,int enabled){c->smooth_enabled=!!enabled;stop_motion(c);}
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
                double old_v,new_v,goal,step,next;
                int abs_e=e[a]<0?-e[a]:e[a];
                int outer=c->deadband_outer<c->deadband?c->deadband:c->deadband_outer;
                if(c->motion_active[a]){
                    if(abs_e<=c->deadband)c->motion_active[a]=0;
                }else if(abs_e>outer)c->motion_active[a]=1;
                goal=c->motion_active[a]?bounded(c->direction[a]*c->gain[a]*e[a],-c->rate[a],c->rate[a]):0;
                old_v=bounded(c->velocity[a],-c->rate[a],c->rate[a]);
                /* Brake to zero before accelerating in the reverse direction. */
                if(old_v*goal<0)goal=0;
                step=((old_v*goal<0||magnitude(goal)<magnitude(old_v))?
                    c->deceleration[a]:c->acceleration[a])*dt;
                new_v=old_v+bounded(goal-old_v,-step,step);
                next=c->position[a]+(old_v+new_v)*0.5*dt;
                if(next<c->minimum[a]||next>c->maximum[a]){
                    next=bounded(next,c->minimum[a],c->maximum[a]);new_v=0;c->motion_active[a]=0;
                }
                c->position[a]=next;c->velocity[a]=new_v;
            }
            if(before!=pt_control_pulse(c,a))changed=1;
        }
    }
    return changed;
}
