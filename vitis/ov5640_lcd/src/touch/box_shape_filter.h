#ifndef BOX_SHAPE_FILTER_H
#define BOX_SHAPE_FILTER_H
#include "../pan_tilt/cap_components.h"
typedef struct {
 unsigned initialized,generation,seen;
 uint32_t frame_id;
 double width,height;
 double proposal[2];
 unsigned votes[2],changing[2];
 int direction[2];
} BoxShapeFilter;
void box_shape_init(BoxShapeFilter *s);
/* Display dimensions only. raw is never modified; target center/PD stay unfiltered. */
int box_shape_update(BoxShapeFilter *s,const CapBox *raw,uint32_t frame,unsigned generation,
 int valid,unsigned image_width,unsigned image_height,CapBox *display);
#endif
