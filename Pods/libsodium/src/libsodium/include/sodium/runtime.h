
#ifndef sodium_runtime_H
#define sodium_runtime_H

#include "export.h"

#ifdef __cplusplus
extern "C" {
#endif

SODIUM_EXPORT
int sodium_runtime_get_cpu_features(void);

SODIUM_EXPORT
int sodium_runtime_has_neon(void);

SODIUM_EXPORT
int sodium_runtime_has_sse2(void);

SODIUM_EXPORT
int sodium_runtime_has_sse3(void);

#ifdef __cplusplus
}
#endif

#endif
