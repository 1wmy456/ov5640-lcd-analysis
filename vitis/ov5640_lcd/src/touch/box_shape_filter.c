#include "box_shape_filter.h"
#include <string.h>
static double absolute(double v){return v<0?-v:v;}
static double maximum(double a,double b){return a>b?a:b;}
void box_shape_init(BoxShapeFilter *s){memset(s,0,sizeof(*s));}
static double dimension(BoxShapeFilter *s,unsigned axis,double stable,double measured){
 double error=measured-stable,band=maximum(4,stable*0.08);
 int direction=error>0?1:(error<0?-1:0);
 if(absolute(error)<=1.0){s->votes[axis]=s->changing[axis]=0;s->direction[axis]=0;return stable;}
 if(!s->changing[axis]&&absolute(error)<=band){s->votes[axis]=0;s->direction[axis]=0;return stable;}
 if(direction!=s->direction[axis]||absolute(measured-s->proposal[axis])>maximum(6,s->proposal[axis]*0.12)){
  s->direction[axis]=direction;s->votes[axis]=1;s->changing[axis]=0;s->proposal[axis]=measured;return stable;
 }
 s->proposal[axis]=(s->proposal[axis]+measured)*0.5;
 if(s->votes[axis]<3)s->votes[axis]++;
 if(s->votes[axis]<3)return stable;
 s->changing[axis]=1;
 double step=maximum(1,stable*0.04),delta=error*0.35;
 if(delta>step)delta=step;
 if(delta< -step)delta=-step;
 return stable+delta;
}
int box_shape_update(BoxShapeFilter *s,const CapBox *raw,uint32_t frame,unsigned generation,int valid,unsigned iw,unsigned ih,CapBox *out){
 *out=*raw;
 if(!valid||!iw||!ih||raw->xmin>raw->xmax||raw->ymin>raw->ymax||raw->xmax>=iw||raw->ymax>=ih){
  s->votes[0]=s->votes[1]=s->changing[0]=s->changing[1]=0;return 0;
 }
 double width=raw->xmax-raw->xmin+1,height=raw->ymax-raw->ymin+1;
 if(!s->initialized||s->generation!=generation){
  box_shape_init(s);s->initialized=1;s->generation=generation;s->width=width;s->height=height;
 }else if(!s->seen||s->frame_id!=frame){
  /* Cropping is a display boundary condition, not evidence that the object shrank. */
  if(raw->xmin&&raw->xmax+1u<iw)s->width=dimension(s,0,s->width,width);
  else s->votes[0]=s->changing[0]=0;
  if(raw->ymin&&raw->ymax+1u<ih)s->height=dimension(s,1,s->height,height);
  else s->votes[1]=s->changing[1]=0;
 }
 s->seen=1;s->frame_id=frame;
 unsigned w=(unsigned)(s->width+0.5),h=(unsigned)(s->height+0.5);
 double cx=((double)raw->xmin+raw->xmax)*0.5,cy=((double)raw->ymin+raw->ymax)*0.5;
 int lx=(int)(cx-(w-1)*0.5+0.5),ly=(int)(cy-(h-1)*0.5+0.5),hx=lx+(int)w-1,hy=ly+(int)h-1;
 if(lx<0)lx=0;
 if(ly<0)ly=0;
 if(hx>=(int)iw)hx=(int)iw-1;
 if(hy>=(int)ih)hy=(int)ih-1;
 out->xmin=(uint16_t)lx;out->xmax=(uint16_t)hx;out->ymin=(uint16_t)ly;out->ymax=(uint16_t)hy;
 return 1;
}
