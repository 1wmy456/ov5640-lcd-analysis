#ifndef CAP_COMPONENTS_H
#define CAP_COMPONENTS_H
#include <stdint.h>
#ifndef CAP_MASK_WIDTH
#define CAP_MASK_WIDTH 200
#define CAP_MASK_HEIGHT 120
#define CAP_MASK_BLOCK 4
#endif
#define CAP_CELLS (CAP_MASK_WIDTH*CAP_MASK_HEIGHT)
#define CAP_WORDS ((CAP_CELLS+31)/32)
enum {CAP_READY,CAP_NO_CANDIDATE,CAP_ACQUIRING,CAP_LOCK_MISS,CAP_FRAME_ERROR,CAP_STALE};
typedef struct {
    uint16_t xmin,xmax,ymin,ymax;
    uint32_t area;
    double cx,cy,quality;
} CapBox;
typedef struct {
    unsigned valid,locked,reason,components,candidates,max_area,max_width,max_height;
    uint32_t frame_id;
    CapBox box;
} CapResult;
typedef struct {
    uint32_t raw[CAP_WORDS],work[CAP_WORDS];
    uint16_t queue[CAP_CELLS];
    unsigned stage,scan,head,tail,shape_index;
    unsigned lx,hx,ly,hy,area;
    uint32_t sx,sy,sxx,syy,sxy;
    double mx,my,cxx,cyy,cxy,det,shape_error;
    unsigned boundary,outliers;
    CapBox candidate,best,locked_box,pending_box;
    unsigned have_best,locked,misses,confirm;
    unsigned seen;
    uint32_t previous_frame;
    CapResult result;
} CapDetector;
void cap_detector_init(CapDetector *d);
/* raw[] must contain the immutable, coherent PL snapshot before begin(). */
void cap_detector_begin(CapDetector *d,uint32_t frame_id);
/* Bounded work, so UART and the 20ms control service continue running. */
int cap_detector_work(CapDetector *d,unsigned budget);
void cap_detector_invalidate(CapDetector *d,unsigned reason);
const char *cap_reason_name(unsigned reason);
#endif
