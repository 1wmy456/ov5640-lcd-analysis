#include "../../vitis/ov5640_lcd/src/pan_tilt/tracking_control.h"
#include <stdio.h>
#include <stdlib.h>
static unsigned checks;
#define CHECK(v) do{checks++;if(!(v)){printf("FAIL TOUCH_PD line %d\n",__LINE__);exit(1);}}while(0)
static void init(PtControl *c){pt_control_init(c,1);c->enabled=3;c->verified[0]=c->verified[1]=1;c->gain[0]=c->gain[1]=0.7;pt_control_controller(c,PT_CONTROL_PD);pt_control_auto(c);}
int main(void){
 PtControl old,raw;PtTarget t={0};init(&old);init(&raw);CHECK(old.sample_gap_us==50000);
 CHECK(pt_control_sample_gap(&raw,150000));CHECK(!pt_control_sample_gap(&raw,250000));CHECK(raw.sample_gap_us==150000);
 t.flags=5;t.age_us=20000;t.ymin=230;t.ymax=250;t.xmin=440;t.xmax=460;
 for(unsigned i=1;i<=5;i++){
  t.frame_id=i;t.xmin+=3;t.xmax+=3;
  pt_control_update(&old,&t,i*75000);pt_control_update(&raw,&t,i*75000);
 }
 CHECK(old.d_term[0]==0);CHECK(raw.d_term[0]>0);CHECK(raw.position[0]<=raw.maximum[0]);
 double pos=raw.position[0];pt_control_update(&raw,&t,400000);CHECK(raw.position[0]==pos);
 t.flags=4;pt_control_update(&raw,&t,420000);CHECK(raw.velocity[0]==0&&raw.d_term[0]==0&&raw.position[0]==pos);
 t.flags=5;t.frame_id++;pt_control_update(&raw,&t,440000);CHECK(raw.position[0]==pos&&raw.hold_reason==PT_HOLD_BASELINE);
 CHECK(pt_control_sample_gap(&raw,50000));CHECK(raw.position[0]==pos&&raw.enabled==3&&raw.automatic);

 PtControl timed,legacy;init(&timed);init(&legacy);timed.motion_dt_cap_us=100000;
 timed.smooth_enabled=legacy.smooth_enabled=0;t.flags=5;t.xmin=490;t.xmax=510;
 t.frame_id=100;pt_control_update(&timed,&t,1000000);pt_control_update(&legacy,&t,1000000);
 t.frame_id++;pt_control_update(&timed,&t,1100000);pt_control_update(&legacy,&t,1100000);
 CHECK(timed.position[0]-1500>1.99*(legacy.position[0]-1500));
 double held=timed.position[0];pt_control_update(&timed,&t,1120000);CHECK(timed.position[0]==held);
 printf("PASS TOUCH_PD checks=%u 75ms-sampling/D-active/duplicate/loss/recovery/position-preserved/legacy-50ms\n",checks);return 0;
}
