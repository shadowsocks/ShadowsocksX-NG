#ifndef crypto_sign_edwards25519sha512batch_H
#define crypto_sign_edwards25519sha512batch_H

/*
 * WARNING: This construction was a prototype, which should not be used
 * any more in new projects.
 * 
 * crypto_sign_edwards25519sha512batch is provided for applications
 * initially built with NaCl, but as recommended by the author of this
 * construction, new applications should use ed25519 instead.
 * 
 * In Sodium, you should use the high-level crypto_sign_*() functions instead.
 */

#include <stddef.h>
#include "export.h"

#ifdef __cplusplus
# if __GNUC__
#  pragma GCC diagnostic ignored "-Wlong-long"
# endif
extern "C" {
#endif

#define crypto_sign_edwards25519sha512batch_BYTES 64U
SODIUM_EXPORT
size_t crypto_sign_edwards25519sha512batch_bytes(void);

#define crypto_sign_edwards25519sha512batch_PUBLICKEYBYTES 32U
SODIUM_EXPORT
size_t crypto_sign_edwards25519sha512batch_publickeybytes(void);

#define crypto_sign_edwards25519sha512batch_SECRETKEYBYTES (32U + 32U)
SODIUM_EXPORT
size_t crypto_sign_edwards25519sha512batch_secretkeybytes(void);

SODIUM_EXPORT
int crypto_sign_edwards25519sha512batch(unsigned char *sm,
                                        unsigned long long *smlen_p,
                                        const unsigned char *m,
                                        unsigned long long mlen,
                                        const unsigned char *sk);

SODIUM_EXPORT
int crypto_sign_edwards25519sha512batch_open(unsigned char *m,
                                             unsigned long long *mlen_p,
                                             const unsigned char *sm,
                                             unsigned long long smlen,
                                             const unsigned char *pk);

SODIUM_EXPORT
int crypto_sign_edwards25519sha512batch_keypair(unsigned char *pk,
                                                unsigned char *sk);

#ifdef __cplusplus
}
#endif

#endif
