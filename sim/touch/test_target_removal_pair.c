/* Private frame pair stays in build/. Replay one learned object, then removal. */
#include "../../vitis/ov5640_lcd/src/touch/appearance_tracker.h"
#include <stdio.h>
#include <stdlib.h>
#include <math.h>
static uint32_t raw[800*480],present[CAP_CELLS],absent[CAP_CELLS];
static AppearanceTracker t;static AppearanceWork w;static unsigned checks;
#define CHECK(v) do{checks++;if(!(v)){printf("FAIL REMOVAL_PAIR line=%d frame=%u valid=%u reason=%u score=%d bbox=%u,%u,%u,%u\n",__LINE__,t.frame_id,t.valid,t.reason,w.search_best_score,t.box.xmin,t.box.xmax,t.box.ymin,t.box.ymax);return 1;}}while(0)
static int load(const char *name,uint32_t *out){
 FILE *f=fopen(name,"rb");if(!f)return 0;unsigned n=(unsigned)fread(raw,4,800*480,f);fclose(f);
 if(n!=800*480||(raw[n-1]>>24))return 0;
 for(unsigned y=0;y<120;y++)for(unsigned x=0;x<200;x++){
  unsigned r=0,g=0,b=0;
  for(unsigned dy=0;dy<4;dy++)for(unsigned dx=0;dx<4;dx++){uint32_t p=raw[(y*4+dy)*800+x*4+dx];r+=(p>>16)&255;g+=(p>>8)&255;b+=p&255;}
  out[y*200+x]=((r/16)<<16)|((g/16)<<8)|(b/16);
 }
 return 1;
}
int main(int argc,char **argv){
 if(argc!=5){fprintf(stderr,"Expected present.bin absent.bin click_x click_y\n");return 2;}
 CHECK(load(argv[1],present));CHECK(load(argv[2],absent));unsigned x=atoi(argv[3]),y=atoi(argv[4]);
 CHECK(x<800&&y<480);appearance_init(&t);
 for(unsigned i=0;i<20;i++){
  appearance_begin(&w,&t,i<10?present:absent,i+1,i==0,x,y);
  unsigned count=0;while(!appearance_work(&w,1000))CHECK(++count<2000);
  if(i<10){CHECK(t.valid);CHECK(fabs(t.box.cx-x)<24&&fabs(t.box.cy-y)<24);}
  else CHECK(!t.valid&&t.state==AP_LOST);
 }
 printf("PASS REMOVAL_PAIR checks=%u initialization/10-present/10-removed/not-live-validation\n",checks);return 0;
}
