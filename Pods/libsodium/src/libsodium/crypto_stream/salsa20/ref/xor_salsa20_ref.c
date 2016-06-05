/*
version 20140420
D. J. Bernstein
Public domain.
*/

#include <stdint.h>

#include "api.h"
#include "crypto_core_salsa20.h"
#include "utils.h"

#ifndef HAVE_AMD64_ASM

typedef unsigned int uint32;

static const unsigned char sigma[16] = {
    'e', 'x', 'p', 'a', 'n', 'd', ' ', '3', '2', '-', 'b', 'y', 't', 'e', ' ', 'k'
};

int crypto_stream_salsa20_xor_ic(
        unsigned char *c,
  const unsigned char *m,unsigned long long mlen,
  const unsigned char *n, uint64_t ic,
  const unsigned char *k
)
{
  unsigned char in[16];
  unsigned char block[64];
  unsigned char kcopy[32];
  unsigned int i;
  unsigned int u;

  if (!mlen) return 0;

  for (i = 0;i < 32;++i) kcopy[i] = k[i];
  for (i = 0;i < 8;++i) in[i] = n[i];
  for (i = 8;i < 16;++i) {
      in[i] = (unsigned char) (ic & 0xff);
      ic >>= 8;
  }

  while (mlen >= 64) {
    crypto_core_salsa20(block,in,kcopy,sigma);
    for (i = 0;i < 64;++i) c[i] = m[i] ^ block[i];

    u = 1;
    for (i = 8;i < 16;++i) {
      u += (unsigned int) in[i];
      in[i] = u;
      u >>= 8;
    }

    mlen -= 64;
    c += 64;
    m += 64;
  }

  if (mlen) {
    crypto_core_salsa20(block,in,kcopy,sigma);
    for (i = 0;i < (unsigned int) mlen;++i) c[i] = m[i] ^ block[i];
  }
  sodium_memzero(block, sizeof block);
  sodium_memzero(kcopy, sizeof kcopy);

  return 0;
}

#endif
