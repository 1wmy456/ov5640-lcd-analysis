#ifndef CAP_RUNTIME_H
#define CAP_RUNTIME_H
#include "pan_tilt_driver.h"
#include "cap_components.h"
int cap_runtime_init(UINTPTR base);
void cap_runtime_service(UINTPTR base,uint64_t now);
void cap_runtime_target(UINTPTR base,uint64_t now,PtTarget *out);
const CapResult *cap_runtime_result(void);
uint32_t cap_runtime_processing_us(void);
#endif
