#include "appearance_tracker.h"
#include <string.h>
#include <stdlib.h>
#include <math.h>
static ApColor color(uint32_t p){
 int r=(p>>16)&255,g=(p>>8)&255,b=p&255,y=(r+2*g+b)/4,sum=r+g+b;
 /* Normalized chromaticity, independent of a common illumination scale. */
 ApColor c={y,sum?b*255/sum-85:0,sum?r*255/sum-85:0};return c;
}
static int matches(ApColor a,ApColor b,unsigned radius){int dy=a.y-b.y,db=a.cb-b.cb,dr=a.cr-b.cr;return abs(dy)<=96&&(unsigned)(db*db+dr*dr)<=radius*radius;}
static unsigned bit(const uint32_t *a,unsigned n){return (a[n>>5]>>(n&31))&1u;}
static void set(uint32_t *a,unsigned n){a[n>>5]|=1u<<(n&31);}
static void clear(uint32_t *a,unsigned n){a[n>>5]&=~(1u<<(n&31));}
static int search_work(AppearanceWork *w,unsigned budget);
static void search_begin(AppearanceWork *w){
 AppearanceTracker *t=w->tracker;unsigned df=w->frame_id-t->frame_id;
 double vx=t->state==AP_TRACK?t->velocity_x:0,vy=t->state==AP_TRACK?t->velocity_y:0;
 if(df>12)vx=vy=0;
 w->pred_x=(int)((t->box.cx+vx*df)/4);w->pred_y=(int)((t->box.cy+vy*df)/4);
 if(w->pred_x<0)w->pred_x=0;
 if(w->pred_x>=CAP_MASK_WIDTH)w->pred_x=CAP_MASK_WIDTH-1;
 if(w->pred_y<0)w->pred_y=0;
 if(w->pred_y>=CAP_MASK_HEIGHT)w->pred_y=CAP_MASK_HEIGHT-1;
 unsigned side=t->reference_box.xmax-t->reference_box.xmin+1,h=t->reference_box.ymax-t->reference_box.ymin+1;
 if(h>side)side=h;
 int gate=(int)(side*0.9);if(gate<48)gate=48;if(gate>160)gate=160;gate/=4;
 w->search_lx=w->pred_x-gate;w->search_hx=w->pred_x+gate;w->search_ly=w->pred_y-gate;w->search_hy=w->pred_y+gate;
 if(w->search_lx<0)w->search_lx=0;
 if(w->search_ly<0)w->search_ly=0;
 if(w->search_hx>=CAP_MASK_WIDTH)w->search_hx=CAP_MASK_WIDTH-1;
 if(w->search_hy>=CAP_MASK_HEIGHT)w->search_hy=CAP_MASK_HEIGHT-1;
 for(unsigned i=0;i<64;i++){
  unsigned f=t->anchor_histogram[i],b=t->background_histogram[i];
  w->probability[i]=f>=32?(4096u*f/(f+b+1)):0;
 }
 w->search_x=w->search_lx;w->search_y=w->search_ly;w->search_best_score=-100000;
 w->fast=1;w->busy=1;
}
static int median(int a[9],unsigned n){unsigned i,j;for(i=1;i<n;i++){int v=a[i];for(j=i;j&&a[j-1]>v;j--)a[j]=a[j-1];a[j]=v;}return a[n/2];}
static ApColor seed(const uint32_t *rgb,unsigned x,unsigned y,unsigned *radius){
 int yy[9],cb[9],cr[9],distance[9],dx,dy;unsigned n=0,k=0;ApColor c;
 for(dy=-1;dy<=1;dy++)for(dx=-1;dx<=1;dx++){
  int xx=(int)x+dx,rr=(int)y+dy;
  if(xx>=0&&rr>=0&&xx<CAP_MASK_WIDTH&&rr<CAP_MASK_HEIGHT){c=color(rgb[rr*CAP_MASK_WIDTH+xx]);yy[n]=c.y;cb[n]=c.cb;cr[n++]=c.cr;}
 }
 c.y=median(yy,n);c.cb=median(cb,n);c.cr=median(cr,n);
 for(dy=-1;dy<=1;dy++)for(dx=-1;dx<=1;dx++){
  int xx=(int)x+dx,rr=(int)y+dy;
  if(xx>=0&&rr>=0&&xx<CAP_MASK_WIDTH&&rr<CAP_MASK_HEIGHT){ApColor p=color(rgb[rr*CAP_MASK_WIDTH+xx]);int db=p.cb-c.cb,dr=p.cr-c.cr;distance[k++]=db*db+dr*dr;}
 }
 *radius=(unsigned)sqrt(18*18+9*median(distance,k));if(*radius>42)*radius=42;
 return c;
}
void appearance_init(AppearanceTracker *t){memset(t,0,sizeof(*t));t->state=AP_SELECT;}
void appearance_invalidate(AppearanceTracker *t,unsigned reason){t->valid=0;t->reason=reason;if(t->has_model)t->state=AP_LOST;}
static void enqueue(CapDetector *d,unsigned n){if(bit(d->raw,n)){clear(d->raw,n);set(d->work,n);d->queue[d->tail++]=(uint16_t)n;}}
void appearance_begin(AppearanceWork *w,AppearanceTracker *t,const uint32_t *rgb,uint32_t frame,int selecting,unsigned x,unsigned y){
 CapDetector *d=&w->detector;unsigned n;
 memset(w,0,sizeof(*w));w->rgb=rgb;w->tracker=t;w->frame_id=frame;w->selecting=!!selecting;w->click_x=x;w->click_y=y;
 if((selecting&&(x>=800||y>=480))||(!selecting&&!t->has_model))return;
 if(!selecting&&t->appearance_ready){search_begin(w);return;}
 cap_detector_init(d);w->chroma_radius=t->chroma_radius;
 w->proposed=selecting?seed(rgb,x/4,y/4,&w->chroma_radius):t->color;
 for(n=0;n<CAP_CELLS;n++)if(matches(color(rgb[n]),w->proposed,w->chroma_radius))set(d->raw,n);
 if(selecting){
  /* Keep only the clicked component. No fixed color table or central-object preference. */
  enqueue(d,(y/4)*CAP_MASK_WIDTH+x/4);
  while(d->head<d->tail){n=d->queue[d->head++];unsigned xx=n%CAP_MASK_WIDTH,yy=n/CAP_MASK_WIDTH;
   if(xx)enqueue(d,n-1);
   if(xx+1<CAP_MASK_WIDTH)enqueue(d,n+1);
   if(yy)enqueue(d,n-CAP_MASK_WIDTH);
   if(yy+1<CAP_MASK_HEIGHT)enqueue(d,n+CAP_MASK_WIDTH);
  }
  memcpy(d->raw,d->work,sizeof(d->raw));
 }else {
  d->locked=1;d->locked_box=t->box;
  if(t->reference_box.area){
   unsigned rw=t->reference_box.xmax-t->reference_box.xmin+1,rh=t->reference_box.ymax-t->reference_box.ymin+1;
   unsigned bw=t->box.xmax-t->box.xmin+1,bh=t->box.ymax-t->box.ymin+1;
   unsigned side=rw>rh?rw:rh;if(bw>side)side=bw;if(bh>side)side=bh;
   d->locked_box.area=t->reference_box.area;d->association_min_area=0.35;d->association_max_area=4.0;d->association_gate=side*0.9;
  }
 }
 cap_detector_begin(d,frame);w->busy=1;
}
static unsigned histogram(AppearanceWork *w,CapBox b,uint16_t out[64],ApColor *mean){
 uint32_t hist[64]={0},smooth[64]={0};int sy=0,scb=0,scr=0;unsigned x,y,n=0,i,total=0;
 for(y=b.ymin/4;y<=b.ymax/4&&y<CAP_MASK_HEIGHT;y++)for(x=b.xmin/4;x<=b.xmax/4&&x<CAP_MASK_WIDTH;x++){
  unsigned index=y*CAP_MASK_WIDTH+x;
  if(bit(w->detector.raw,index)){
   uint32_t p=w->rgb[index];ApColor c=color(p);unsigned bin=((unsigned)(c.cb+85)>>5)*8+((unsigned)(c.cr+85)>>5);
   hist[bin]++;n++;sy+=c.y;scb+=c.cb;scr+=c.cr;
  }
 }
 if(!n)return 0;
 /* Smooth neighboring chromaticity bins; avoid a hard-bin boundary causing LOST. */
 for(y=0;y<8;y++)for(x=0;x<8;x++)if(hist[y*8+x]){
  for(int dy=-1;dy<=1;dy++)for(int dx=-1;dx<=1;dx++){
   int xx=(int)x+dx,yy=(int)y+dy;unsigned weight=(dx?1u:2u)*(dy?1u:2u);
   if(xx>=0&&xx<8&&yy>=0&&yy<8){smooth[yy*8+xx]+=hist[y*8+x]*weight;total+=hist[y*8+x]*weight;}
  }
 }
 for(i=0;i<64;i++)out[i]=(uint16_t)((smooth[i]*4096u+total/2)/total);
 mean->y=sy/(int)n;mean->cb=scb/(int)n;mean->cr=scr/(int)n;return n;
}
static unsigned intersection(const uint16_t *a,const uint16_t *b){unsigned i,v=0;for(i=0;i<64;i++)v+=a[i]<b[i]?a[i]:b[i];return v>4096?4096:v;}
static void background_model(AppearanceWork *w,CapBox b,uint16_t out[64]){
 uint32_t raw_hist[64]={0},smooth[64]={0};unsigned total=0;
 int lx=b.xmin/4,hx=b.xmax/4,ly=b.ymin/4,hy=b.ymax/4,mx=(hx-lx+1)/3+1,my=(hy-ly+1)/3+1;
 for(int y=ly-my;y<=hy+my;y++)for(int x=lx-mx;x<=hx+mx;x++){
  if(x<0||y<0||x>=CAP_MASK_WIDTH||y>=CAP_MASK_HEIGHT||(x>=lx&&x<=hx&&y>=ly&&y<=hy))continue;
  ApColor c=color(w->rgb[y*CAP_MASK_WIDTH+x]);raw_hist[((c.cb+85)>>5)*8+((c.cr+85)>>5)]++;
 }
 for(int y=0;y<8;y++)for(int x=0;x<8;x++)for(int dy=-1;dy<=1;dy++)for(int dx=-1;dx<=1;dx++){
  int xx=x+dx,yy=y+dy;if(xx>=0&&xx<8&&yy>=0&&yy<8){unsigned v=raw_hist[y*8+x]*(dx?1u:2u)*(dy?1u:2u);smooth[yy*8+xx]+=v;total+=v;}
 }
 for(unsigned i=0;i<64;i++)out[i]=total?(uint16_t)((smooth[i]*4096u+total/2)/total):0;
}
static unsigned region_radius(AppearanceWork *w,CapBox b,ApColor mean){
 unsigned bins[64]={0},total=0,cumulative=0,x,y,k;
 for(y=b.ymin/4;y<=b.ymax/4;y++)for(x=b.xmin/4;x<=b.xmax/4;x++){
  unsigned n=y*CAP_MASK_WIDTH+x;if(bit(w->detector.raw,n)){
   ApColor c=color(w->rgb[n]);int db=c.cb-mean.cb,dr=c.cr-mean.cr;
   unsigned index=(unsigned)(db*db+dr*dr)/64;if(index>63)index=63;bins[index]++;total++;
  }
 }
 for(k=0;k<64;k++){cumulative+=bins[k];if(cumulative*10>=total*9)break;}
 unsigned radius=(unsigned)(sqrt((k+1)*64.0)*1.5+8);return radius<18?18:(radius>60?60:radius);
}
int appearance_work(AppearanceWork *w,unsigned budget){
 AppearanceTracker *t=w->tracker;CapDetector *d=&w->detector;CapBox b;uint16_t hist[64];ApColor mean;unsigned score,anchor_score,i;
 if(!w->busy)return 1;
 if(w->fast)return search_work(w,budget);
 if(!cap_detector_work(d,budget))return 0;
 w->busy=0;
 if(!d->have_best){if(w->selecting){t->reason=AP_BACKGROUND;}else{t->frame_id=w->frame_id;t->misses++;appearance_invalidate(t,AP_NO_MATCH);}return 1;}
 b=d->best;
 if(!histogram(w,b,hist,&mean)){if(w->selecting)t->reason=AP_BACKGROUND;else appearance_invalidate(t,AP_NO_MATCH);return 1;}
 if(w->selecting){
  if(w->click_x+4<b.xmin||w->click_x>b.xmax+4u||w->click_y+4<b.ymin||w->click_y>b.ymax+4u){t->reason=AP_BACKGROUND;return 1;}
  t->has_model=1;t->generation++;t->anchor=t->color=mean;t->box=t->reference_box=b;t->similarity=4096;t->chroma_radius=region_radius(w,b,mean);
  memcpy(t->histogram,hist,sizeof(hist));memcpy(t->anchor_histogram,hist,sizeof(hist));w->selection_accepted=1;
  background_model(w,b,t->background_histogram);t->appearance_ready=1;t->velocity_x=t->velocity_y=0;
 }else{
  score=intersection(t->histogram,hist);anchor_score=intersection(t->anchor_histogram,hist);t->similarity=score;
  if(score<1638||anchor_score<1434){t->frame_id=w->frame_id;t->misses++;appearance_invalidate(t,AP_APPEARANCE);return 1;}
  /* Preserve an immutable initial model; update only confident, continuously associated frames. */
  if(t->state==AP_TRACK&&score>=3686&&anchor_score>=3277&&b.quality>=0.72){
   ApColor proposed={(15*t->color.y+mean.y)/16,(15*t->color.cb+mean.cb)/16,(15*t->color.cr+mean.cr)/16};
   if(abs(proposed.y-t->anchor.y)<=20&&abs(proposed.cb-t->anchor.cb)<=18&&abs(proposed.cr-t->anchor.cr)<=18){
    t->color=proposed;for(i=0;i<64;i++)t->histogram[i]=(15*t->histogram[i]+hist[i]+8)/16;
   }
  }
  t->box=b;
 }
 t->state=AP_TRACK;t->valid=1;t->reason=AP_OK;t->misses=0;t->frame_id=w->frame_id;return 1;
}
static unsigned rectangle(AppearanceWork *w,int lx,int ly,int hx,int hy,unsigned *area){
 if(lx<0)lx=0;
 if(ly<0)ly=0;
 if(hx>=CAP_MASK_WIDTH)hx=CAP_MASK_WIDTH-1;
 if(hy>=CAP_MASK_HEIGHT)hy=CAP_MASK_HEIGHT-1;
 if(lx>hx||ly>hy){*area=0;return 0;}
 unsigned stride=CAP_MASK_WIDTH+1;*area=(hx-lx+1)*(hy-ly+1);
 return w->integral[(hy+1)*stride+hx+1]-w->integral[ly*stride+hx+1]-w->integral[(hy+1)*stride+lx]+w->integral[ly*stride+lx];
}
static int search_finish(AppearanceWork *w){
 AppearanceTracker *t=w->tracker;uint16_t hist[64];ApColor mean;CapBox b;unsigned score,anchor_score,df=w->frame_id-t->frame_id;
 w->busy=0;
 if(w->search_best_score<1400)goto lost;
 int lx=w->search_best_x-w->search_best_w/2,ly=w->search_best_y-w->search_best_h/2;
 int hx=lx+w->search_best_w-1,hy=ly+w->search_best_h-1;
 if(lx<0)lx=0;
 if(ly<0)ly=0;
 if(hx>=CAP_MASK_WIDTH)hx=CAP_MASK_WIDTH-1;
 if(hy>=CAP_MASK_HEIGHT)hy=CAP_MASK_HEIGHT-1;
 memset(&b,0,sizeof(b));b.xmin=lx*4;b.xmax=(hx+1)*4-1;b.ymin=ly*4;b.ymax=(hy+1)*4-1;
 b.cx=(b.xmin+b.xmax)*0.5;b.cy=(b.ymin+b.ymax)*0.5;b.quality=w->search_best_score/4096.0;
 unsigned n=histogram(w,b,hist,&mean);b.area=n*16;
 if(n<20||b.area<t->reference_box.area*0.35||b.area>t->reference_box.area*4.0)goto lost;
 score=intersection(t->histogram,hist);anchor_score=intersection(t->anchor_histogram,hist);t->similarity=score;
 if(score<1638||anchor_score<1434)goto lost;
 if(df&&df<=12&&t->state==AP_TRACK){
  double vx=(b.cx-t->box.cx)/df,vy=(b.cy-t->box.cy)/df;
  if(vx>20)vx=20;
  if(vx< -20)vx=-20;
  if(vy>20)vy=20;
  if(vy< -20)vy=-20;
  t->velocity_x=(t->velocity_x+vx)*0.5;t->velocity_y=(t->velocity_y+vy)*0.5;
 }else t->velocity_x=t->velocity_y=0;
 /* Initial foreground/background anchors stay immutable. Only confident continuous
    matches may refine the active descriptor; temporary losses never train anything. */
 if(t->state==AP_TRACK&&w->search_best_score>=3000&&score>=3686&&anchor_score>=3277){
  for(unsigned i=0;i<64;i++)t->histogram[i]=(15*t->histogram[i]+hist[i]+8)/16;
 }
 t->box=b;t->frame_id=w->frame_id;t->state=AP_TRACK;t->valid=1;t->reason=AP_OK;t->misses=0;
 return 1;
lost:
 t->frame_id=w->frame_id;t->misses++;t->velocity_x=t->velocity_y=0;appearance_invalidate(t,AP_NO_MATCH);return 1;
}
static int search_work(AppearanceWork *w,unsigned budget){
 static const int scale[3]={85,100,118};AppearanceTracker *t=w->tracker;unsigned stride=CAP_MASK_WIDTH+1;
 while(budget--){
  if(w->search_stage==0){
   unsigned n=w->search_scan++,x=n%CAP_MASK_WIDTH,y=n/CAP_MASK_WIDTH;ApColor c=color(w->rgb[n]);
   unsigned bin=((c.cb+85)>>5)*8+((c.cr+85)>>5),p=w->probability[bin];
   if(abs(c.y-t->anchor.y)>110)p=0;
   w->likelihood[n]=(uint16_t)p;if(p>=2000)set(w->detector.raw,n);
   w->integral[(y+1)*stride+x+1]=p+w->integral[(y+1)*stride+x]+w->integral[y*stride+x+1]-w->integral[y*stride+x];
   if(w->search_scan==CAP_CELLS)w->search_stage=1;
  }else{
   int bw=(t->box.xmax-t->box.xmin+1)/4,bh=(t->box.ymax-t->box.ymin+1)/4;
   int rw=(t->reference_box.xmax-t->reference_box.xmin+1)/4,rh=(t->reference_box.ymax-t->reference_box.ymin+1)/4;
   int ww=bw*scale[w->search_scale%3]/100,hh=bh*scale[w->search_scale/3]/100;
   if(ww<rw*3/5)ww=rw*3/5;
   if(hh<rh*3/5)hh=rh*3/5;
   if(ww>rw*2)ww=rw*2;
   if(hh>rh*2)hh=rh*2;
   if(ww<3)ww=3;
   if(hh<3)hh=3;
   int x=w->search_x,y=w->search_y,lx=x-ww/2,ly=y-hh/2,hx=lx+ww-1,hy=ly+hh-1;
   unsigned ia,oa,ma;
   unsigned inner=rectangle(w,lx+ww/5,ly+hh/5,hx-ww/5,hy-hh/5,&ia);
   unsigned outer=rectangle(w,lx-ww/4-1,ly-hh/4-1,hx+ww/4+1,hy+hh/4+1,&oa);
   unsigned main=rectangle(w,lx,ly,hx,hy,&ma);
   if(ia&&oa>ma){
    int im=inner/ia,om=(outer-main)/(oa-ma);
    int dx=x-w->pred_x,dy=y-w->pred_y,gate=w->search_hx-w->search_lx+1;
    int score=im-om*3/5-(dx*dx+dy*dy)*1024/(gate*gate+1);
    if(im>=2000&&im-om>=600&&score>w->search_best_score){
     w->search_best_score=score;w->search_best_x=x;w->search_best_y=y;w->search_best_w=ww;w->search_best_h=hh;
    }
   }
   w->search_x+=2;
   if(w->search_x>w->search_hx){w->search_x=w->search_lx;w->search_y+=2;}
   if(w->search_y>w->search_hy){w->search_y=w->search_ly;if(++w->search_scale==9)return search_finish(w);}
  }
 }
 return 0;
}
