#include <stdint.h>
typedef uint64_t XTime;
#define COUNTS_PER_SECOND 1000000ull
void XTime_GetTime(XTime *t);
