#include "cap_components.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
static CapDetector d;
static unsigned checks,frames,total_frames;
#define CHECK(x) do{checks++;if(!(x)){fprintf(stderr,"FAIL CAP line=%d frame=%u valid=%u why=%s box=%u,%u,%u,%u candidates=%u\n",__LINE__,frames,d.result.valid,cap_reason_name(d.result.reason),d.result.box.xmin,d.result.box.xmax,d.result.box.ymin,d.result.box.ymax,d.result.candidates);exit(1);}}while(0)
static void clear(void){memset(d.raw,0,sizeof(d.raw));}
static void pixel(int x,int y){if(x>=0&&x<CAP_MASK_WIDTH&&y>=0&&y<CAP_MASK_HEIGHT){unsigned n=y*CAP_MASK_WIDTH+x;d.raw[n>>5]|=1u<<(n&31);}}
static void ellipse(int cx,int cy,int a,int b){
    for(int y=0;y<CAP_MASK_HEIGHT;y++)for(int x=0;x<CAP_MASK_WIDTH;x++){
        long dx=x-cx,dy=y-cy;
        if(dx*dx*b*b+dy*dy*a*a<=(long)a*a*b*b)pixel(x,y);
    }
}
static void rect(int x0,int y0,int w,int h){for(int y=y0;y<y0+h;y++)for(int x=x0;x<x0+w;x++)pixel(x,y);}
static void run(void){unsigned calls=0;total_frames++;cap_detector_begin(&d,++frames);while(!cap_detector_work(&d,137)){CHECK(++calls<10000);}CHECK(d.stage==0);}
int main(void){
    clock_t start=clock();cap_detector_init(&d);
    clear();run();CHECK(!d.result.valid&&d.result.reason==CAP_NO_CANDIDATE);
    for(int i=0;i<3;i++){
        clear();ellipse(60,60,12,9);rect(5,5,55,20);pixel(190,110);run();
        CHECK(d.result.candidates==1);if(i==0)CHECK(!d.result.valid);else CHECK(d.result.valid);
    }
    CHECK(d.result.box.xmax-d.result.box.xmin<110&&d.result.box.xmin>180);
    /* A larger blue disk elsewhere must not steal the already locked target. */
    for(int i=0;i<12;i++){
        clear();ellipse(60+i,60,12,9);ellipse(160,60,18,12);run();
        CHECK(d.result.valid&&d.result.box.xmax<400);
    }
    /* Loss invalidates immediately; association history does not authorize motion. */
    for(int i=0;i<6;i++){clear();ellipse(160,60,18,12);run();CHECK(!d.result.valid&&d.result.reason==CAP_LOCK_MISS);}
    clear();ellipse(71,60,12,9);run();CHECK(d.result.valid&&d.result.box.xmax<400);
    /* A connected, remote lobe cannot make the selected box grow across the scene. */
    clear();ellipse(71,60,12,9);rect(80,59,90,3);ellipse(165,60,15,13);run();CHECK(!d.result.valid);
    cap_detector_invalidate(&d,CAP_FRAME_ERROR);CHECK(!d.result.valid&&!d.locked);
    clear();ellipse(100,60,20,8);run();CHECK(!d.result.valid);
    clear();ellipse(100,60,20,8);run();CHECK(d.result.valid); /* 2.5:1 ellipse */
    cap_detector_invalidate(&d,CAP_FRAME_ERROR);
    clear();rect(20,20,130,60);run();CHECK(!d.result.valid);
    clear();rect(10,60,170,1);run();CHECK(!d.result.valid);
    clear();for(int y=0;y<CAP_MASK_HEIGHT;y+=4)for(int x=0;x<CAP_MASK_WIDTH;x+=4)pixel(x,y);run();CHECK(!d.result.valid);
    /* Frame-edge target remains bounded. */
    clear();ellipse(4,60,10,9);run();
    clear();ellipse(4,60,10,9);run();CHECK(d.result.valid&&d.result.box.xmin==0);
    cap_detector_invalidate(&d,CAP_FRAME_ERROR);
    clear();ellipse(100,60,12,12);run();CHECK(!d.result.valid);
    cap_detector_begin(&d,frames);CHECK(cap_detector_work(&d,1)&&!d.result.valid); /* duplicate cannot confirm */
    clear();ellipse(100,60,12,12);run();CHECK(d.result.valid);
    d.previous_frame=UINT32_MAX;frames=0;clear();ellipse(100,60,12,12);run();CHECK(d.result.valid);
    printf("PASS CAP_COMPONENTS checks=%u frames=%u host_ms=%.2f circle/ellipse/multiple/background/lock/loss/recovery/edge/duplicate/wrap\n",checks,total_frames,1000.0*(clock()-start)/CLOCKS_PER_SEC);
    return 0;
}
