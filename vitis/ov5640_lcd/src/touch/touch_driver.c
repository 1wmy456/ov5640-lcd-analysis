#include "touch_driver.h"
#include "xparameters.h"
#include "xgpio.h"
#include "sleep.h"
#include <stdio.h>
#include <string.h>
#ifdef XPAR_TOUCH_GPIO_BASEADDR
static XGpio io;
static unsigned tri=15,latch,addr,enabled;
static TouchMap map;
static TouchEvents events;
static uint64_t last_poll,last_print;
/* Bits SCL/SDA/RST/INT. I2C lines only drive zero; high means release. */
static void pin(unsigned bit,int value){
 unsigned mask=1u<<bit;
 if(value)tri|=mask;else {latch&=~mask;XGpio_DiscreteWrite(&io,1,latch);tri&=~mask;}
 XGpio_SetDataDirection(&io,1,tri);usleep(3);
}
static int rd(unsigned bit){return (XGpio_DiscreteRead(&io,1)>>bit)&1;}
static void control_pin(unsigned bit,int value){
 unsigned mask=1u<<bit;
 latch=value?latch|mask:latch&~mask;
 XGpio_DiscreteWrite(&io,1,latch);tri&=~mask;XGpio_SetDataDirection(&io,1,tri);usleep(3);
}
static int scl(void){unsigned t;pin(0,1);for(t=0;t<100;t++){if(rd(0))return 1;usleep(2);}return 0;}
static void stop(void){pin(1,0);scl();pin(1,1);}
static int start(void){pin(1,1);if(!scl()||!rd(1)){stop();return 0;}pin(1,0);pin(0,0);return 1;}
static int put(unsigned b){int i,ack;for(i=7;i>=0;i--){pin(1,(b>>i)&1);if(!scl())return 0;pin(0,0);}pin(1,1);if(!scl())return 0;ack=!rd(1);pin(0,0);return ack;}
static int get(unsigned char *b,int ack){unsigned i,v=0;pin(1,1);for(i=0;i<8;i++){if(!scl())return 0;v=(v<<1)|rd(1);pin(0,0);}pin(1,!ack);if(!scl())return 0;pin(0,0);pin(1,1);*b=v;return 1;}
static int readreg(unsigned reg,unsigned char *p,unsigned n){unsigned i;int ok=start()&&put(addr<<1)&&put(reg>>8)&&put(reg&255)&&start()&&put((addr<<1)|1);for(i=0;ok&&i<n;i++)ok=get(p+i,i+1<n);stop();return ok;}
static int clear_status(void){int ok=start()&&put(addr<<1)&&put(0x81)&&put(0x4e)&&put(0);stop();return ok;}
int touch_init(unsigned lcd_id,unsigned width,unsigned height){
 unsigned char id[5]={0},cfg[5];unsigned i;
 memset(&events,0,sizeof(events));enabled=0;
 if(lcd_id!=0x4384||width!=800||height!=480){printf("TOUCH disabled: unsupported LCD %04x %ux%u\r\n",lcd_id,width,height);return 0;}
 if(XGpio_Initialize(&io,XPAR_TOUCH_GPIO_DEVICE_ID)!=XST_SUCCESS)return 0;
 XGpio_SetDataDirection(&io,1,15);XGpio_SetDataDirection(&io,2,0);XGpio_DiscreteWrite(&io,2,0);
 /* Reference reset selects 7-bit 0x14 with INT high; no controller flash writes. */
 control_pin(2,0);control_pin(3,1);usleep(12000);control_pin(2,1);usleep(12000);control_pin(3,0);usleep(50000);pin(3,1);usleep(50000);
 printf("TOUCH BUS idle=%lx dir=%lx\r\n",(unsigned long)XGpio_DiscreteRead(&io,1),(unsigned long)XGpio_GetDataDirection(&io,1));
 for(i=0;i<2;i++){
  int ok;addr=i?0x5d:0x14;memset(id,0,sizeof(id));ok=readreg(0x8140,id,4);
  printf("TOUCH PROBE addr=%02x ack=%d id_hex=%02x,%02x,%02x,%02x bus=%lx\r\n",addr,ok,id[0],id[1],id[2],id[3],(unsigned long)XGpio_DiscreteRead(&io,1));
  if(ok&&(!memcmp(id,"9147",4)||!memcmp(id,"1158",4)))break;
 }
 if(i==2){printf("TOUCH probe FAILED: supported Goodix ID not confirmed, no events/selection enabled\r\n");return 0;}
 /* GT1158=GT1x config 0x8050; GT9147=GT9x config 0x8047.
  * Protocol cross-check: Linux v6.6 goodix.c chip ID table and goodix.h.
  * https://github.com/torvalds/linux/tree/v6.6/drivers/input/touchscreen */
 if(!readreg(!memcmp(id,"1158",4)?0x8050:0x8047,cfg,5))return 0;
 map=(TouchMap){cfg[1]|(cfg[2]<<8),cfg[3]|(cfg[4]<<8),width,height,0,0,0};
 if(map.raw_width<2||map.raw_height<2||map.raw_width>4096||map.raw_height>4096)return 0;
 enabled=1;printf("TOUCH ID=%s addr=%02x GPIO=%08lx raw=%ux%u mapped=%ux%u swap=0 invert=0,0 STAGE_A PWM unchanged\r\n",id,addr,(unsigned long)XPAR_TOUCH_GPIO_BASEADDR,map.raw_width,map.raw_height,width,height);return 1;
}
void touch_service(uint64_t now){
 unsigned char status=0,p[8];unsigned count=0,x=events.x,y=events.y;int ok,event;
 if(!enabled||now-last_poll<10000)return;
 last_poll=now;
 ok=readreg(0x814e,&status,1)&&(status&0x80);
 if(ok){count=status&15;if(count==1){ok=readreg(0x814f,p,8)&&touch_map(&map,p[1]|(p[2]<<8),p[3]|(p[4]<<8),&x,&y);}else if(count>5)ok=0;
  if(!clear_status())ok=0;
 }
 event=touch_event(&events,ok,count,x,y,now);
 if(event==TOUCH_DOWN||event==TOUCH_MOVE)XGpio_DiscreteWrite(&io,2,0x80000000u|(events.y<<10)|events.x);
 if(event==TOUCH_DOWN||event==TOUCH_UP||event==TOUCH_CANCEL||(event==TOUCH_MOVE&&now-last_print>200000)){
  last_print=now;printf("TOUCH %s x=%u y=%u time_us=%llu\r\n",event==TOUCH_DOWN?"DOWN":event==TOUCH_UP?"UP":event==TOUCH_CANCEL?"CANCEL":"MOVE",events.x,events.y,(unsigned long long)now);
 }
}
#else
int touch_init(unsigned id,unsigned w,unsigned h){(void)id;(void)w;(void)h;return 0;}
void touch_service(uint64_t now){(void)now;}
#endif
