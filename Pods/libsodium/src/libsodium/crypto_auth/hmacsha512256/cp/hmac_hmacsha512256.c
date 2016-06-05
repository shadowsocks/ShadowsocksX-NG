
#include "api.h"
#include "crypto_auth_hmacsha512256.h"
#include "crypto_auth_hmacsha512.h"
#include "crypto_hash_sha512.h"
#include "utils.h"

#include <sys/types.h>

#include <stdint.h>
#include <string.h>

int
crypto_auth_hmacsha512256_init(crypto_auth_hmacsha512256_state *state,
                               const unsigned char *key,
                               size_t keylen)
{
    return crypto_auth_hmacsha512_init((crypto_auth_hmacsha512_state *) state,
                                       key, keylen);
}

int
crypto_auth_hmacsha512256_update(crypto_auth_hmacsha512256_state *state,
                                 const unsigned char *in,
                                 unsigned long long inlen)
{
    return crypto_auth_hmacsha512_update((crypto_auth_hmacsha512_state *) state,
                                         in, inlen);
}

int
crypto_auth_hmacsha512256_final(crypto_auth_hmacsha512256_state *state,
                                unsigned char *out)
{
    unsigned char out0[64];

    crypto_auth_hmacsha512_final((crypto_auth_hmacsha512_state *) state, out0);
    memcpy(out, out0, 32);

    return 0;
}

int
crypto_auth(unsigned char *out, const unsigned char *in,
            unsigned long long inlen, const unsigned char *k)
{
    crypto_auth_hmacsha512256_state state;

    crypto_auth_hmacsha512256_init(&state, k, crypto_auth_KEYBYTES);
    crypto_auth_hmacsha512256_update(&state, in, inlen);
    crypto_auth_hmacsha512256_final(&state, out);

    return 0;
}
