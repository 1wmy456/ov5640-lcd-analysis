#include <stdint.h>
#include "xil_types.h"
void Xil_Out32(UINTPTR address,uint32_t value);
uint32_t Xil_In32(UINTPTR address);
#define dmb() ((void)0)
