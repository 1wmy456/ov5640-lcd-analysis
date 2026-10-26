#include "cap_runtime.h"
#include <string.h>
enum {
    MASK_LOCK=0xd0,MASK_FRAME=0xd4,MASK_FLAGS=0xd8,MASK_AGE=0xdc,
    MASK_DIMS=0xe0,MASK_BLOCK_SIZE=0xe4,MASK_WORD_COUNT=0xe8,
    MASK_LIVE_FRAME=0xec,MASK_ERROR=0xf0,MASK_LIVE_AGE=0xf4,MASK_ERRORS=0xf8,MASK_MAGIC=0xfc,
    BOX_X=0x100,BOX_Y=0x104,BOX_AREA=0x108,BOX_FRAME=0x10c,BOX_FLAGS=0x110,BOX_COMMIT=0x114,
    DETECTOR_US=0x11c,DETECTOR_STATUS=0x120,MASK_DATA=0x200
};
static CapDetector detector;
static unsigned enabled,state,word_index,have_frame;
static uint32_t source_frame,source_flags,source_age,source_errors,last_frame,processing_us;
static uint64_t snapshot_time;
static PtTarget published;
static uint64_t published_time;
static uint32_t published_errors;
static CapResult summary;
static void write_box(UINTPTR b,const PtTarget *t){
    pt_reg_write(b,BOX_X,((u32)t->xmax<<16)|t->xmin);
    pt_reg_write(b,BOX_Y,((u32)t->ymax<<16)|t->ymin);
    pt_reg_write(b,BOX_AREA,t->count);pt_reg_write(b,BOX_FRAME,t->frame_id);
    pt_reg_write(b,BOX_FLAGS,t->flags&1);pt_reg_write(b,DETECTOR_US,processing_us);
    pt_reg_write(b,DETECTOR_STATUS,(detector.result.reason<<16)|(detector.result.locked<<8)|
        (detector.result.candidates>255?255:detector.result.candidates));
    /* pt_reg_write includes the device-memory barrier on the target. */
    pt_reg_write(b,BOX_COMMIT,1);
}
int cap_runtime_init(UINTPTR b){
    cap_detector_init(&detector);state=word_index=have_frame=0;processing_us=0;
    memset(&summary,0,sizeof(summary));summary.reason=CAP_NO_CANDIDATE;
    memset(&published,0,sizeof(published));published_time=0;published_errors=0;
    enabled=pt_reg_read(b,4)>=0x00010100;
    if(enabled)enabled=pt_reg_read(b,MASK_MAGIC)==0x43434c31&&
        pt_reg_read(b,MASK_DIMS)==((CAP_MASK_HEIGHT<<16)|CAP_MASK_WIDTH)&&
        pt_reg_read(b,MASK_BLOCK_SIZE)==CAP_MASK_BLOCK&&pt_reg_read(b,MASK_WORD_COUNT)==CAP_WORDS;
    return enabled;
}
void cap_runtime_service(UINTPTR b,uint64_t now){
    unsigned n;
    if(!enabled)return;
    if(state==0){
        uint32_t frame=pt_reg_read(b,MASK_LIVE_FRAME);
        if(!frame||(have_frame&&frame==last_frame))return;
        pt_reg_write(b,MASK_LOCK,1);snapshot_time=now;state=1;
    }else if(state==1){
        if(!(pt_reg_read(b,MASK_LOCK)&1))return;
        source_frame=pt_reg_read(b,MASK_FRAME);source_flags=pt_reg_read(b,MASK_FLAGS);
        source_age=pt_reg_read(b,MASK_AGE);source_errors=pt_reg_read(b,0x124);
        last_frame=source_frame;have_frame=1;word_index=0;
        if(source_flags!=5||source_age>250000){
            pt_reg_write(b,MASK_LOCK,0);cap_detector_invalidate(&detector,source_flags&2?CAP_FRAME_ERROR:CAP_STALE);
            summary=detector.result;
            published.frame_id=source_frame;published.flags=source_flags&2?6:4;published.count=0;
            published_time=now;published.age_us=source_age;published_errors=source_errors;
            processing_us=(uint32_t)(now-snapshot_time);write_box(b,&published);state=0;
        }else state=2;
    }else if(state==2){
        for(n=0;n<64&&word_index<CAP_WORDS;n++,word_index++)
            detector.raw[word_index]=pt_reg_read(b,MASK_DATA+4*word_index);
        if(word_index==CAP_WORDS){
            pt_reg_write(b,MASK_LOCK,0);
            cap_detector_begin(&detector,source_frame);state=3;
        }
    }else if(cap_detector_work(&detector,1000)){
        memset(&published,0,sizeof(published));published.frame_id=source_frame;
        published.flags=detector.result.valid?5:4;
        if(detector.result.valid){
            published.xmin=detector.result.box.xmin;published.xmax=detector.result.box.xmax;
            published.ymin=detector.result.box.ymin;published.ymax=detector.result.box.ymax;
            published.count=detector.result.box.area;
        }
        processing_us=(uint32_t)(now-snapshot_time);
        published.age_us=source_age+processing_us;published_time=now;published_errors=source_errors;
        if(pt_reg_read(b,MASK_ERROR)||pt_reg_read(b,MASK_ERRORS)!=source_errors){
            cap_detector_invalidate(&detector,CAP_FRAME_ERROR);published.flags=6;
        }else if(published.age_us>250000){cap_detector_invalidate(&detector,CAP_STALE);published.flags=4;}
        summary=detector.result;
        write_box(b,&published);state=0;
    }
}
void cap_runtime_target(UINTPTR b,uint64_t now,PtTarget *out){
    uint64_t age;
    if(!enabled){memset(out,0,sizeof(*out));out->flags=6;return;}
    *out=published;age=(uint64_t)published.age_us+(now-published_time);
    out->age_us=age>UINT32_MAX?UINT32_MAX:(uint32_t)age;
    if(pt_reg_read(b,MASK_ERROR)||pt_reg_read(b,MASK_ERRORS)!=published_errors){
        out->flags=(out->flags|2)&~1u;
        if(detector.locked)cap_detector_invalidate(&detector,CAP_FRAME_ERROR);
        summary.valid=0;summary.locked=0;summary.reason=CAP_FRAME_ERROR;
    }else if(out->age_us>250000)out->flags&=~1u;
}
const CapResult *cap_runtime_result(void){return &summary;}
uint32_t cap_runtime_processing_us(void){return processing_us;}
