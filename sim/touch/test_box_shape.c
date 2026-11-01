#include "../../vitis/ov5640_lcd/src/touch/box_shape_filter.h"
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
static unsigned checks;
#define CHECK(v) do{checks++;if(!(v)){printf("FAIL BOX_SHAPE line %d\n",__LINE__);exit(1);}}while(0)
static CapBox box(int cx,int cy,unsigned w,unsigned h){CapBox b={0};b.xmin=cx-w/2;b.xmax=b.xmin+w-1;b.ymin=cy-h/2;b.ymax=b.ymin+h-1;b.area=w*h;b.cx=cx;b.cy=cy;return b;}
int main(void){
 BoxShapeFilter s;CapBox raw,out,copy;box_shape_init(&s);raw=box(200,200,100,80);
 CHECK(box_shape_update(&s,&raw,1,1,1,800,480,&out));
 for(unsigned i=2;i<122;i++){
  raw=box(150+i*3,220,i%2?85:115,i%2?92:68);copy=raw;
  CHECK(box_shape_update(&s,&raw,i,1,1,800,480,&out));CHECK(!memcmp(&raw,&copy,sizeof(raw)));
  CHECK(out.xmax-out.xmin+1==100);CHECK(out.ymax-out.ymin+1==80);
  CHECK(abs((int)(out.xmin+out.xmax)-(int)(raw.xmin+raw.xmax))<=1);
  CHECK(abs((int)(out.ymin+out.ymax)-(int)(raw.ymin+raw.ymax))<=1);
 }
 raw=box(400,240,150,120);double before=s.width;
 box_shape_update(&s,&raw,200,1,1,800,480,&out);CHECK(s.width==before);
 for(unsigned i=0;i<20;i++){box_shape_update(&s,&raw,200,1,1,800,480,&out);}
 CHECK(s.width==before); // duplicate cannot vote
 for(unsigned i=201;i<240;i++){
  double old_w=s.width,old_h=s.height;box_shape_update(&s,&raw,i,1,1,800,480,&out);
  CHECK(s.width-old_w<=old_w*0.04+1e-8);CHECK(s.height-old_h<=old_h*0.04+1e-8);
 }
 CHECK(s.width>148&&s.width<=150);CHECK(s.height>118&&s.height<=120);
 before=s.width;CHECK(!box_shape_update(&s,&raw,241,1,0,800,480,&out));CHECK(s.width==before);
 raw=box(420,220,40,32);box_shape_update(&s,&raw,242,2,1,800,480,&out);CHECK(s.width==40&&s.height==32); // reselection resets size
 raw.xmin=0;raw.xmax=15;box_shape_update(&s,&raw,243,2,1,800,480,&out);CHECK(s.width==40&&out.xmax<800);
 raw=box(799,479,1,1);box_shape_update(&s,&raw,244,2,1,800,480,&out);CHECK(out.xmax==799&&out.ymax==479);
 raw.xmax=900;CHECK(!box_shape_update(&s,&raw,245,2,1,800,480,&out));
 printf("PASS BOX_SHAPE checks=%u moving-center/size-oscillation/sustained-scale/slew/duplicate/loss/reselect/edges/raw-preserved\n",checks);return 0;
}
