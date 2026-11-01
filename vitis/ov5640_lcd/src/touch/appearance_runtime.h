#ifndef APPEARANCE_RUNTIME_H
#define APPEARANCE_RUNTIME_H
#include "../pan_tilt/pan_tilt_driver.h"
int appearance_runtime_init(UINTPTR base,uint64_t now);
void appearance_runtime_service(UINTPTR base,uint64_t now);
int appearance_runtime_active(void);
int appearance_runtime_paused(void);
int appearance_runtime_switched(void);
void appearance_runtime_target(uint64_t now,PtTarget *out);
void appearance_runtime_blue(UINTPTR base);
void appearance_runtime_click(unsigned x,unsigned y,uint64_t now);
void appearance_runtime_status(void);
#endif
