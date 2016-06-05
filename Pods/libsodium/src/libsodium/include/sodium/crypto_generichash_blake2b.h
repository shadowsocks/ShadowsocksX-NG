#ifndef crypto_generichash_blake2b_H
#define crypto_generichash_blake2b_H

#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>

#include "export.h"

#if defined(_MSC_VER)
# define CRYPTO_ALIGN(x) __declspec(align(x))
#else
# define CRYPTO_ALIGN(x) __attribute__((aligned(x)))
#endif

#ifdef __cplusplus
# if __GNUC__
#  pragma GCC diagnostic ignored "-Wlong-long"
# endif
extern "C" {
#endif

#pragma pack(push, 1)
typedef CRYPTO_ALIGN(64) struct crypto_generichash_blake2b_state {
    uint64_t h[8];
    uint64_t t[2];
    uint64_t f[2];
    uint8_t  buf[2 * 128];
    size_t   buflen;
    uint8_t  last_node;
} crypto_generichash_blake2b_state;
#pragma pack(pop)

#define crypto_generichash_blake2b_BYTES_MIN     16U
SODIUM_EXPORT
size_t crypto_generichash_blake2b_bytes_min(void);

#define crypto_generichash_blake2b_BYTES_MAX     64U
SODIUM_EXPORT
size_t crypto_generichash_blake2b_bytes_max(void);

#define crypto_generichash_blake2b_BYTES         32U
SODIUM_EXPORT
size_t crypto_generichash_blake2b_bytes(void);

#define crypto_generichash_blake2b_KEYBYTES_MIN  16U
SODIUM_EXPORT
size_t crypto_generichash_blake2b_keybytes_min(void);

#define crypto_generichash_blake2b_KEYBYTES_MAX  64U
SODIUM_EXPORT
size_t crypto_generichash_blake2b_keybytes_max(void);

#define crypto_generichash_blake2b_KEYBYTES      32U
SODIUM_EXPORT
size_t crypto_generichash_blake2b_keybytes(void);

#define crypto_generichash_blake2b_SALTBYTES     16U
SODIUM_EXPORT
size_t crypto_generichash_blake2b_saltbytes(void);

#define crypto_generichash_blake2b_PERSONALBYTES 16U
SODIUM_EXPORT
size_t crypto_generichash_blake2b_personalbytes(void);

SODIUM_EXPORT
int crypto_generichash_blake2b(unsigned char *out, size_t outlen,
                               const unsigned char *in,
                               unsigned long long inlen,
                               const unsigned char *key, size_t keylen);

SODIUM_EXPORT
int crypto_generichash_blake2b_salt_personal(unsigned char *out, size_t outlen,
                                             const unsigned char *in,
                                             unsigned long long inlen,
                                             const unsigned char *key,
                                             size_t keylen,
                                             const unsigned char *salt,
                                             const unsigned char *personal);

SODIUM_EXPORT
int crypto_generichash_blake2b_init(crypto_generichash_blake2b_state *state,
                                    const unsigned char *key,
                                    const size_t keylen, const size_t outlen);

SODIUM_EXPORT
int crypto_generichash_blake2b_init_salt_personal(crypto_generichash_blake2b_state *state,
                                                  const unsigned char *key,
                                                  const size_t keylen, const size_t outlen,
                                                  const unsigned char *salt,
                                                  const unsigned char *personal);

SODIUM_EXPORT
int crypto_generichash_blake2b_update(crypto_generichash_blake2b_state *state,
                                      const unsigned char *in,
                                      unsigned long long inlen);

SODIUM_EXPORT
int crypto_generichash_blake2b_final(crypto_generichash_blake2b_state *state,
                                     unsigned char *out,
                                     const size_t outlen);

#ifdef __cplusplus
}
#endif

#endif
