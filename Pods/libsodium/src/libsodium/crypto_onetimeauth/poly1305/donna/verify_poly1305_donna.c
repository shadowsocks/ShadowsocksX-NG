#include "crypto_onetimeauth_poly1305.h"
#include "crypto_verify_16.h"
#include "poly1305_donna.h"

int
crypto_onetimeauth_poly1305_donna_verify(const unsigned char *h,
                                         const unsigned char *in,
                                         unsigned long long inlen,
                                         const unsigned char *k)
{
    unsigned char correct[16];

    crypto_onetimeauth_poly1305_donna(correct,in,inlen,k);
    return crypto_verify_16(h,correct);
}
