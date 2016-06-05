/*
version 20080913
D. J. Bernstein
Public domain.
*/

#include "api.h"
#include "crypto_core_hsalsa20.h"
#include "crypto_stream_salsa20.h"
#include "utils.h"

static const unsigned char sigma[16] = {
    'e', 'x', 'p', 'a', 'n', 'd', ' ', '3', '2', '-', 'b', 'y', 't', 'e', ' ', 'k'
};

int crypto_stream_xor_ic(
        unsigned char *c,
  const unsigned char *m,unsigned long long mlen,
  const unsigned char *n,uint64_t ic,
  const unsigned char *k
)
{
  unsigned char subkey[32];
  int ret;
  crypto_core_hsalsa20(subkey,n,k,sigma);
  ret = crypto_stream_salsa20_xor_ic(c,m,mlen,n + 16,ic,subkey);
  sodium_memzero(subkey, sizeof subkey);
  return ret;
}

int crypto_stream_xor(
        unsigned char *c,
  const unsigned char *m,unsigned long long mlen,
  const unsigned char *n,
  const unsigned char *k
)
{
  return crypto_stream_xor_ic(c, m, mlen, n, 0ULL, k);
}
