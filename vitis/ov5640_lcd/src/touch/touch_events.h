#ifndef TOUCH_EVENTS_H
#define TOUCH_EVENTS_H
#include <stdint.h>
enum { TOUCH_NONE, TOUCH_DOWN, TOUCH_MOVE, TOUCH_UP, TOUCH_CANCEL };
typedef struct { unsigned raw_width,raw_height,width,height,swap_xy,invert_x,invert_y; } TouchMap;
typedef struct { unsigned down,pending,x,y; uint64_t since,last_good; } TouchEvents;
int touch_map(const TouchMap *m,unsigned rx,unsigned ry,unsigned *x,unsigned *y);
int touch_event(TouchEvents *s,int ready,unsigned count,unsigned x,unsigned y,uint64_t now);
#endif
