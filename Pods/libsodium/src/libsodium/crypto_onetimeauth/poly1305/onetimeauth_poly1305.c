
#include "crypto_onetimeauth_poly1305.h"
#include "donna/poly1305_donna.h"

/* LCOV_EXCL_START */
static const crypto_onetimeauth_poly1305_implementation *implementation =
    &crypto_onetimeauth_poly1305_donna_implementation;

int
crypto_onetimeauth_poly1305_set_implementation(crypto_onetimeauth_poly1305_implementation *impl)
{
    implementation = impl;

    return 0;
}

const char *
crypto_onetimeauth_poly1305_implementation_name(void)
{
    return implementation->implementation_name();
}
/* LCOV_EXCL_STOP */

int
crypto_onetimeauth_poly1305(unsigned char *out, const unsigned char *in,
                            unsigned long long inlen, const unsigned char *k)
{
    return implementation->onetimeauth(out, in, inlen, k);
}

int
crypto_onetimeauth_poly1305_verify(const unsigned char *h,
                                   const unsigned char *in,
                                   unsigned long long inlen,
                                   const unsigned char *k)
{
    return implementation->onetimeauth_verify(h, in, inlen, k);
}

int
crypto_onetimeauth_poly1305_init(crypto_onetimeauth_poly1305_state *state,
                                 const unsigned char *key)
{
    return implementation->onetimeauth_init(state, key);
}

int
crypto_onetimeauth_poly1305_update(crypto_onetimeauth_poly1305_state *state,
                                   const unsigned char *in,
                                   unsigned long long inlen)
{
    return implementation->onetimeauth_update(state, in, inlen);
}

int
crypto_onetimeauth_poly1305_final(crypto_onetimeauth_poly1305_state *state,
                                  unsigned char *out)
{
    return implementation->onetimeauth_final(state, out);
}
