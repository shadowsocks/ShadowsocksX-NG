#ifndef crypto_sign_ed25519_H
#define crypto_sign_ed25519_H

#include <stddef.h>
#include "export.h"

#ifdef __cplusplus
# if __GNUC__
#  pragma GCC diagnostic ignored "-Wlong-long"
# endif
extern "C" {
#endif

#define crypto_sign_ed25519_BYTES 64U
SODIUM_EXPORT
size_t crypto_sign_ed25519_bytes(void);

#define crypto_sign_ed25519_SEEDBYTES 32U
SODIUM_EXPORT
size_t crypto_sign_ed25519_seedbytes(void);

#define crypto_sign_ed25519_PUBLICKEYBYTES 32U
SODIUM_EXPORT
size_t crypto_sign_ed25519_publickeybytes(void);

#define crypto_sign_ed25519_SECRETKEYBYTES (32U + 32U)
SODIUM_EXPORT
size_t crypto_sign_ed25519_secretkeybytes(void);

SODIUM_EXPORT
int crypto_sign_ed25519(unsigned char *sm, unsigned long long *smlen_p,
                        const unsigned char *m, unsigned long long mlen,
                        const unsigned char *sk);

SODIUM_EXPORT
int crypto_sign_ed25519_open(unsigned char *m, unsigned long long *mlen_p,
                             const unsigned char *sm, unsigned long long smlen,
                             const unsigned char *pk);

SODIUM_EXPORT
int crypto_sign_ed25519_detached(unsigned char *sig,
                                 unsigned long long *siglen_p,
                                 const unsigned char *m,
                                 unsigned long long mlen,
                                 const unsigned char *sk);

SODIUM_EXPORT
int crypto_sign_ed25519_verify_detached(const unsigned char *sig,
                                        const unsigned char *m,
                                        unsigned long long mlen,
                                        const unsigned char *pk);

SODIUM_EXPORT
int crypto_sign_ed25519_keypair(unsigned char *pk, unsigned char *sk);

SODIUM_EXPORT
int crypto_sign_ed25519_seed_keypair(unsigned char *pk, unsigned char *sk,
                                     const unsigned char *seed);

SODIUM_EXPORT
int crypto_sign_ed25519_pk_to_curve25519(unsigned char *curve25519_pk,
                                         const unsigned char *ed25519_pk);

SODIUM_EXPORT
int crypto_sign_ed25519_sk_to_curve25519(unsigned char *curve25519_sk,
                                         const unsigned char *ed25519_sk);

SODIUM_EXPORT
int crypto_sign_ed25519_sk_to_seed(unsigned char *seed,
                                   const unsigned char *sk);

SODIUM_EXPORT
int crypto_sign_ed25519_sk_to_pk(unsigned char *pk, const unsigned char *sk);

#ifdef __cplusplus
}
#endif

#endif
