#include "appearance_runtime.h"
#include "appearance_tracker.h"
#include "touch_driver.h"
#include "xparameters.h"
#include "xil_cache.h"
#include "xil_io.h"
#include "xtime_l.h"
#include <stdio.h>
#include <string.h>
#ifdef XPAR_RAW_CAPTURE_DMA_BASEADDR
enum { DMA_CR=0x30,DMA_SR=0x34,DMA_ADDR=0x48,DMA_LENGTH=0x58,FRAME_BYTES=800*480*4 };
static uint32_t raw[800*480] __attribute__((aligned(64)));
static uint32_t small[CAP_CELLS] __attribute__((aligned(64)));
static AppearanceTracker tracker;static AppearanceWork work;
static unsigned available,active,phase,down,pending,click_x,click_y,click_token,request_token;
static unsigned selecting,switched,errors,rejections,accepted,frames,processing_us,last_status,raw_rows,cpu_us,dma_us;
static uint32_t source_error,last_frame;static uint64_t deadline,issued,published,next_capture,clicked,cpu_started;
static UINTPTR base;
static uint64_t ticks_us(void){XTime t;XTime_GetTime(&t);return t/COUNTS_PER_SECOND*1000000ull+t%COUNTS_PER_SECOND*1000000ull/COUNTS_PER_SECOND;}
static void wr(unsigned reg,uint32_t value){Xil_Out32(XPAR_RAW_CAPTURE_DMA_BASEADDR+reg,value);dmb();}
static uint32_t rd(unsigned reg){return Xil_In32(XPAR_RAW_CAPTURE_DMA_BASEADDR+reg);}
static void publish_box(UINTPTR b,int valid){
 pt_reg_write(b,0x100,((uint32_t)tracker.box.xmax<<16)|tracker.box.xmin);
 pt_reg_write(b,0x104,((uint32_t)tracker.box.ymax<<16)|tracker.box.ymin);
 pt_reg_write(b,0x108,tracker.box.area);pt_reg_write(b,0x10c,tracker.frame_id);
 pt_reg_write(b,0x110,2u|!!valid);pt_reg_write(b,0x11c,processing_us);pt_reg_write(b,0x114,1);
}
static void touch(unsigned event,unsigned x,unsigned y,uint64_t now){
 if(event==TOUCH_DOWN){click_token++;down=1;pending=0;click_x=x;click_y=y;}
 if(event==TOUCH_MOVE&&down){click_x=x;click_y=y;}
 if(event==TOUCH_UP&&down){down=0;pending=1;clicked=now;click_x=x;click_y=y;}
 if(event==TOUCH_CANCEL){down=pending=0;click_token++;}
}
int appearance_runtime_init(UINTPTR b,uint64_t now){
 appearance_init(&tracker);base=b;available=1;active=phase=down=pending=0;last_frame=0;
 touch_capture_control(2);wr(DMA_CR,4);phase=4;deadline=now;touch_set_handler(touch);
 printf("TOUCH_CAPTURE ready DMA=%08lx buffer=%08lx bytes=%u; tap to select, vision blue fallback; raw buffer ownership single-shot\r\n",(unsigned long)XPAR_RAW_CAPTURE_DMA_BASEADDR,(unsigned long)(UINTPTR)raw,FRAME_BYTES);return 1;
}
int appearance_runtime_active(void){return active;}
int appearance_runtime_paused(void){return down||pending;}
int appearance_runtime_switched(void){int result=switched;switched=0;return result;}
void appearance_runtime_blue(UINTPTR b){active=0;pending=down=0;click_token++;appearance_init(&tracker);pt_reg_write(b,0xd0,0);}
void appearance_runtime_click(unsigned x,unsigned y,uint64_t now){if(x<800&&y<480){click_token++;click_x=x;click_y=y;down=0;pending=1;clicked=now;}}
static void failed(UINTPTR b,uint64_t now){
 errors++;appearance_invalidate(&tracker,AP_BAD_FRAME);pending=0;
 if(active)publish_box(b,0);
 touch_capture_control(2);wr(DMA_CR,4);phase=4;deadline=now;
}
void appearance_runtime_service(UINTPTR b,uint64_t now){
 unsigned x,y,dx,dy;uint32_t frame;
 if(!available)return;
 touch_display_state((down||pending||!active)?AP_SELECT:(!tracker.valid||now-published>250000?AP_LOST:AP_TRACK));
 if(phase==4){
  if(!(rd(DMA_CR)&4)){touch_capture_control(0);phase=0;next_capture=now+1000;}
  else if(now-deadline>250000){available=0;touch_display_state(AP_LOST);printf("TOUCH_CAPTURE disabled: DMA reset timeout\r\n");}
  return;
 }
 if(phase==0){
  if(down||now<next_capture||(!active&&!pending)||(pending&&now-clicked<80000))return;
  selecting=pending;request_token=click_token;issued=now;source_error=pt_reg_read(b,0xf8);
  /* The last padding byte is a sentinel: a short/error packet must never look complete. */
  raw[800*480-1]=0xa5000000;Xil_DCacheFlushRange((UINTPTR)raw,FRAME_BYTES);
  wr(DMA_SR,0x7000);wr(DMA_CR,1);wr(DMA_ADDR,(uint32_t)(UINTPTR)raw);wr(DMA_LENGTH,FRAME_BYTES);
  touch_capture_control(1);phase=1;return;
 }
 if(phase==1){
  last_status=rd(DMA_SR);
  if((last_status&0x4070)||now-issued>200000){failed(b,now);return;}
  if(!(last_status&0x1000))return;
  touch_capture_control(0);Xil_DCacheInvalidateRange((UINTPTR)raw,FRAME_BYTES);dmb();
  frame=(raw[0]>>24)|((raw[1]>>24)<<8)|((raw[2]>>24)<<16)|((raw[3]>>24)<<24);
  if((raw[800*480-1]>>24)!=0||frame==last_frame||pt_reg_read(b,0x128)!=frame||!(pt_reg_read(b,0x12c)&1)||pt_reg_read(b,0xf8)!=source_error||pt_reg_read(b,0xf0)){failed(b,now);return;}
  last_frame=frame;frames++;
  if(request_token!=click_token||down){phase=0;next_capture=now+1000;return;}
  dma_us=(unsigned)(now-issued);cpu_started=ticks_us();raw_rows=0;phase=2;return;
 }
 if(phase==2){
  if(request_token!=click_token||down){phase=0;next_capture=now+1000;return;}
  /* Bounded downsampling of the immutable original frame; UART/control keep running. */
  unsigned end=raw_rows+8;if(end>CAP_MASK_HEIGHT)end=CAP_MASK_HEIGHT;
  for(y=raw_rows;y<end;y++)for(x=0;x<CAP_MASK_WIDTH;x++){
   unsigned r=0,g=0,bb=0;
   for(dy=0;dy<4;dy++)for(dx=0;dx<4;dx++){uint32_t p=raw[(y*4+dy)*800+x*4+dx];r+=(p>>16)&255;g+=(p>>8)&255;bb+=p&255;}
   small[y*CAP_MASK_WIDTH+x]=((r/16)<<16)|((g/16)<<8)|(bb/16);
  }
  raw_rows=end;
  if(raw_rows==CAP_MASK_HEIGHT){appearance_begin(&work,&tracker,small,last_frame,selecting,click_x,click_y);phase=3;}
  return;
 }
 if(phase==3){
  if(request_token!=click_token||down){phase=0;next_capture=now+1000;return;}
  if(!appearance_work(&work,1000))return;
  processing_us=(unsigned)(ticks_us()-issued);cpu_us=(unsigned)(ticks_us()-cpu_started);
  if(selecting){
   pending=0;
   if(work.selection_accepted){active=1;switched=1;accepted++;pt_reg_write(b,0xd0,0);}
   else rejections++;
   printf("SELECT %s x=%u y=%u frame=%lu latency_us=%u generation=%u bbox=%u,%u,%u,%u reason=%u\r\n",work.selection_accepted?"accepted":"rejected",click_x,click_y,(unsigned long)work.frame_id,processing_us,tracker.generation,tracker.box.xmin,tracker.box.xmax,tracker.box.ymin,tracker.box.ymax,tracker.reason);
  }
  if(active){
   if(processing_us>200000||pt_reg_read(b,0xf8)!=source_error||pt_reg_read(b,0xf0))appearance_invalidate(&tracker,AP_BAD_FRAME);
   if(!selecting||work.selection_accepted)published=issued;
   publish_box(b,tracker.valid&&now-published<=250000);
  }
  phase=0;next_capture=now+1000;
 }
}
void appearance_runtime_target(uint64_t now,PtTarget *out){
 memset(out,0,sizeof(*out));out->frame_id=tracker.frame_id;out->xmin=tracker.box.xmin;out->xmax=tracker.box.xmax;out->ymin=tracker.box.ymin;out->ymax=tracker.box.ymax;out->count=tracker.box.area;
 out->age_us=now-published>UINT32_MAX?UINT32_MAX:(uint32_t)(now-published);
 out->flags=4|(tracker.valid&&!down&&!pending&&out->age_us<=250000?1:0);
 if(!available||pt_reg_read(base,0xf0)||pt_reg_read(base,0xf8)!=source_error)out->flags=6;
}
void appearance_runtime_status(void){
 uint64_t now=ticks_us();unsigned valid=available&&tracker.valid&&!down&&!pending&&now-published<=250000;
 printf("APPEARANCE available=%u active=%u state=%s valid=%u reason=%u frame=%lu generation=%u similarity=%u/4096 phase=%u raw_frames=%u errors=%u accept=%u reject=%u process_us=%u cpu_us=%u dma_us=%u dma=%08x model=%d,%d,%d radius=%u ref_area=%lu\r\n",available,active,!active||down||pending?"SELECT":valid?"TRACK":"LOST",valid,tracker.reason,(unsigned long)tracker.frame_id,tracker.generation,tracker.similarity,phase,frames,errors,accepted,rejections,processing_us,cpu_us,dma_us,last_status,tracker.color.y,tracker.color.cb,tracker.color.cr,tracker.chroma_radius,(unsigned long)tracker.reference_box.area);
}
#else
int appearance_runtime_init(UINTPTR b,uint64_t n){(void)b;(void)n;return 0;}
void appearance_runtime_service(UINTPTR b,uint64_t n){(void)b;(void)n;}
int appearance_runtime_active(void){return 0;}
int appearance_runtime_paused(void){return 0;}
int appearance_runtime_switched(void){return 0;}
void appearance_runtime_target(uint64_t n,PtTarget *o){(void)n;memset(o,0,sizeof(*o));}
void appearance_runtime_blue(UINTPTR b){(void)b;}
void appearance_runtime_click(unsigned x,unsigned y,uint64_t n){(void)x;(void)y;(void)n;}
void appearance_runtime_status(void){printf("APPEARANCE unavailable: raw capture DMA absent from BSP\r\n");}
#endif
