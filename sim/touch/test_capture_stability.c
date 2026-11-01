/* Optional private captured-frame replay. Images/model dumps remain in build/.
 * ABI: Cortex-A9 and host both use this 552-byte version of AppearanceTracker. */
#include "../../vitis/ov5640_lcd/src/touch/appearance_tracker.h"
#include <stdio.h>
#include <stdlib.h>
#include <math.h>
static uint32_t raw[800*480],rgb[CAP_CELLS];
static AppearanceTracker tracker;
static AppearanceWork work;
static unsigned checks;
#define CHECK(v) do{checks++;if(!(v)){printf("FAIL CAPTURE_STABILITY line=%d frame=%u\n",__LINE__,tracker.frame_id);return 1;}}while(0)
int main(int argc,char **argv){
 if(argc!=3&&argc!=5){fprintf(stderr,"Expected frame/model, or frame --select x y\n");return 2;}
 CHECK(sizeof(tracker)==552);
 FILE *f=fopen(argv[1],"rb");CHECK(f);CHECK(fread(raw,4,800*480,f)==800*480);fclose(f);
 CHECK(!(raw[800*480-1]>>24));
 if(argc==3){f=fopen(argv[2],"rb");CHECK(f);CHECK(fread(&tracker,1,sizeof(tracker),f)==sizeof(tracker));fclose(f);CHECK(tracker.has_model&&tracker.appearance_ready);}
 else appearance_init(&tracker);
 for(unsigned y=0;y<120;y++)for(unsigned x=0;x<200;x++){
  unsigned r=0,g=0,b=0;
  for(unsigned dy=0;dy<4;dy++)for(unsigned dx=0;dx<4;dx++){
   uint32_t p=raw[(y*4+dy)*800+x*4+dx];r+=(p>>16)&255;g+=(p>>8)&255;b+=p&255;
  }
  rgb[y*200+x]=((r/16)<<16)|((g/16)<<8)|(b/16);
 }
 CapBox settled={0};
 for(unsigned i=0;i<30;i++){
  appearance_begin(&work,&tracker,rgb,tracker.frame_id+2,argc==5&&i==0,argc==5?(unsigned)atoi(argv[3]):0,argc==5?(unsigned)atoi(argv[4]):0);
  unsigned n=0;while(!appearance_work(&work,1000))CHECK(++n<2000);
  CHECK(tracker.valid);
  if(argc==5){CHECK(tracker.box.xmax-tracker.box.xmin<200);CHECK(tracker.box.ymax-tracker.box.ymin<180);}
  if(i==5)settled=tracker.box;
  if(i>5){
   CHECK(abs((int)(tracker.box.xmax-tracker.box.xmin)-(int)(settled.xmax-settled.xmin))<=4);
   CHECK(abs((int)(tracker.box.ymax-tracker.box.ymin)-(int)(settled.ymax-settled.ymin))<=4);
   CHECK(fabs(tracker.box.cx-settled.cx)<=4&&fabs(tracker.box.cy-settled.cy)<=4);
  }
 }
 printf("PASS CAPTURE_STABILITY checks=%u 30 identical raw frames, stable raw dimensions/center, no overlay filter involved\n",checks);
 return 0;
}
