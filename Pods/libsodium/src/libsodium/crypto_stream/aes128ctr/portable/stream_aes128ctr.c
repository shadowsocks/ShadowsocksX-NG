#include "api.h"

int crypto_stream(
        unsigned char *out,
        unsigned long long outlen,
        const unsigned char *n,
        const unsigned char *k
        )
{
    unsigned char d[crypto_stream_BEFORENMBYTES];
    crypto_stream_beforenm(d, k);
    crypto_stream_afternm(out, outlen, n, d);
    return 0;
}

int crypto_stream_xor(
        unsigned char *out,
        const unsigned char *in,
        unsigned long long inlen,
        const unsigned char *n,
        const unsigned char *k
        )
{
    unsigned char d[crypto_stream_BEFORENMBYTES];
    crypto_stream_beforenm(d, k);
    crypto_stream_xor_afternm(out, in, inlen, n, d);
    return 0;
}
