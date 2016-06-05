
#include "crypto_stream.h"

size_t
crypto_stream_keybytes(void)
{
    return crypto_stream_KEYBYTES;
}

size_t
crypto_stream_noncebytes(void)
{
    return crypto_stream_NONCEBYTES;
}

const char *
crypto_stream_primitive(void)
{
    return crypto_stream_PRIMITIVE;
}

int
crypto_stream(unsigned char *c, unsigned long long clen,
              const unsigned char *n, const unsigned char *k)
{
    return crypto_stream_xsalsa20(c, clen, n, k);
}


int
crypto_stream_xor(unsigned char *c, const unsigned char *m,
                  unsigned long long mlen, const unsigned char *n,
                  const unsigned char *k)
{
    return crypto_stream_xsalsa20_xor(c, m, mlen, n, k);
}
