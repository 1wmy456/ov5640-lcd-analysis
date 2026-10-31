#include "../../vitis/ov5640_lcd/src/touch/touch_events.h"
#include <stdio.h>
#include <stdlib.h>
static unsigned checks;
#define CHECK(x) do{checks++;if(!(x)){printf("FAIL line %d\n",__LINE__);exit(1);}}while(0)
int main(void){
 TouchMap m={800,480,800,480,0,0,0};TouchEvents s={0};unsigned x,y,i,j;
 for(i=0;i<800;i++)for(j=0;j<480;j++){CHECK(touch_map(&m,i,j,&x,&y));CHECK(x==i&&y==j);}
 CHECK(!touch_map(&m,800,0,&x,&y));CHECK(!touch_map(&m,0,480,&x,&y));
 m.invert_x=m.invert_y=1;CHECK(touch_map(&m,0,0,&x,&y)&&x==799&&y==479);
 m=(TouchMap){480,800,800,480,1,0,0};CHECK(touch_map(&m,479,799,&x,&y)&&x==799&&y==479);
 m.raw_width=0;CHECK(!touch_map(&m,0,0,&x,&y));
 CHECK(touch_event(&s,1,1,400,240,10000)==TOUCH_NONE);
 CHECK(touch_event(&s,1,1,402,239,20000)==TOUCH_NONE);
 CHECK(touch_event(&s,1,1,402,239,30000)==TOUCH_DOWN);
 CHECK(touch_event(&s,1,1,402,239,40000)==TOUCH_NONE);
 CHECK(touch_event(&s,1,1,410,240,50000)==TOUCH_MOVE);
 CHECK(touch_event(&s,1,0,0,0,60000)==TOUCH_UP);
 CHECK(touch_event(&s,1,0,0,0,70000)==TOUCH_NONE);
 CHECK(touch_event(&s,1,1,400,240,80000)==TOUCH_NONE);
 CHECK(touch_event(&s,1,1,400,240,100000)==TOUCH_DOWN);
 CHECK(touch_event(&s,1,2,400,240,110000)==TOUCH_CANCEL);
 CHECK(touch_event(&s,1,1,400,240,120000)==TOUCH_NONE);
 CHECK(touch_event(&s,1,1,400,240,140000)==TOUCH_DOWN);
 CHECK(touch_event(&s,0,0,0,0,280000)==TOUCH_NONE);
 CHECK(touch_event(&s,0,0,0,0,300001)==TOUCH_CANCEL);
 printf("PASS TOUCH_EVENTS checks=%u mapping/debounce/repeat/multitouch/release/timeout\n",checks);return 0;
}
