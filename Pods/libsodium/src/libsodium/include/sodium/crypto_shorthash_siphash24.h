#ifndef crypto_shorthash_siphash24_H
#define crypto_shorthash_siphash24_H

#include <stddef.h>
#include "export.h"

#ifdef __cplusplus
# if __GNUC__
#  pragma GCC diagnostic ignored "-Wlong-long"
# endif
extern "C" {
#endif

#define crypto_shorthash_siphash24_BYTES 8U
SODIUM_EXPORT
size_t crypto_shorthash_siphash24_bytes(void);

#define crypto_shorthash_siphash24_KEYBYTES 16U
SODIUM_EXPORT
size_t crypto_shorthash_siphash24_keybytes(void);

SODIUM_EXPORT
int crypto_shorthash_siphash24(unsigned char *out, const unsigned char *in,
                               unsigned long long inlen, const unsigned char *k);

#ifdef __cplusplus
}
#endif

#endif
