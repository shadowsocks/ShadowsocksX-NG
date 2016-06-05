#ifndef crypto_secretbox_xsalsa20poly1305_H
#define crypto_secretbox_xsalsa20poly1305_H

#include <stddef.h>
#include "export.h"

#ifdef __cplusplus
# if __GNUC__
#  pragma GCC diagnostic ignored "-Wlong-long"
# endif
extern "C" {
#endif

#define crypto_secretbox_xsalsa20poly1305_KEYBYTES 32U
SODIUM_EXPORT
size_t crypto_secretbox_xsalsa20poly1305_keybytes(void);

#define crypto_secretbox_xsalsa20poly1305_NONCEBYTES 24U
SODIUM_EXPORT
size_t crypto_secretbox_xsalsa20poly1305_noncebytes(void);

#define crypto_secretbox_xsalsa20poly1305_ZEROBYTES 32U
SODIUM_EXPORT
size_t crypto_secretbox_xsalsa20poly1305_zerobytes(void);

#define crypto_secretbox_xsalsa20poly1305_BOXZEROBYTES 16U
SODIUM_EXPORT
size_t crypto_secretbox_xsalsa20poly1305_boxzerobytes(void);

#define crypto_secretbox_xsalsa20poly1305_MACBYTES \
    (crypto_secretbox_xsalsa20poly1305_ZEROBYTES - \
     crypto_secretbox_xsalsa20poly1305_BOXZEROBYTES)
SODIUM_EXPORT
size_t crypto_secretbox_xsalsa20poly1305_macbytes(void);

SODIUM_EXPORT
int crypto_secretbox_xsalsa20poly1305(unsigned char *c,
                                      const unsigned char *m,
                                      unsigned long long mlen,
                                      const unsigned char *n,
                                      const unsigned char *k);

SODIUM_EXPORT
int crypto_secretbox_xsalsa20poly1305_open(unsigned char *m,
                                           const unsigned char *c,
                                           unsigned long long clen,
                                           const unsigned char *n,
                                           const unsigned char *k);

#ifdef __cplusplus
}
#endif

#endif
