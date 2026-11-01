#include "cap_components.h"
#include <string.h>
#include <math.h>
static int bit(const uint32_t *p,unsigned n){return (p[n>>5]>>(n&31))&1u;}
static void setbit(uint32_t *p,unsigned n){p[n>>5]|=1u<<(n&31);}
static void clearbit(uint32_t *p,unsigned n){p[n>>5]&=~(1u<<(n&31));}
static double side(const CapBox *b){double w=b->xmax-b->xmin+1,h=b->ymax-b->ymin+1;return w>h?w:h;}
static double distance2(const CapBox *a,const CapBox *b){double x=a->cx-b->cx,y=a->cy-b->cy;return x*x+y*y;}
static int matches(const CapBox *a,const CapBox *b,const CapDetector *d){
    double gate=d->association_gate>0?d->association_gate:side(b)*0.75,ratio=(double)a->area/b->area;
    if(gate<32)gate=32;
    if(gate>(d->association_gate>0?160:120))gate=d->association_gate>0?160:120;
    return ratio>=(d->association_min_area>0?d->association_min_area:0.5)&&ratio<=(d->association_max_area>0?d->association_max_area:2.0)&&distance2(a,b)<=gate*gate;
}
void cap_detector_init(CapDetector *d){memset(d,0,sizeof(*d));d->result.reason=CAP_NO_CANDIDATE;}
void cap_detector_invalidate(CapDetector *d,unsigned reason){
    d->stage=0;d->locked=0;d->confirm=0;d->misses=0;
    d->result.valid=0;d->result.locked=0;d->result.reason=reason;
    memset(&d->result.box,0,sizeof(d->result.box));
}
void cap_detector_begin(CapDetector *d,uint32_t frame){
    if(d->seen&&frame==d->previous_frame){d->stage=0;return;}
    if(d->seen&&(uint32_t)(frame-d->previous_frame)>8){d->locked=0;d->confirm=0;}
    d->seen=1;d->previous_frame=frame;d->stage=1;d->scan=0;d->have_best=0;
    memset(d->work,0,sizeof(d->work));memset(&d->result,0,sizeof(d->result));d->result.frame_id=frame;
}
static void enqueue(CapDetector *d,unsigned n){
    if(bit(d->work,n)){clearbit(d->work,n);d->queue[d->tail++]=(uint16_t)n;}
}
static int geometry(CapDetector *d){
    double w=d->hx-d->lx+1,h=d->hy-d->ly+1,extent=d->area/(w*h),tr,disc,minor,major;
    if(d->area>d->result.max_area){d->result.max_area=d->area;d->result.max_width=(unsigned)w;d->result.max_height=(unsigned)h;}
    if(d->area<20||d->area>CAP_CELLS/4||w<3||h<3||
       w>CAP_MASK_WIDTH*3/4||h>CAP_MASK_HEIGHT*3/4||extent<0.40||extent>0.96)return 0;
    d->mx=(double)d->sx/d->area;d->my=(double)d->sy/d->area;
    d->cxx=(double)d->sxx/d->area-d->mx*d->mx;
    d->cyy=(double)d->syy/d->area-d->my*d->my;
    d->cxy=(double)d->sxy/d->area-d->mx*d->my;
    d->det=d->cxx*d->cyy-d->cxy*d->cxy;
    if(d->det<=0.01)return 0;
    tr=d->cxx+d->cyy;disc=sqrt((d->cxx-d->cyy)*(d->cxx-d->cyy)+4*d->cxy*d->cxy);
    minor=(tr-disc)*0.5;major=(tr+disc)*0.5;
    if(minor<=0||major>7.84*minor)return 0; /* fitted ellipse axis ratio <= 2.8 */
    d->shape_index=0;d->shape_error=0;d->boundary=0;d->outliers=0;
    return 1;
}
static void consider(CapDetector *d){
    double score,best_score;
    CapBox *c=&d->candidate;
    if(d->boundary<8||d->shape_error/d->boundary>0.35||d->outliers*20u>d->area)return;
    d->result.candidates++;
    c->xmin=(uint16_t)(d->lx*CAP_MASK_BLOCK);c->xmax=(uint16_t)((d->hx+1)*CAP_MASK_BLOCK-1);
    c->ymin=(uint16_t)(d->ly*CAP_MASK_BLOCK);c->ymax=(uint16_t)((d->hy+1)*CAP_MASK_BLOCK-1);
    c->area=d->area*CAP_MASK_BLOCK*CAP_MASK_BLOCK;
    c->cx=(d->mx+0.5)*CAP_MASK_BLOCK;c->cy=(d->my+0.5)*CAP_MASK_BLOCK;
    c->quality=1.0-d->shape_error/d->boundary;
    if(d->locked){
        if(!matches(c,&d->locked_box,d))return;
        score=distance2(c,&d->locked_box)+(1-c->quality)*1024;
        best_score=distance2(&d->best,&d->locked_box)+(1-d->best.quality)*1024;
    }else{
        double x=c->cx-CAP_MASK_WIDTH*CAP_MASK_BLOCK*0.5,y=c->cy-CAP_MASK_HEIGHT*CAP_MASK_BLOCK*0.5;
        double bx=d->best.cx-CAP_MASK_WIDTH*CAP_MASK_BLOCK*0.5,by=d->best.cy-CAP_MASK_HEIGHT*CAP_MASK_BLOCK*0.5;
        score=(1-c->quality)*10000+(x*x+y*y)*0.01-sqrt(c->area);
        best_score=(1-d->best.quality)*10000+(bx*bx+by*by)*0.01-sqrt(d->best.area);
    }
    if(!d->have_best||score<best_score){d->best=*c;d->have_best=1;}
}
static void finish(CapDetector *d){
    CapBox out;
    if(!d->have_best){
        d->result.reason=d->locked?CAP_LOCK_MISS:CAP_NO_CANDIDATE;
        if(d->locked&&++d->misses>6){d->locked=0;d->confirm=0;}
        if(!d->locked)d->confirm=0;
    }else{
        if(!d->locked){
            if(d->confirm&&matches(&d->best,&d->pending_box,d))d->confirm++;else d->confirm=1;
            d->pending_box=d->best;
            if(d->confirm>=2){d->locked=1;d->locked_box=d->best;}
        }
        if(d->locked){
            out=d->best;
            /* Smooth only the associated object, never coordinates from another blob. */
            out.xmin=(out.xmin+d->locked_box.xmin+1)/2;out.xmax=(out.xmax+d->locked_box.xmax+1)/2;
            out.ymin=(out.ymin+d->locked_box.ymin+1)/2;out.ymax=(out.ymax+d->locked_box.ymax+1)/2;
            d->locked_box=out;d->misses=0;d->result.box=out;d->result.valid=1;d->result.reason=CAP_READY;
        }else d->result.reason=CAP_ACQUIRING;
    }
    d->result.locked=d->locked;d->stage=0;
}
int cap_detector_work(CapDetector *d,unsigned budget){
    unsigned n,x,y,k,neighbors;
    while(budget--&&d->stage){
        if(d->stage==1){
            /* Small majority filter removes single-cell speckle and thin strands. */
            n=d->scan++;x=n%CAP_MASK_WIDTH;y=n/CAP_MASK_WIDTH;neighbors=0;
            for(int dy=-1;dy<=1;dy++)for(int dx=-1;dx<=1;dx++){
                int xx=(int)x+dx,yy=(int)y+dy;
                if(xx>=0&&xx<CAP_MASK_WIDTH&&yy>=0&&yy<CAP_MASK_HEIGHT)
                    neighbors+=bit(d->raw,(unsigned)(yy*CAP_MASK_WIDTH+xx));
            }
            if(neighbors>=(bit(d->raw,n)?4u:6u))setbit(d->work,n);
            if(d->scan==CAP_CELLS){memcpy(d->raw,d->work,sizeof(d->raw));d->stage=2;d->scan=0;}
        }else if(d->stage==2){
            if(d->scan==CAP_CELLS){finish(d);return 1;}
            n=d->scan++;
            if(bit(d->work,n)){
                d->head=d->tail=0;enqueue(d,n);d->area=d->sx=d->sy=d->sxx=d->syy=d->sxy=0;
                d->lx=CAP_MASK_WIDTH;d->ly=CAP_MASK_HEIGHT;d->hx=d->hy=0;d->stage=3;d->result.components++;
            }
        }else if(d->stage==3){
            n=d->queue[d->head++];x=n%CAP_MASK_WIDTH;y=n/CAP_MASK_WIDTH;
            d->area++;d->sx+=x;d->sy+=y;d->sxx+=x*x;d->syy+=y*y;d->sxy+=x*y;
            if(x<d->lx)d->lx=x;
            if(x>d->hx)d->hx=x;
            if(y<d->ly)d->ly=y;
            if(y>d->hy)d->hy=y;
            if(x)enqueue(d,n-1);
            if(x+1<CAP_MASK_WIDTH)enqueue(d,n+1);
            if(y)enqueue(d,n-CAP_MASK_WIDTH);
            if(y+1<CAP_MASK_HEIGHT)enqueue(d,n+CAP_MASK_WIDTH);
            if(d->head==d->tail)d->stage=geometry(d)?4:2;
        }else{
            double dx,dy,r2;
            n=d->queue[d->shape_index++];x=n%CAP_MASK_WIDTH;y=n/CAP_MASK_WIDTH;
            dx=x-d->mx;dy=y-d->my;
            r2=(d->cyy*dx*dx-2*d->cxy*dx*dy+d->cxx*dy*dy)/(4*d->det);
            if(r2>1.5)d->outliers++;
            k=(!x||!y||x+1==CAP_MASK_WIDTH||y+1==CAP_MASK_HEIGHT);
            if(!k)k=!bit(d->raw,n-1)||!bit(d->raw,n+1)||!bit(d->raw,n-CAP_MASK_WIDTH)||!bit(d->raw,n+CAP_MASK_WIDTH);
            /* Ignore inner pinhole boundaries; retain the outer silhouette. */
            if(k&&r2>0.45){d->boundary++;d->shape_error+=fabs(r2-1);}
            if(d->shape_index==d->tail){consider(d);d->stage=2;}
        }
    }
    return d->stage==0;
}
const char *cap_reason_name(unsigned r){
    static const char *names[]={"ready","no_blob","acquire","lock_miss","frame_error","stale"};
    return r<sizeof(names)/sizeof(names[0])?names[r]:"unknown";
}
