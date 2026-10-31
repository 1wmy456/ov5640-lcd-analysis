#ifndef TOUCH_DRIVER_H
#define TOUCH_DRIVER_H
#include "touch_events.h"
/* Returns 0 when this BSP does not contain the independent touch GPIO. */
int touch_init(unsigned lcd_id,unsigned width,unsigned height);
void touch_service(uint64_t now);
#endif
