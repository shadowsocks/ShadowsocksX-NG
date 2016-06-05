#ifndef crypto_stream_aes128ctr_H
#define crypto_stream_aes128ctr_H

/*
 *  WARNING: This is just a stream cipher. It is NOT authenticated encryption.
 *  While it provides some protection against eavesdropping, it does NOT
 *  provide any security against active attacks.
 *  Unless you know what you're doing, what you are looking for is probably
 *  the crypto_box functions.
 */

#include <stddef.h>
#include "export.h"

#ifdef __cplusplus
# if __GNUC__
#  pragma GCC diagnostic ignored "-Wlong-long"
# endif
extern "C" {
#endif

#define crypto_stream_aes128ctr_KEYBYTES 16U
SODIUM_EXPORT
size_t crypto_stream_aes128ctr_keybytes(void);

#define crypto_stream_aes128ctr_NONCEBYTES 16U
SODIUM_EXPORT
size_t crypto_stream_aes128ctr_noncebytes(void);

#define crypto_stream_aes128ctr_BEFORENMBYTES 1408U
SODIUM_EXPORT
size_t crypto_stream_aes128ctr_beforenmbytes(void);

SODIUM_EXPORT
int crypto_stream_aes128ctr(unsigned char *out, unsigned long long outlen,
                            const unsigned char *n, const unsigned char *k);

SODIUM_EXPORT
int crypto_stream_aes128ctr_xor(unsigned char *out, const unsigned char *in,
                                unsigned long long inlen, const unsigned char *n,
                                const unsigned char *k);

SODIUM_EXPORT
int crypto_stream_aes128ctr_beforenm(unsigned char *c, const unsigned char *k);

SODIUM_EXPORT
int crypto_stream_aes128ctr_afternm(unsigned char *out, unsigned long long len,
                                    const unsigned char *nonce, const unsigned char *c);

SODIUM_EXPORT
int crypto_stream_aes128ctr_xor_afternm(unsigned char *out, const unsigned char *in,
                                        unsigned long long len,
                                        const unsigned char *nonce,
                                        const unsigned char *c);

#ifdef __cplusplus
}
#endif

#endif
