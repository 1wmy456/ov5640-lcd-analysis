#include "pan_tilt_driver.h"
#include "xil_io.h"
u32 pt_reg_read(UINTPTR b,unsigned o){return Xil_In32(b+o);}
void pt_reg_write(UINTPTR b,unsigned o,u32 v){Xil_Out32(b+o,v);__asm__ volatile("dmb sy":::"memory");}
void pt_driver_snapshot(UINTPTR b,PtTarget *t){
    u32 x,y;pt_reg_write(b,PT_SNAPSHOT,1);
    t->frame_id=pt_reg_read(b,PT_FRAME_ID);t->flags=pt_reg_read(b,PT_FLAGS);
    x=pt_reg_read(b,PT_BBOX_X);y=pt_reg_read(b,PT_BBOX_Y);
    t->xmin=x&0xffff;t->xmax=x>>16;t->ymin=y&0xffff;t->ymax=y>>16;
    t->count=pt_reg_read(b,PT_COUNT);t->age_us=pt_reg_read(b,PT_AGE);
}
void pt_driver_commit(UINTPTR b,const PtControl *c){
    pt_reg_write(b,PT_YAW_SHADOW,pt_control_pulse(c,0));pt_reg_write(b,PT_PITCH_SHADOW,pt_control_pulse(c,1));
    pt_reg_write(b,PT_COMMIT,1);
}
void pt_driver_limits(UINTPTR b,int a,int lo,int hi){
    unsigned minreg=a?PT_PITCH_MIN:PT_YAW_MIN,maxreg=a?PT_PITCH_MAX:PT_YAW_MAX;
    if(lo>(int)pt_reg_read(b,maxreg)){pt_reg_write(b,maxreg,hi);pt_reg_write(b,minreg,lo);}
    else{pt_reg_write(b,minreg,lo);pt_reg_write(b,maxreg,hi);}
}
