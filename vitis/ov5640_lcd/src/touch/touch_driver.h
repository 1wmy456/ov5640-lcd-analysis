#ifndef TOUCH_DRIVER_H
#define TOUCH_DRIVER_H
#include "touch_events.h"
/* Returns 0 when this BSP does not contain the independent touch GPIO. */
int touch_init(unsigned lcd_id,unsigned width,unsigned height);
void touch_service(uint64_t now);
typedef void (*TouchHandler)(unsigned event,unsigned x,unsigned y,uint64_t now);
void touch_set_handler(TouchHandler handler);
void touch_capture_control(unsigned flags); /* bit0 arm, bit1 abort */
void touch_display_state(unsigned state); /* SELECT=0 TRACK=1 LOST=2 */
#endif
