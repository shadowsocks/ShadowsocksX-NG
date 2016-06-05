
#include <string.h>

#include "api.h"
#include "crypto_hash_sha512.h"
#include "crypto_scalarmult_curve25519.h"
#include "randombytes.h"
#include "utils.h"
#include "fe.h"
#include "ge.h"

int crypto_sign_seed_keypair(unsigned char *pk, unsigned char *sk,
                             const unsigned char *seed)
{
    ge_p3 A;

    crypto_hash_sha512(sk,seed,32);
    sk[0] &= 248;
    sk[31] &= 63;
    sk[31] |= 64;

    ge_scalarmult_base(&A,sk);
    ge_p3_tobytes(pk,&A);

    memmove(sk, seed, 32);
    memmove(sk + 32, pk, 32);
    return 0;
}

int crypto_sign_keypair(unsigned char *pk, unsigned char *sk)
{
    unsigned char seed[32];
    int           ret;

    randombytes_buf(seed, sizeof seed);
    ret = crypto_sign_seed_keypair(pk, sk, seed);
    sodium_memzero(seed, sizeof seed);

    return ret;
}

int crypto_sign_ed25519_pk_to_curve25519(unsigned char *curve25519_pk,
                                         const unsigned char *ed25519_pk)
{
    ge_p3 A;
    fe    x;
    fe    one_minus_y;

    if (ge_frombytes_negate_vartime(&A, ed25519_pk) != 0) {
        return -1;
    }
    fe_1(one_minus_y);
    fe_sub(one_minus_y, one_minus_y, A.Y);
    fe_invert(one_minus_y, one_minus_y);
    fe_1(x);
    fe_add(x, x, A.Y);
    fe_mul(x, x, one_minus_y);
    fe_tobytes(curve25519_pk, x);

    return 0;
}

int crypto_sign_ed25519_sk_to_curve25519(unsigned char *curve25519_sk,
                                         const unsigned char *ed25519_sk)
{
    unsigned char h[crypto_hash_sha512_BYTES];

    crypto_hash_sha512(h, ed25519_sk,
                       crypto_sign_ed25519_SECRETKEYBYTES -
                       crypto_sign_ed25519_PUBLICKEYBYTES);
    h[0] &= 248;
    h[31] &= 127;
    h[31] |= 64;
    memcpy(curve25519_sk, h, crypto_scalarmult_curve25519_BYTES);
    sodium_memzero(h, sizeof h);

    return 0;
}
