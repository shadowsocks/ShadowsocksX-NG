#ifndef crypto_aead_chacha20poly1305_H
#define crypto_aead_chacha20poly1305_H

#include <stddef.h>
#include "export.h"

#ifdef __cplusplus
# if __GNUC__
#  pragma GCC diagnostic ignored "-Wlong-long"
# endif
extern "C" {
#endif

#define crypto_aead_chacha20poly1305_KEYBYTES 32U
SODIUM_EXPORT
size_t crypto_aead_chacha20poly1305_keybytes(void);

#define crypto_aead_chacha20poly1305_NSECBYTES 0U
SODIUM_EXPORT
size_t crypto_aead_chacha20poly1305_nsecbytes(void);

#define crypto_aead_chacha20poly1305_NPUBBYTES 8U
SODIUM_EXPORT
size_t crypto_aead_chacha20poly1305_npubbytes(void);

#define crypto_aead_chacha20poly1305_ABYTES 16U
SODIUM_EXPORT
size_t crypto_aead_chacha20poly1305_abytes(void);

SODIUM_EXPORT
int crypto_aead_chacha20poly1305_encrypt(unsigned char *c,
                                         unsigned long long *clen,
                                         const unsigned char *m,
                                         unsigned long long mlen,
                                         const unsigned char *ad,
                                         unsigned long long adlen,
                                         const unsigned char *nsec,
                                         const unsigned char *npub,
                                         const unsigned char *k);

SODIUM_EXPORT
int crypto_aead_chacha20poly1305_decrypt(unsigned char *m,
                                         unsigned long long *mlen,
                                         unsigned char *nsec,
                                         const unsigned char *c,
                                         unsigned long long clen,
                                         const unsigned char *ad,
                                         unsigned long long adlen,
                                         const unsigned char *npub,
                                         const unsigned char *k);
#ifdef __cplusplus
}
#endif

#endif
