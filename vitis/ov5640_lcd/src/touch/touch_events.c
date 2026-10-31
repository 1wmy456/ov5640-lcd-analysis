#include "touch_events.h"
int touch_map(const TouchMap *m,unsigned rx,unsigned ry,unsigned *x,unsigned *y){
 unsigned rw=m->raw_width,rh=m->raw_height,t;
 if(rw<2||rh<2||m->width<2||m->height<2||rx>=rw||ry>=rh)return 0;
 if(m->swap_xy){t=rx;rx=ry;ry=t;t=rw;rw=rh;rh=t;}
 *x=(uint64_t)rx*(m->width-1)/(rw-1);*y=(uint64_t)ry*(m->height-1)/(rh-1);
 if(m->invert_x)*x=m->width-1-*x;
 if(m->invert_y)*y=m->height-1-*y;
 return 1;
}
int touch_event(TouchEvents *s,int ready,unsigned count,unsigned x,unsigned y,uint64_t now){
 if(!ready){if((s->down||s->pending)&&now-s->last_good>150000){s->down=s->pending=0;return TOUCH_CANCEL;}return TOUCH_NONE;}
 s->last_good=now;
 if(count>1){if(s->down||s->pending){s->down=s->pending=0;return TOUCH_CANCEL;}return TOUCH_NONE;}
 if(!count){s->pending=0;if(s->down){s->down=0;return TOUCH_UP;}return TOUCH_NONE;}
 if(!s->down){
  if(!s->pending){s->pending=1;s->since=now;s->x=x;s->y=y;return TOUCH_NONE;}
  if((x>s->x?x-s->x:s->x-x)>20||(y>s->y?y-s->y:s->y-y)>20){s->since=now;s->x=x;s->y=y;return TOUCH_NONE;}
  if(now-s->since<20000)return TOUCH_NONE;
  s->pending=0;s->down=1;s->x=x;s->y=y;return TOUCH_DOWN;
 }
 if(x!=s->x||y!=s->y){s->x=x;s->y=y;return TOUCH_MOVE;}
 return TOUCH_NONE;
}
