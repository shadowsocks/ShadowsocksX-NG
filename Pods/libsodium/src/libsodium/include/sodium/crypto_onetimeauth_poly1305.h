#ifndef crypto_onetimeauth_poly1305_H
#define crypto_onetimeauth_poly1305_H

#include <stddef.h>
#include "export.h"

#ifdef __cplusplus
# if __GNUC__
#  pragma GCC diagnostic ignored "-Wlong-long"
# endif
extern "C" {
#endif

#include <sys/types.h>

#include <stdint.h>
#include <stdio.h>

typedef struct crypto_onetimeauth_poly1305_state {
    unsigned long long aligner;
    unsigned char      opaque[136];
} crypto_onetimeauth_poly1305_state;

typedef struct crypto_onetimeauth_poly1305_implementation {
    const char *(*implementation_name)(void);
    int         (*onetimeauth)(unsigned char *out,
                               const unsigned char *in,
                               unsigned long long inlen,
                               const unsigned char *k);
    int         (*onetimeauth_verify)(const unsigned char *h,
                                      const unsigned char *in,
                                      unsigned long long inlen,
                                      const unsigned char *k);
    int         (*onetimeauth_init)(crypto_onetimeauth_poly1305_state *state,
                                    const unsigned char *key);
    int         (*onetimeauth_update)(crypto_onetimeauth_poly1305_state *state,
                                      const unsigned char *in,
                                      unsigned long long inlen);
    int         (*onetimeauth_final)(crypto_onetimeauth_poly1305_state *state,
                                     unsigned char *out);
} crypto_onetimeauth_poly1305_implementation;

#define crypto_onetimeauth_poly1305_BYTES 16U
SODIUM_EXPORT
size_t crypto_onetimeauth_poly1305_bytes(void);

#define crypto_onetimeauth_poly1305_KEYBYTES 32U
SODIUM_EXPORT
size_t crypto_onetimeauth_poly1305_keybytes(void);

SODIUM_EXPORT
const char *crypto_onetimeauth_poly1305_implementation_name(void);

SODIUM_EXPORT
int crypto_onetimeauth_poly1305_set_implementation(crypto_onetimeauth_poly1305_implementation *impl);

crypto_onetimeauth_poly1305_implementation *
crypto_onetimeauth_pick_best_implementation(void);

SODIUM_EXPORT
int crypto_onetimeauth_poly1305(unsigned char *out,
                                const unsigned char *in,
                                unsigned long long inlen,
                                const unsigned char *k);

SODIUM_EXPORT
int crypto_onetimeauth_poly1305_verify(const unsigned char *h,
                                       const unsigned char *in,
                                       unsigned long long inlen,
                                       const unsigned char *k);

SODIUM_EXPORT
int crypto_onetimeauth_poly1305_init(crypto_onetimeauth_poly1305_state *state,
                                     const unsigned char *key);

SODIUM_EXPORT
int crypto_onetimeauth_poly1305_update(crypto_onetimeauth_poly1305_state *state,
                                       const unsigned char *in,
                                       unsigned long long inlen);

SODIUM_EXPORT
int crypto_onetimeauth_poly1305_final(crypto_onetimeauth_poly1305_state *state,
                                      unsigned char *out);

#ifdef __cplusplus
}
#endif

#endif
