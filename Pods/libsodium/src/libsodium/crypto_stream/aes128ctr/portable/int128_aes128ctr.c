
#include "int128.h"
#include "common.h"

void xor2(int128 *r, const int128 *x)
{
  r->u64[0] ^= x->u64[0];
  r->u64[1] ^= x->u64[1];
}

void and2(int128 *r, const int128 *x)
{
  r->u64[0] &= x->u64[0];
  r->u64[1] &= x->u64[1];
}

void or2(int128 *r, const int128 *x)
{
  r->u64[0] |= x->u64[0];
  r->u64[1] |= x->u64[1];
}

void copy2(int128 *r, const int128 *x)
{
  r->u64[0] = x->u64[0];
  r->u64[1] = x->u64[1];
}

void shufb(int128 *r, const unsigned char *l)
{
  int128   t;
  uint8_t *ct;
  uint8_t *cr;

  copy2(&t, r);
  cr = r->u8;
  ct = t.u8;
  cr[0] = ct[l[0]];
  cr[1] = ct[l[1]];
  cr[2] = ct[l[2]];
  cr[3] = ct[l[3]];
  cr[4] = ct[l[4]];
  cr[5] = ct[l[5]];
  cr[6] = ct[l[6]];
  cr[7] = ct[l[7]];
  cr[8] = ct[l[8]];
  cr[9] = ct[l[9]];
  cr[10] = ct[l[10]];
  cr[11] = ct[l[11]];
  cr[12] = ct[l[12]];
  cr[13] = ct[l[13]];
  cr[14] = ct[l[14]];
  cr[15] = ct[l[15]];
}

void shufd(int128 *r, const int128 *x, const unsigned int c)
{
  int128 t;

  t.u32[0] = x->u32[c >> 0 & 3];
  t.u32[1] = x->u32[c >> 2 & 3];
  t.u32[2] = x->u32[c >> 4 & 3];
  t.u32[3] = x->u32[c >> 6 & 3];
  copy2(r, &t);
}

void rshift32_littleendian(int128 *r, const unsigned int n)
{
  unsigned char *rp = (unsigned char *)r;
  uint32 t;
  t = load32_littleendian(rp);
  t >>= n;
  store32_littleendian(rp, t);
  t = load32_littleendian(rp+4);
  t >>= n;
  store32_littleendian(rp+4, t);
  t = load32_littleendian(rp+8);
  t >>= n;
  store32_littleendian(rp+8, t);
  t = load32_littleendian(rp+12);
  t >>= n;
  store32_littleendian(rp+12, t);
}

void rshift64_littleendian(int128 *r, const unsigned int n)
{
  unsigned char *rp = (unsigned char *)r;
  uint64 t;
  t = load64_littleendian(rp);
  t >>= n;
  store64_littleendian(rp, t);
  t = load64_littleendian(rp+8);
  t >>= n;
  store64_littleendian(rp+8, t);
}

void lshift64_littleendian(int128 *r, const unsigned int n)
{
  unsigned char *rp = (unsigned char *)r;
  uint64 t;
  t = load64_littleendian(rp);
  t <<= n;
  store64_littleendian(rp, t);
  t = load64_littleendian(rp+8);
  t <<= n;
  store64_littleendian(rp+8, t);
}

void toggle(int128 *r)
{
  r->u64[0] ^= 0xffffffffffffffffULL;
  r->u64[1] ^= 0xffffffffffffffffULL;
}

void xor_rcon(int128 *r)
{
  unsigned char *rp = (unsigned char *)r;
  uint32 t;
  t = load32_littleendian(rp+12);
  t ^= 0xffffffff;
  store32_littleendian(rp+12, t);
}

void add_uint32_big(int128 *r, uint32 x)
{
  unsigned char *rp = (unsigned char *)r;
  uint32 t;
  t = load32_littleendian(rp+12);
  t += x;
  store32_littleendian(rp+12, t);
}
