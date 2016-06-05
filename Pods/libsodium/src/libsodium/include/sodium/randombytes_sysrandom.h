
#ifndef randombytes_sysrandom_H
#define randombytes_sysrandom_H

/*
 * THREAD SAFETY: randombytes_sysrandom() functions are thread-safe,
 * provided that you called sodium_init() once before using any
 * other libsodium function.
 */

#include <stddef.h>
#include <stdint.h>

#include "export.h"

#ifdef __cplusplus
extern "C" {
#endif

SODIUM_EXPORT
extern struct randombytes_implementation randombytes_sysrandom_implementation;

SODIUM_EXPORT
const char *randombytes_sysrandom_implementation_name(void);

SODIUM_EXPORT
uint32_t    randombytes_sysrandom(void);

SODIUM_EXPORT
void        randombytes_sysrandom_stir(void);

SODIUM_EXPORT
uint32_t    randombytes_sysrandom_uniform(const uint32_t upper_bound);

SODIUM_EXPORT
void        randombytes_sysrandom_buf(void * const buf, const size_t size);

SODIUM_EXPORT
int         randombytes_sysrandom_close(void);

#ifdef __cplusplus
}
#endif

#endif
