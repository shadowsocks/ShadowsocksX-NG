#include "fe.h"
#include "crypto_verify_32.h"

/*
return 1 if f == 0
return 0 if f != 0

Preconditions:
   |f| bounded by 1.1*2^26,1.1*2^25,1.1*2^26,1.1*2^25,etc.
*/

static unsigned char zero[32];

int fe_isnonzero(const fe f)
{
  unsigned char s[32];
  fe_tobytes(s,f);
  return crypto_verify_32(s,zero);
}
