
#include <string.h>

#include "crypto_sign_ed25519.h"

size_t
crypto_sign_ed25519_bytes(void) {
    return crypto_sign_ed25519_BYTES;
}

size_t
crypto_sign_ed25519_seedbytes(void) {
    return crypto_sign_ed25519_SEEDBYTES;
}

size_t
crypto_sign_ed25519_publickeybytes(void) {
    return crypto_sign_ed25519_PUBLICKEYBYTES;
}

size_t
crypto_sign_ed25519_secretkeybytes(void) {
    return crypto_sign_ed25519_SECRETKEYBYTES;
}

int
crypto_sign_ed25519_sk_to_seed(unsigned char *seed, const unsigned char *sk)
{
    memmove(seed, sk, crypto_sign_ed25519_SEEDBYTES);
    return 0;
}

int
crypto_sign_ed25519_sk_to_pk(unsigned char *pk, const unsigned char *sk)
{
    memmove(pk, sk + crypto_sign_ed25519_SEEDBYTES,
            crypto_sign_ed25519_PUBLICKEYBYTES);
    return 0;
}
