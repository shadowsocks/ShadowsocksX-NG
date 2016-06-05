#include "api.h"
#include "crypto_verify_64.h"
#include "utils.h"

int crypto_auth_verify(const unsigned char *h, const unsigned char *in,
                       unsigned long long inlen, const unsigned char *k)
{
  unsigned char correct[64];
  crypto_auth(correct,in,inlen,k);
  return crypto_verify_64(h,correct) | (-(h == correct)) |
         sodium_memcmp(correct,h,64);
}
