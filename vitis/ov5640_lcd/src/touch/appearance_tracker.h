#ifndef APPEARANCE_TRACKER_H
#define APPEARANCE_TRACKER_H
#include "../pan_tilt/cap_components.h"
enum { AP_SELECT,AP_TRACK,AP_LOST };
enum { AP_OK,AP_BACKGROUND,AP_NO_MATCH,AP_APPEARANCE,AP_BAD_FRAME };
typedef struct { int y,cb,cr; } ApColor;
typedef struct {
 unsigned has_model,state,valid,reason,misses,generation,similarity,chroma_radius;
 uint32_t frame_id;
 CapBox box;
 ApColor anchor,color;
 uint16_t histogram[64],anchor_histogram[64];
    CapBox reference_box;
    uint16_t background_histogram[64];
    unsigned appearance_ready;
    double velocity_x,velocity_y;
} AppearanceTracker;
typedef struct {
 CapDetector detector;
 const uint32_t *rgb;
 AppearanceTracker *tracker;
 ApColor proposed;
 unsigned selecting,click_x,click_y,busy,selection_accepted,chroma_radius;
 uint32_t frame_id;
    uint32_t integral[(CAP_MASK_WIDTH+1)*(CAP_MASK_HEIGHT+1)];
    uint16_t likelihood[CAP_CELLS];
    unsigned probability[64],search_stage,search_scan,search_scale;
    int search_x,search_y,search_lx,search_hx,search_ly,search_hy,pred_x,pred_y;
    int search_best_score,search_best_x,search_best_y,search_best_w,search_best_h;
    unsigned fast;
    unsigned global_luma;
} AppearanceWork;
void appearance_init(AppearanceTracker *t);
void appearance_begin(AppearanceWork *w,AppearanceTracker *t,const uint32_t *rgb,
 uint32_t frame_id,int selecting,unsigned x,unsigned y);
int appearance_work(AppearanceWork *w,unsigned budget);
void appearance_invalidate(AppearanceTracker *t,unsigned reason);
#endif
