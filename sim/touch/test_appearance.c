#include "../../vitis/ov5640_lcd/src/touch/appearance_tracker.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
static uint32_t image[CAP_CELLS];static AppearanceTracker t;static AppearanceWork w;static unsigned checks,frame;
#define CHECK(v) do{checks++;if(!(v)){printf("FAIL line=%d reason=%u valid=%u state=%u frame=%u\n",__LINE__,t.reason,t.valid,t.state,frame);exit(1);}}while(0)
static void disk(int cx,int cy,int rx,int ry,uint32_t c){for(int y=0;y<CAP_MASK_HEIGHT;y++)for(int x=0;x<CAP_MASK_WIDTH;x++){int dx=x-cx,dy=y-cy;if(dx*dx*ry*ry+dy*dy*rx*rx<=rx*rx*ry*ry)image[y*CAP_MASK_WIDTH+x]=c;}}
static void scene(int moving,int selected){
 for(unsigned i=0;i<CAP_CELLS;i++)image[i]=0x305020;
 disk(42+(selected==0?moving:0),58,12,9,0xe04030);
 disk(100+(selected==1?moving:0),58,12,9,0x2040d0);
 disk(158+(selected==2?moving:0),58,12,9,0xe0e0e0);
}
static void process(int select,unsigned x,unsigned y){unsigned steps=0;appearance_begin(&w,&t,image,++frame,select,x,y);while(!appearance_work(&w,137))CHECK(++steps<2000);}
int main(void){
 int centers[]={42,100,158};appearance_init(&t);CHECK(t.state==AP_SELECT&&!t.has_model);
 for(int which=0;which<3;which++){
  scene(0,which);process(1,centers[which]*4,58*4);CHECK(w.selection_accepted&&t.valid&&t.generation==(unsigned)which+1);
  CHECK(abs((int)t.box.cx-centers[which]*4)<8);
  /* Identical input must converge, rather than feeding scale/grid jitter back
     into the next search and the controller. */
  unsigned stable_w=0,stable_h=0;double stable_x=0,stable_y=0;
  for(unsigned repeat=0;repeat<30;repeat++){
   process(0,0,0);CHECK(t.valid);
   if(repeat==5){stable_w=t.box.xmax-t.box.xmin;stable_h=t.box.ymax-t.box.ymin;stable_x=t.box.cx;stable_y=t.box.cy;}
   if(repeat>5){CHECK(abs((int)(t.box.xmax-t.box.xmin)-(int)stable_w)<=4);CHECK(abs((int)(t.box.ymax-t.box.ymin)-(int)stable_h)<=4);CHECK(fabs(t.box.cx-stable_x)<=4&&fabs(t.box.cy-stable_y)<=4);}
  }
  uint16_t anchor[64];memcpy(anchor,t.anchor_histogram,sizeof(anchor));
  for(int move=1;move<=8;move++){
   scene(move,which);
   unsigned scale=move%2?65:125;
   for(unsigned i=0;i<CAP_CELLS;i++){
    unsigned p=image[i],r=((p>>16)&255)*scale/100,g=((p>>8)&255)*scale/100,b=(p&255)*scale/100;
    image[i]=((r>255?255:r)<<16)|((g>255?255:g)<<8)|(b>255?255:b);
   }
   process(0,0,0);CHECK(t.valid&&t.state==AP_TRACK);CHECK(abs((int)t.box.cx-(centers[which]+move)*4)<8);
  }
  CHECK(!memcmp(anchor,t.anchor_histogram,sizeof(anchor)));
  unsigned gen=t.generation;CapBox box=t.box;ApColor learned=t.color;
  process(1,4,4);CHECK(!w.selection_accepted&&t.generation==gen);CHECK(!memcmp(&box,&t.box,sizeof(box)));
  for(unsigned i=0;i<CAP_CELLS;i++)image[i]=0x305020;
  for(int j=0;j<10;j++){process(0,0,0);CHECK(!t.valid&&t.state==AP_LOST);CHECK(!memcmp(&learned,&t.color,sizeof(learned)));}
  scene(8,which);process(0,0,0);CHECK(t.valid&&t.state==AP_TRACK);
 }
 appearance_init(&t);for(unsigned i=0;i<CAP_CELLS;i++)image[i]=0xe0e0e0;
 process(1,400,240);CHECK(!t.has_model&&!w.selection_accepted&&t.state==AP_SELECT);
 scene(0,0);process(1,800,240);CHECK(!t.has_model);
 appearance_init(&t);for(unsigned i=0;i<CAP_CELLS;i++)image[i]=0xa07c64;
 disk(100,60,12,9,0xe0e0e0);process(1,400,240);CHECK(t.has_model&&t.valid&&t.chroma_radius<=25);
 appearance_init(&t);scene(0,1);process(1,400,232);CHECK(t.valid);
 unsigned reference=t.reference_box.area;
 for(int radius=11;radius>=4;radius--){
  for(unsigned i=0;i<CAP_CELLS;i++)image[i]=0x305020;
  disk(100,58,radius,radius*3/4,0x2040d0);process(0,0,0);
  if(t.valid)CHECK(t.box.area>=reference*0.35);
  CHECK(t.reference_box.area==reference);
 }
 scene(0,1);process(0,0,0);CHECK(t.valid&&t.box.area>=reference*0.8);
 appearance_init(&t);for(unsigned i=0;i<CAP_CELLS;i++)image[i]=0x305020;
 disk(42,58,12,9,0x2040d0);disk(162,58,12,9,0x2040d0);process(1,168,232);CHECK(t.valid);
 for(int step=1;step<=7;step++){
  int cx=42+step*12;
  for(unsigned i=0;i<CAP_CELLS;i++)image[i]=0x305020;
  disk(cx,58,12,9,0x2040d0);disk(162,58,12,9,0x2040d0);
  /* A notch spoils a strict ellipse silhouette while the local appearance remains. */
  for(int y=50;y<54;y++)for(int x=cx;x<cx+7;x++)image[y*CAP_MASK_WIDTH+x]=0x305020;
  process(0,0,0);CHECK(t.valid);CHECK(abs((int)t.box.cx-cx*4)<20);
 }
 printf("PASS APPEARANCE checks=%u red/blue/white click/motion/reselect/background-preserve/loss/recovery/immutable-anchor/flat-background\n",checks);return 0;
}
