#include "pan_tilt_app.h"
#include "pan_tilt_driver.h"
#include "cap_runtime.h"
#include "../touch/touch_driver.h"
extern unsigned int lcd_id;
#include "xparameters.h"
#include "xtime_l.h"
#include "xuartps.h"
#include "xuartps_hw.h"
#include "xil_io.h"
#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>
#include <string.h>
#include <math.h>
#ifndef XPAR_PAN_TILT_CTRL_0_S_AXI_BASEADDR
#error "Fresh BSP with pan_tilt_ctrl driver/address macros is required"
#endif
static const UINTPTR pt_base=XPAR_PAN_TILT_CTRL_0_S_AXI_BASEADDR;
static PtControl control;
static PtTarget target;
static int command_result;
static char tx[4096],line[128];static unsigned tx_head,tx_tail,line_used,dropped;static int line_overflow;
static void log_text(const char *fmt,...){
    char text[512];int i,n;va_list ap;va_start(ap,fmt);n=vsnprintf(text,sizeof(text),fmt,ap);va_end(ap);
    if(n<0)return;
    if(n>511)n=511;
    for(i=0;i<n;i++){unsigned next=(tx_head+1)%sizeof(tx);if(next==tx_tail){dropped++;break;}tx[tx_head]=text[i];tx_head=next;}
}
static uint64_t now_us(void){XTime t;XTime_GetTime(&t);return (t/COUNTS_PER_SECOND)*1000000ull+(t%COUNTS_PER_SECOND)*1000000ull/COUNTS_PER_SECOND;}
static int axis_of(const char *s){return !strcmp(s,"yaw")?0:(!strcmp(s,"pitch")?1:-1);}
static int number(const char *s,double *v){char *end;*v=strtod(s,&end);return *s&&!*end&&isfinite(*v);}
static const char *controller_name(void){return control.controller==PT_CONTROL_PID?"pid":(control.controller==PT_CONTROL_PD?"pd":"p");}
static void show_pid(void){
    log_text("PID controller=%s kp_milli=%d,%d ki_milli=%d,%d kd_milli=%d,%d tau_ms=%d,%d imax_milli=%d,%d dlimit=%d,%d\r\n",
        controller_name(),(int)(control.gain[0]*1000),(int)(control.gain[1]*1000),
        (int)(control.ki[0]*1000),(int)(control.ki[1]*1000),(int)(control.kd[0]*1000),(int)(control.kd[1]*1000),
        (int)(control.derivative_tau[0]*1000),(int)(control.derivative_tau[1]*1000),
        (int)(control.integral_limit[0]*1000),(int)(control.integral_limit[1]*1000),
        (int)control.derivative_limit[0],(int)control.derivative_limit[1]);
    log_text("PID_TERMS p_milli=%d,%d i_milli=%d,%d d_milli=%d,%d requested_milli=%d,%d us/s; D filtered px/s=%d,%d\r\n",
        (int)(control.p_term[0]*1000),(int)(control.p_term[1]*1000),
        (int)(control.integral[0]*1000),(int)(control.integral[1]*1000),
        (int)(control.d_term[0]*1000),(int)(control.d_term[1]*1000),
        (int)(control.requested_velocity[0]*1000),(int)(control.requested_velocity[1]*1000),
        (int)control.derivative[0],(int)control.derivative[1]);
}
static void show_status(void){
    unsigned yaw=pt_reg_read(pt_base,PT_YAW_ACTIVE),pitch=pt_reg_read(pt_base,PT_PITCH_ACTIVE);
    unsigned limit=(yaw<=control.minimum[0]||yaw>=control.maximum[0]?1:0)|
                   (pitch<=control.minimum[1]||pitch>=control.maximum[1]?2:0);
    log_text("mode=%s frame=%lu valid=%u err=%u age=%lu bbox=%u,%u,%u,%u ex=%d ey=%d yaw=%lu pitch=%lu en=%d hold=%d limit=%u det=%s drop=%u smooth=%d db=%d/%d vel_milli=%d,%d active=%d,%d ctrl=%s\r\n",
      control.automatic?"auto":"manual",(unsigned long)target.frame_id,target.flags&1,(target.flags>>1)&1,
      (unsigned long)target.age_us,target.xmin,target.xmax,target.ymin,target.ymax,control.ex,control.ey,
      (unsigned long)yaw,(unsigned long)pitch,control.enabled,control.hold_reason,limit,
      cap_reason_name(cap_runtime_result()->reason),dropped,control.smooth_enabled,control.deadband,control.deadband_outer,
      (int)(control.velocity[0]*1000),(int)(control.velocity[1]*1000),control.motion_active[0],control.motion_active[1],controller_name());
}
static void command(char *s){
    char *w[5],*p;int n=0,a;double v,lo,hi;command_result=0;
    for(p=strtok(s," \t");p&&n<5;p=strtok(NULL," \t"))w[n++]=p;
    if(!n)return;
    if(n==1&&!strcmp(w[0],"pid")){show_pid();return;}
    if(n==2&&!strcmp(w[0],"controller")){
        int mode=!strcmp(w[1],"p")?PT_CONTROL_P:(!strcmp(w[1],"pd")?PT_CONTROL_PD:(!strcmp(w[1],"pid")?PT_CONTROL_PID:-1));
        if(!pt_control_controller(&control,mode))goto bad;
        log_text("controller=%s; pulse/enables retained, velocity/I/D reset; new frame baseline required\r\n",controller_name());
        show_pid();return;
    }
    if(n==1&&!strcmp(w[0],"motion")){
        log_text("MOTION smooth=%d deadband=%d/%d accel=%d,%d decel=%d,%d us/s2; gain_milli=%d,%d rate=%d,%d us/s\r\n",
            control.smooth_enabled,control.deadband,control.deadband_outer,
            (int)control.acceleration[0],(int)control.acceleration[1],(int)control.deceleration[0],(int)control.deceleration[1],
            (int)(control.gain[0]*1000),(int)(control.gain[1]*1000),(int)control.rate[0],(int)control.rate[1]);return;
    }
    if(n==2&&!strcmp(w[0],"smooth")&&(!strcmp(w[1],"on")||!strcmp(w[1],"off"))){
        pt_control_smooth(&control,!strcmp(w[1],"on"));
        log_text("smooth=%d controller=%s; pulse retained, motion state reset\r\n",control.smooth_enabled,controller_name());return;
    }
    if(n==1&&!strcmp(w[0],"vision")){
        const CapResult *r=cap_runtime_result();
        log_text("VISION mask_frame=%lu src_error=%lu age=%lu errors=%lu objects=%u candidates=%u locked=%u reason=%s process_us=%lu largest=%u/%ux%u cells\r\n",
            (unsigned long)pt_reg_read(pt_base,0xec),(unsigned long)pt_reg_read(pt_base,0xf0),
            (unsigned long)pt_reg_read(pt_base,0xf4),(unsigned long)pt_reg_read(pt_base,0xf8),
            r->components,r->candidates,r->locked,cap_reason_name(r->reason),(unsigned long)cap_runtime_processing_us(),
            r->max_area,r->max_width,r->max_height);return;
    }
    if(n==1&&!strcmp(w[0],"pwm")){
        log_text("PWM_NET clk=%lu flags=%lx yaw high=%lu period=%lu rises=%lu pitch high=%lu period=%lu rises=%lu ticks; connector voltage unmeasured\r\n",
            (unsigned long)pt_reg_read(pt_base,PT_CLOCK_HZ),(unsigned long)pt_reg_read(pt_base,PT_WAVE_STATUS),
            (unsigned long)pt_reg_read(pt_base,PT_YAW_HIGH_TICKS),(unsigned long)pt_reg_read(pt_base,PT_YAW_PERIOD_TICKS),
            (unsigned long)pt_reg_read(pt_base,PT_YAW_RISES),(unsigned long)pt_reg_read(pt_base,PT_PITCH_HIGH_TICKS),
            (unsigned long)pt_reg_read(pt_base,PT_PITCH_PERIOD_TICKS),(unsigned long)pt_reg_read(pt_base,PT_PITCH_RISES));return;
    }
    if(!strcmp(w[0],"status")){show_status();return;}
    if(!strcmp(w[0],"manual")||!strcmp(w[0],"hold")){pt_control_manual(&control);log_text("manual/hold: PWM enable and position retained\r\n");return;}
    if(!strcmp(w[0],"disable")){control.enabled=0;pt_control_manual(&control);pt_reg_write(pt_base,PT_ENABLE,0);log_text("PWM disabled; stored position retained\r\n");return;}
    if(n==2&&!strcmp(w[0],"enable")){
        int mask=!strcmp(w[1],"both")?3:(!strcmp(w[1],"yaw")?1:(!strcmp(w[1],"pitch")?2:0));
        if(!mask)goto bad;
        control.enabled|=mask;pt_reg_write(pt_base,PT_ENABLE,control.enabled);log_text("enable=%d; starts at next period boundary\r\n",control.enabled);return;
    }
    if(!strcmp(w[0],"auto")){
        if(pt_reg_read(pt_base,PT_COMMIT)){command_result=2;log_text("auto refused: pending PWM commit; retry after 20ms\r\n");return;}
        control.position[0]=pt_reg_read(pt_base,PT_YAW_ACTIVE);control.position[1]=pt_reg_read(pt_base,PT_PITCH_ACTIVE);
        if(pt_control_auto(&control))log_text("auto on: K us/(pixel*s), rate us/s; first frame establishes baseline\r\n");
        else {command_result=2;log_text("auto refused: dimensions/camera, both enables and verify yaw/pitch required\r\n");}return;
    }
    if(n==1&&!strcmp(w[0],"center")){
        pt_control_manual(&control);control.position[0]=control.center[0];control.position[1]=control.center[1];pt_driver_commit(pt_base,&control);log_text("center pair committed; enables unchanged\r\n");return;
    }
    if(n==2&&!strcmp(w[0],"verify")&&(a=axis_of(w[1]))>=0){control.verified[a]=1;log_text("axis %s center/limits/direction marked verified by operator\r\n",w[1]);return;}
    if(n==2&&(a=axis_of(w[0]))>=0&&number(w[1],&v)&&v>=500&&v<=2500&&v==(int)v){
        if(!pt_control_set_position(&control,a,(int)v))goto bad;
        pt_driver_commit(pt_base,&control);log_text("%s requested=%d us\r\n",w[0],(int)v);return;
    }
    if(n==3&&!strcmp(w[0],"step")&&(a=axis_of(w[1]))>=0&&number(w[2],&v)&&v>=-100&&v<=100&&v==(int)v){
        int pos=(int)pt_control_pulse(&control,a)+(int)v;
        if(!pt_control_set_position(&control,a,pos))goto bad;
        pt_driver_commit(pt_base,&control);log_text("%s step=%d us requested=%d\r\n",w[1],(int)v,pos);return;
    }
    if(n==3&&(a=axis_of(w[1]))>=0&&number(w[2],&v)){
        if(!strcmp(w[0],"ki")||!strcmp(w[0],"kd")){
            if(!pt_control_pid_gains(&control,a,!strcmp(w[0],"ki")?v:control.ki[a],!strcmp(w[0],"kd")?v:control.kd[a]))goto bad;
            show_pid();return;
        }
        if(!strcmp(w[0],"dtau")||!strcmp(w[0],"dlimit")||!strcmp(w[0],"imax")){
            if(!pt_control_pid_filter(&control,a,!strcmp(w[0],"dtau")?v:control.derivative_tau[a]*1000,
                !strcmp(w[0],"dlimit")?v:control.derivative_limit[a],!strcmp(w[0],"imax")?v:control.integral_limit[a]))goto bad;
            show_pid();return;
        }
        if((!strcmp(w[0],"accel")||!strcmp(w[0],"decel"))&&v>=10&&v<=2000){
            if(!strcmp(w[0],"accel"))control.acceleration[a]=v;else control.deceleration[a]=v;
            log_text("%s %s=%d us/s2\r\n",w[1],w[0],(int)v);return;
        }
        if(!strcmp(w[0],"dir")&&(v==1||v==-1)){control.direction[a]=(int)v;control.verified[a]=0;pt_control_manual(&control);log_text("%s direction=%d; verify again\r\n",w[1],(int)v);return;}
        if((!strcmp(w[0],"gain")||!strcmp(w[0],"kp"))&&v>=0&&v<=2){
            control.gain[a]=v;
            if(control.controller!=PT_CONTROL_P)pt_control_controller(&control,control.controller);
            log_text("%s gain=%d milli-us/(pixel*s)\r\n",w[1],(int)(v*1000));return;
        }
        if(!strcmp(w[0],"rate")&&v>0&&v<=100){control.rate[a]=v;log_text("%s rate=%d milli-us/s\r\n",w[1],(int)(v*1000));return;}
        if(!strcmp(w[0],"center")&&v>=control.minimum[a]&&v<=control.maximum[a]&&v==(int)v){
            pt_control_manual(&control);control.center[a]=(int)v;control.verified[a]=0;pt_reg_write(pt_base,a?PT_PITCH_CENTER:PT_YAW_CENTER,(u32)v);log_text("%s center configured; use center to move\r\n",w[1]);return;}
    }
    if(n==4&&!strcmp(w[0],"limits")&&(a=axis_of(w[1]))>=0&&number(w[2],&lo)&&number(w[3],&hi)&&lo>=500&&hi<=2500&&lo<=hi&&lo==(int)lo&&hi==(int)hi){
        if(!pt_control_limits(&control,a,(int)lo,(int)hi))goto bad;
        pt_driver_limits(pt_base,a,(int)lo,(int)hi);pt_reg_write(pt_base,a?PT_PITCH_CENTER:PT_YAW_CENTER,control.center[a]);pt_driver_commit(pt_base,&control);
        log_text("%s limits=%d..%d us; verify again\r\n",w[1],(int)lo,(int)hi);return;
    }
    if(n==2&&!strcmp(w[0],"deadband")&&number(w[1],&v)&&v>=0&&v<=100&&v==(int)v){
        control.deadband=(int)v;control.deadband_outer=(int)v+7;pt_control_smooth(&control,control.smooth_enabled);
        log_text("deadband=%d/%d px\r\n",control.deadband,control.deadband_outer);return;
    }
    if(n==3&&!strcmp(w[0],"deadband")&&number(w[1],&lo)&&number(w[2],&hi)&&
       lo>=0&&hi>=lo&&hi<=120&&lo==(int)lo&&hi==(int)hi){
        control.deadband=(int)lo;control.deadband_outer=(int)hi;pt_control_smooth(&control,control.smooth_enabled);
        log_text("deadband=%d/%d px\r\n",control.deadband,control.deadband_outer);return;
    }
bad:command_result=1;log_text("invalid command/value; examples: enable yaw | step yaw +5 | dir yaw -1 | limits yaw 1400 1600 | gain yaw 0.1 | center | verify yaw | auto | status\r\n");
}
static void app_state(void){
    pt_reg_write(pt_base,PT_APP_STATUS,0x80000000u|control.automatic|(control.verified[0]<<1)|
        (control.verified[1]<<2)|(control.hold_reason<<8)|(control.dimensions_ok<<16));
}
static void service_mailbox(void){
    u32 request=pt_reg_read(pt_base,PT_COMMAND_REQUEST);unsigned i,j;char message[32];
    if(request==pt_reg_read(pt_base,PT_COMMAND_ACK))return;
    for(i=0;i<8;i++){u32 word=pt_reg_read(pt_base,PT_COMMAND_WORDS+i*4);for(j=0;j<4;j++)message[i*4+j]=(char)(word>>(j*8));}
    message[31]=0;command(message);pt_reg_write(pt_base,PT_APP_COMMAND_RESULT,command_result);
    app_state();pt_reg_write(pt_base,PT_COMMAND_ACK,request);
}
static void service_uart(void){
    unsigned budget=32;
    while(budget--&&XUartPs_IsReceiveData(STDIN_BASEADDRESS)){
        char ch=(char)Xil_In32(STDIN_BASEADDRESS+XUARTPS_FIFO_OFFSET);
        if(ch=='\r'||ch=='\n'){
            if(!line_overflow&&line_used){line[line_used]=0;command(line);}
            else if(line_overflow)log_text("command line too long\r\n");
            line_used=0;line_overflow=0;
        }else if(ch==8||ch==127){if(line_used)line_used--;}
        else if(line_used<sizeof(line)-1)line[line_used++]=ch;else line_overflow=1;
    }
    budget=32;
    while(budget--&&tx_tail!=tx_head&&!XUartPs_IsTransmitFull(STDOUT_BASEADDRESS)){
        Xil_Out32(STDOUT_BASEADDRESS+XUARTPS_FIFO_OFFSET,(unsigned char)tx[tx_tail]);tx_tail=(tx_tail+1)%sizeof(tx);
    }
}
void pan_tilt_run(unsigned width,unsigned height,int camera_ok){
    XUartPs uart;XUartPs_Config *cfg=XUartPs_LookupConfig(XPAR_XUARTPS_0_DEVICE_ID);
    uint64_t last_tick,last_log,now;u32 dimensions=pt_reg_read(pt_base,PT_DIMENSIONS);
    if(cfg){XUartPs_CfgInitialize(&uart,cfg,cfg->BaseAddress);XUartPs_SetBaudRate(&uart,115200);}
    pt_reg_write(pt_base,PT_ENABLE,0);
    pt_control_init(&control,camera_ok&&width==800&&height==480&&dimensions==((480u<<16)|800u));
    if(!cap_runtime_init(pt_base))control.dimensions_ok=0;
    if(pt_reg_read(pt_base,PT_ID)!=0x50544c54)control.dimensions_ok=0;
    pt_driver_commit(pt_base,&control);
    log_text("PAN_TILT ready manual PWM OFF 115200 8N1; range1400..1600 center1500; first step5us\r\n");
    log_text("VISION component/ellipse/lock mask200x120 block4 acquisition2frames; command: vision\r\n");
    log_text("SMOOTH defaults ON deadband15/22 accel200 decel400 us/s2; motion | smooth on/off | accel/decel yaw/pitch <value>\r\n");
    log_text("VISUAL_PID v1 defaults controller=p Ki=0 Kd=0.03 tau100ms; controller p/pd/pid | pid | kp/ki/kd/dtau/imax/dlimit yaw/pitch <value>\r\n");
    if(!control.dimensions_ok)log_text("AUTO DISABLED: camera/display/tracker mismatch display=%ux%u tracker=%ux%u camera_ok=%d\r\n",width,height,dimensions&65535,dimensions>>16,camera_ok);
    last_tick=last_log=now_us();
    touch_init(lcd_id,width,height);
    app_state();
    for(;;){
        service_uart();service_mailbox();now=now_us();
        touch_service(now);
        cap_runtime_service(pt_base,now);
        if(now-last_tick>=20000){last_tick=now;cap_runtime_target(pt_base,now,&target);
            if(pt_control_update(&control,&target,now))pt_driver_commit(pt_base,&control);
            app_state();}
        if(now-last_log>=500000){last_log=now;show_status();}
    }
}
