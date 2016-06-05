#include "api.h"
#include "utils.h"

int crypto_box(
  unsigned char *c,
  const unsigned char *m,unsigned long long mlen,
  const unsigned char *n,
  const unsigned char *pk,
  const unsigned char *sk
)
{
  unsigned char k[crypto_box_BEFORENMBYTES];
  int           ret;

  crypto_box_beforenm(k,pk,sk);
  ret = crypto_box_afternm(c,m,mlen,n,k);
  sodium_memzero(k, sizeof k);

  return ret;
}

int crypto_box_open(
  unsigned char *m,
  const unsigned char *c,unsigned long long clen,
  const unsigned char *n,
  const unsigned char *pk,
  const unsigned char *sk
)
{
  unsigned char k[crypto_box_BEFORENMBYTES];
  int           ret;

  crypto_box_beforenm(k,pk,sk);
  ret = crypto_box_open_afternm(m,c,clen,n,k);
  sodium_memzero(k, sizeof k);

  return ret;
}
