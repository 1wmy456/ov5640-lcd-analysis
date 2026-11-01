/* Include the runtime so the emulated DMA can fill its private buffer; production API stays private. */
#include "../../vitis/ov5640_lcd/src/touch/appearance_runtime.c"
#include <stdlib.h>
static uint32_t dma[64],regs[1024];static uint64_t clock_us;static unsigned arms,aborts,flushes,invalidates,commits,checks,servo_writes;static TouchHandler callback;
#define CHECK(v) do{checks++;if(!(v)){printf("FAIL runtime line=%d phase=%u errors=%u pending=%u\n",__LINE__,phase,errors,pending);exit(1);}}while(0)
void XTime_GetTime(XTime *t){*t=clock_us;}
void Xil_Out32(UINTPTR a,uint32_t v){unsigned n=(a-XPAR_RAW_CAPTURE_DMA_BASEADDR)/4;if(n==DMA_CR/4&&v==4)dma[n]=0;else if(n==DMA_SR/4)dma[n]&=~v;else dma[n]=v;}
uint32_t Xil_In32(UINTPTR a){return dma[(a-XPAR_RAW_CAPTURE_DMA_BASEADDR)/4];}
void Xil_DCacheFlushRange(UINTPTR a,unsigned n){CHECK(a==(UINTPTR)raw&&n==FRAME_BYTES);flushes++;}
void Xil_DCacheInvalidateRange(UINTPTR a,unsigned n){CHECK(a==(UINTPTR)raw&&n==FRAME_BYTES);invalidates++;}
u32 pt_reg_read(UINTPTR b,unsigned o){(void)b;return regs[o/4];}
void pt_reg_write(UINTPTR b,unsigned o,u32 v){(void)b;regs[o/4]=v;if(o==0x114)commits++;if(o<0x80)servo_writes++;}
void touch_set_handler(TouchHandler h){callback=h;}
void touch_capture_control(unsigned f){if(f==1)arms++;if(f==2)aborts++;}
void touch_display_state(unsigned s){(void)s;}
static void service(uint64_t now){clock_us=now;appearance_runtime_service(0,now);}
static void complete(unsigned id,int object){
 for(unsigned y=0;y<480;y++)for(unsigned x=0;x<800;x++){
  int dx=(int)x-400,dy=(int)y-240;raw[y*800+x]=object&&dx*dx*28*28+dy*dy*40*40<=40*40*28*28?0x2040d0:0x305020;
 }
 for(unsigned i=0;i<4;i++)raw[i]=(raw[i]&0xffffffu)|(((id>>(i*8))&255)<<24);
 dma[DMA_SR/4]=0x1002;
 regs[0x128/4]=id;regs[0x12c/4]=1;
}
static void finish_processing(void){unsigned n=0;while(phase==2||phase==3){service(clock_us+100);CHECK(++n<1000);}}
static void request_next(void){service(clock_us+2000);CHECK(phase==1);}
int main(void){
 PtTarget out;CHECK(appearance_runtime_init(0,0));service(1);CHECK(phase==0&&callback);
 appearance_runtime_click(400,240,1000);service(80000);CHECK(!arms);service(82000);CHECK(arms==1&&phase==1&&flushes==1);
 service(83000);CHECK(!tracker.has_model&&!invalidates);complete(11,1);service(84000);CHECK(phase==2&&invalidates==1);finish_processing();
 CHECK(active&&tracker.valid&&tracker.generation==1&&accepted==1);CHECK(appearance_runtime_switched());CHECK(!appearance_runtime_switched());
 appearance_runtime_target(clock_us,&out);CHECK(out.flags==5&&out.frame_id==11);CHECK(!servo_writes);
 unsigned gen=tracker.generation;CapBox old=tracker.box;
 /* Overlay sizes are stabilized; controller still receives the raw current box. */
 for(unsigned i=0;i<20;i++){
  tracker.frame_id=100+i;tracker.box=old;
  tracker.box.xmax=old.xmin+(i%2?67:91);tracker.box.ymax=old.ymin+(i%2?63:47);
  publish_box(0,1);appearance_runtime_target(clock_us,&out);
  CHECK(out.xmin==tracker.box.xmin&&out.xmax==tracker.box.xmax);
  CHECK(out.ymin==tracker.box.ymin&&out.ymax==tracker.box.ymax);
  CHECK((regs[0x100/4]>>16)-(regs[0x100/4]&65535)==(unsigned)(old.xmax-old.xmin));
  CHECK((regs[0x104/4]>>16)-(regs[0x104/4]&65535)==(unsigned)(old.ymax-old.ymin));
 }
 tracker.box=old;tracker.frame_id=11;box_shape_init(&shape);publish_box(0,1);
 appearance_runtime_click(8,8,clock_us);service(clock_us+81000);CHECK(phase==1);complete(12,1);service(clock_us+1000);finish_processing();
 CHECK(rejections==1&&tracker.generation==gen&&!memcmp(&old,&tracker.box,sizeof(old)));
 request_next();complete(13,0);service(clock_us+1000);finish_processing();CHECK(tracker.state==AP_LOST&&!tracker.valid);
 request_next();complete(14,1);service(clock_us+1000);finish_processing();CHECK(tracker.valid&&tracker.generation==gen);
 appearance_runtime_target(published+250001,&out);CHECK(!(out.flags&1));
 request_next();dma[DMA_SR/4]=0x1002;raw[0]=0x15000000;service(clock_us+1000);CHECK(phase==4&&errors==1);service(clock_us+1);CHECK(phase==0);
 request_next();service(issued+200001);CHECK(phase==4&&errors==2&&aborts>=3);service(clock_us+1);
 request_next();complete(16,1);regs[0xf8/4]++;service(clock_us+1000);CHECK(phase==4&&errors==3);service(clock_us+1);
 request_next();callback(TOUCH_DOWN,700,240,clock_us);CHECK(appearance_runtime_paused());complete(17,1);service(clock_us+1000);CHECK(phase==0&&tracker.generation==gen);
 callback(TOUCH_CANCEL,700,240,clock_us);CHECK(!appearance_runtime_paused());appearance_runtime_blue(0);CHECK(!active);
 CHECK(!servo_writes&&commits>0&&arms==flushes);
 printf("PASS APPEARANCE_RUNTIME checks=%u ownership/IOC/cache/short-frame/error/timeout/age/background-preserve/touch-cancel/no-servo-writes\n",checks);return 0;
}
