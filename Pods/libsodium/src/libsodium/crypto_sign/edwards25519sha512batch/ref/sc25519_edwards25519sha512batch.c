#include "sc25519.h"

/*Arithmetic modulo the group order n = 2^252 +  27742317777372353535851937790883648493 = 7237005577332262213973186563042994240857116359379907606001950938285454250989 */

static const crypto_uint32 m[32] = {0xED, 0xD3, 0xF5, 0x5C, 0x1A, 0x63, 0x12, 0x58, 0xD6, 0x9C, 0xF7, 0xA2, 0xDE, 0xF9, 0xDE, 0x14,
                                    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x10};

static const crypto_uint32 mu[33] = {0x1B, 0x13, 0x2C, 0x0A, 0xA3, 0xE5, 0x9C, 0xED, 0xA7, 0x29, 0x63, 0x08, 0x5D, 0x21, 0x06, 0x21,
                                     0xEB, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x0F};

/* Reduce coefficients of r before calling reduce_add_sub */
static void reduce_add_sub(sc25519 *r)
{
  int i, b, pb=0, nb;
  unsigned char t[32];

  for(i=0;i<32;i++)
  {
    b = (r->v[i]<pb+m[i]);
    t[i] = r->v[i]-pb-m[i]+b*256;
    pb = b;
  }
  nb = 1-b;
  for(i=0;i<32;i++)
    r->v[i] = r->v[i]*b + t[i]*nb;
}

/* Reduce coefficients of x before calling barrett_reduce */
static void barrett_reduce(sc25519 *r, const crypto_uint32 x[64])
{
  /* See HAC, Alg. 14.42 */
  int i,j;
  crypto_uint32 q2[66] = {0};
  crypto_uint32 *q3 = q2 + 33;
  crypto_uint32 r1[33];
  crypto_uint32 r2[33] = {0};
  crypto_uint32 carry;
  int b, pb=0;

  for(i=0;i<33;i++)
    for(j=0;j<33;j++)
      if(i+j >= 31) q2[i+j] += mu[i]*x[j+31];
  carry = q2[31] >> 8;
  q2[32] += carry;
  carry = q2[32] >> 8;
  q2[33] += carry;

  for(i=0;i<33;i++)r1[i] = x[i];
  for(i=0;i<32;i++) {
    for(j=0;j<33;j++) {
      if(i+j < 33) {
          /* coverity[overrun-local] */
          r2[i+j] += m[i]*q3[j];
      }
    }
  }
  for(i=0;i<32;i++)
  {
    carry = r2[i] >> 8;
    r2[i+1] += carry;
    r2[i] &= 0xff;
  }

  for(i=0;i<32;i++)
  {
    b = (r1[i]<pb+r2[i]);
    r->v[i] = r1[i]-pb-r2[i]+b*256;
    pb = b;
  }

  /* XXX: Can it really happen that r<0?, See HAC, Alg 14.42, Step 3
   * If so: Handle  it here!
   */

  reduce_add_sub(r);
  reduce_add_sub(r);
}

/*
static int iszero(const sc25519 *x)
{
  // Implement
  return 0;
}
*/

void sc25519_from32bytes(sc25519 *r, const unsigned char x[32])
{
  int i;
  crypto_uint32 t[64] = {0};
  for(i=0;i<32;i++) t[i] = x[i];
  barrett_reduce(r, t);
}

void sc25519_from64bytes(sc25519 *r, const unsigned char x[64])
{
  int i;
  crypto_uint32 t[64] = {0};
  for(i=0;i<64;i++) t[i] = x[i];
  barrett_reduce(r, t);
}

/* XXX: What we actually want for crypto_group is probably just something like
 * void sc25519_frombytes(sc25519 *r, const unsigned char *x, size_t xlen)
 */

void sc25519_to32bytes(unsigned char r[32], const sc25519 *x)
{
  int i;
  for(i=0;i<32;i++) r[i] = x->v[i];
}

void sc25519_add(sc25519 *r, const sc25519 *x, const sc25519 *y)
{
  int i, carry;
  for(i=0;i<32;i++) r->v[i] = x->v[i] + y->v[i];
  for(i=0;i<31;i++)
  {
    carry = r->v[i] >> 8;
    r->v[i+1] += carry;
    r->v[i] &= 0xff;
  }
  reduce_add_sub(r);
}

void sc25519_mul(sc25519 *r, const sc25519 *x, const sc25519 *y)
{
  int i,j,carry;
  crypto_uint32 t[64];
  for(i=0;i<64;i++)t[i] = 0;

  for(i=0;i<32;i++)
    for(j=0;j<32;j++)
      t[i+j] += x->v[i] * y->v[j];

  /* Reduce coefficients */
  for(i=0;i<63;i++)
  {
    carry = t[i] >> 8;
    t[i+1] += carry;
    t[i] &= 0xff;
  }

  barrett_reduce(r, t);
}

void sc25519_square(sc25519 *r, const sc25519 *x)
{
  sc25519_mul(r, x, x);
}
