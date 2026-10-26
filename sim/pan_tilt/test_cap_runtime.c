#include "cap_runtime.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
static uint32_t regs[1024],live[CAP_WORDS],held[CAP_WORDS];
static uint64_t now;
static unsigned checks,reads,commits;
#define CHECK(x) do{checks++;if(!(x)){fprintf(stderr,"FAIL RUNTIME line=%d now=%llu\n",__LINE__,(unsigned long long)now);exit(1);}}while(0)
u32 pt_reg_read(UINTPTR base,unsigned off){
    (void)base;
    if(off>=0x200&&off<0x200+4*CAP_WORDS){CHECK(regs[0xd0/4]&1);reads++;return held[(off-0x200)/4];}
    return regs[off/4];
}
void pt_reg_write(UINTPTR base,unsigned off,u32 value){
    (void)base;regs[off/4]=value;
    if(off==0xd0&&value){
        memcpy(held,live,sizeof(held));regs[0xd4/4]=regs[0xec/4];
        regs[0xd8/4]=regs[0xf0/4]?6:5;regs[0xdc/4]=regs[0xf4/4];regs[0x124/4]=regs[0xf8/4];
    }
    if(off==0x114&&value){
        commits++;regs[0x118/4]=(regs[0x110/4]&1)&&!regs[0xf0/4]&&regs[0x124/4]==regs[0xf8/4];
    }
}
static void setup(void){
    memset(regs,0,sizeof(regs));regs[1]=0x10100;regs[0xfc/4]=0x43434c31;
    regs[0xe0/4]=(CAP_MASK_HEIGHT<<16)|CAP_MASK_WIDTH;regs[0xe4/4]=CAP_MASK_BLOCK;regs[0xe8/4]=CAP_WORDS;
    CHECK(cap_runtime_init(0));
}
static void scene(unsigned id,int cx){
    memset(live,0,sizeof(live));
    if(cx>=0)for(int y=0;y<CAP_MASK_HEIGHT;y++)for(int x=0;x<CAP_MASK_WIDTH;x++){
        int dx=x-cx,dy=y-60;if(dx*dx+dy*dy<=144){unsigned n=y*CAP_MASK_WIDTH+x;live[n>>5]|=1u<<(n&31);}
    }
    regs[0xec/4]=id;regs[0xf0/4]=0;regs[0xf4/4]=0;
}
static void tick(void){now+=10;cap_runtime_service(0,now);}
static void finish(void){unsigned before=commits,n=0;while(commits==before){tick();CHECK(++n<1000);}}
int main(void){
    PtTarget t;
    setup();scene(1,60);finish();cap_runtime_target(0,now,&t);CHECK(t.frame_id==1&&!(t.flags&1));
    scene(2,60);tick();tick();CHECK(regs[0xd0/4]==1);
    scene(3,160); /* Camera changes while PS reads the immutable frame-2 snapshot. */
    finish();cap_runtime_target(0,now,&t);CHECK(t.frame_id==2&&(t.flags&1)&&t.xmax<400);
    CHECK(regs[0xd0/4]==0&&reads==2*CAP_WORDS&&regs[0x118/4]);
    unsigned old_commits=commits;
    /* Reader may sample a new frame ID but cannot reuse its previous target as a new detection. */
    for(unsigned i=0;i<100;i++)tick();
    CHECK(commits>=old_commits);cap_runtime_target(0,now,&t);CHECK(t.frame_id==3&&!(t.flags&1));
    scene(4,60);finish();cap_runtime_target(0,now,&t);CHECK(t.flags&1);
    now+=250001;cap_runtime_target(0,now,&t);CHECK(!(t.flags&1)&&t.age_us>250000);
    setup();scene(10,60);finish();scene(11,60);tick();tick();
    regs[0xf8/4]++;regs[0xf0/4]=1; /* Error arrives after snapshot acquisition. */
    cap_runtime_target(0,now,&t);CHECK((t.flags&3)==2);
    regs[0xf0/4]=0; /* Even after input recovers, old snapshot epoch stays rejected. */
    finish();cap_runtime_target(0,now,&t);CHECK(!(t.flags&1)&&!regs[0x118/4]);
    scene(12,60);finish();scene(13,60);finish();cap_runtime_target(0,now,&t);CHECK(t.flags&1);
    scene(14,-1);finish();cap_runtime_target(0,now,&t);CHECK(!(t.flags&1));
    setup();regs[1]=0x10000;CHECK(!cap_runtime_init(0));cap_runtime_target(0,now,&t);CHECK(!(t.flags&1));
    printf("PASS CAP_RUNTIME checks=%u reads=%u commits=%u coherent-mask/error-epoch/loss/stale/version\n",checks,reads,commits);
    return 0;
}
