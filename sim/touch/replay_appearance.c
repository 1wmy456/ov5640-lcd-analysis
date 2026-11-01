/* Local captured-frame regression. Raw photos stay in ignored build/, not the repository. */
#include "../../vitis/ov5640_lcd/src/touch/appearance_tracker.h"
#include <stdio.h>
#include <stdlib.h>
static uint32_t raw[800*480],rgb[CAP_CELLS];static AppearanceTracker t;static AppearanceWork w;
static void run(unsigned select){unsigned n=0;appearance_begin(&w,&t,rgb,1,select,400,260);while(!appearance_work(&w,1000))if(++n>2000)exit(3);
 printf("REPLAY select=%u accepted=%u valid=%u reason=%u best=%u components=%u candidates=%u max=%u/%ux%u bbox=%u,%u,%u,%u model=%d,%d,%d radius=%u similarity=%u\n",select,w.selection_accepted,t.valid,t.reason,w.detector.have_best,w.detector.result.components,w.detector.result.candidates,w.detector.result.max_area,w.detector.result.max_width,w.detector.result.max_height,t.box.xmin,t.box.xmax,t.box.ymin,t.box.ymax,t.color.y,t.color.cb,t.color.cr,t.chroma_radius,t.similarity);
}
int main(int argc,char **argv){
 FILE *f;if(argc<2)return 2;f=fopen(argv[1],"rb");if(!f||fread(raw,4,800*480,f)!=800*480)return 2;fclose(f);
 for(unsigned y=0;y<120;y++)for(unsigned x=0;x<200;x++){unsigned r=0,g=0,b=0;for(unsigned dy=0;dy<4;dy++)for(unsigned dx=0;dx<4;dx++){unsigned p=raw[(y*4+dy)*800+x*4+dx];r+=(p>>16)&255;g+=(p>>8)&255;b+=p&255;}rgb[y*200+x]=((r/16)<<16)|((g/16)<<8)|(b/16);}
 if(argc>2){f=fopen(argv[2],"rb");if(!f||fread(&t,1,360,f)!=360)return 2;fclose(f);run(0);}
 appearance_init(&t);run(1);
 if(!t.valid||t.box.xmax-t.box.xmin<120||t.box.ymax-t.box.ymin<90)return 4;
 for(unsigned i=0;i<10;i++){run(0);if(!t.valid)return 5;}
 printf("PASS REAL_FRAME_REPLAY complete bottle bounds, 10 repeated offline observations; not live-board acceptance\n");return 0;
}
