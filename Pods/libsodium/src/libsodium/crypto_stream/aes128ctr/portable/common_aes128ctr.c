#include "common.h"

uint32 load32_bigendian(const unsigned char *x)
{
  return
      (uint32) (x[3]) \
  | (((uint32) (x[2])) << 8) \
  | (((uint32) (x[1])) << 16) \
  | (((uint32) (x[0])) << 24)
  ;
}

void store32_bigendian(unsigned char *x,uint32 u)
{
  x[3] = u; u >>= 8;
  x[2] = u; u >>= 8;
  x[1] = u; u >>= 8;
  x[0] = u;
}

uint32 load32_littleendian(const unsigned char *x)
{
  return
      (uint32) (x[0]) \
  | (((uint32) (x[1])) << 8) \
  | (((uint32) (x[2])) << 16) \
  | (((uint32) (x[3])) << 24)
  ;
}

void store32_littleendian(unsigned char *x,uint32 u)
{
  x[0] = u; u >>= 8;
  x[1] = u; u >>= 8;
  x[2] = u; u >>= 8;
  x[3] = u;
}


uint64 load64_littleendian(const unsigned char *x)
{
  return
      (uint64) (x[0]) \
  | (((uint64) (x[1])) << 8) \
  | (((uint64) (x[2])) << 16) \
  | (((uint64) (x[3])) << 24)
  | (((uint64) (x[4])) << 32)
  | (((uint64) (x[5])) << 40)
  | (((uint64) (x[6])) << 48)
  | (((uint64) (x[7])) << 56)
  ;
}

void store64_littleendian(unsigned char *x,uint64 u)
{
  x[0] = u; u >>= 8;
  x[1] = u; u >>= 8;
  x[2] = u; u >>= 8;
  x[3] = u; u >>= 8;
  x[4] = u; u >>= 8;
  x[5] = u; u >>= 8;
  x[6] = u; u >>= 8;
  x[7] = u;
}
