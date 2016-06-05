#include "fe25519.h"

#define WINDOWSIZE 4 /* Should be 1,2, or 4 */
#define WINDOWMASK ((1<<WINDOWSIZE)-1)

static void reduce_add_sub(fe25519 *r)
{
  crypto_uint32 t;
  int i,rep;

  for(rep=0;rep<4;rep++)
  {
    t = r->v[31] >> 7;
    r->v[31] &= 127;
    t *= 19;
    r->v[0] += t;
    for(i=0;i<31;i++)
    {
      t = r->v[i] >> 8;
      r->v[i+1] += t;
      r->v[i] &= 255;
    }
  }
}

static void reduce_mul(fe25519 *r)
{
  crypto_uint32 t;
  int i,rep;

  for(rep=0;rep<2;rep++)
  {
    t = r->v[31] >> 7;
    r->v[31] &= 127;
    t *= 19;
    r->v[0] += t;
    for(i=0;i<31;i++)
    {
      t = r->v[i] >> 8;
      r->v[i+1] += t;
      r->v[i] &= 255;
    }
  }
}

/* reduction modulo 2^255-19 */
static void freeze(fe25519 *r)
{
  int i;
  unsigned int m = (r->v[31] == 127);
  for(i=30;i>1;i--)
    m *= (r->v[i] == 255);
  m *= (r->v[0] >= 237);

  r->v[31] -= m*127;
  for(i=30;i>0;i--)
    r->v[i] -= m*255;
  r->v[0] -= m*237;
}

/*freeze input before calling isone*/
static int isone(const fe25519 *x)
{
  int i;
  int r = (x->v[0] == 1);
  for(i=1;i<32;i++)
    r *= (x->v[i] == 0);
  return r;
}

/*freeze input before calling iszero*/
static int iszero(const fe25519 *x)
{
  int i;
  int r = (x->v[0] == 0);
  for(i=1;i<32;i++)
    r *= (x->v[i] == 0);
  return r;
}


static int issquare(const fe25519 *x)
{
  unsigned char e[32] = {0xf6,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0x3f}; /* (p-1)/2 */
  fe25519 t;

  fe25519_pow(&t,x,e);
  freeze(&t);
  return isone(&t) || iszero(&t);
}

void fe25519_unpack(fe25519 *r, const unsigned char x[32])
{
  int i;
  for(i=0;i<32;i++) r->v[i] = x[i];
  r->v[31] &= 127;
}

/* Assumes input x being reduced mod 2^255 */
void fe25519_pack(unsigned char r[32], const fe25519 *x)
{
  int i;
  unsigned int m;
  for(i=0;i<32;i++)
    r[i] = x->v[i];

  /* freeze byte array */
  m = (r[31] == 127); /* XXX: some compilers might use branches; fix */
  for(i=30;i>1;i--)
    m *= (r[i] == 255);
  m *= (r[0] >= 237);
  r[31] -= m*127;
  for(i=30;i>0;i--)
    r[i] -= m*255;
  r[0] -= m*237;
}

void fe25519_cmov(fe25519 *r, const fe25519 *x, unsigned char b)
{
  unsigned char nb = 1-b;
  int i;
  for(i=0;i<32;i++) r->v[i] = nb * r->v[i] + b * x->v[i];
}

unsigned char fe25519_getparity(const fe25519 *x)
{
  fe25519 t;
  int i;
  for(i=0;i<32;i++) t.v[i] = x->v[i];
  freeze(&t);
  return t.v[0] & 1;
}

void fe25519_setone(fe25519 *r)
{
  int i;
  r->v[0] = 1;
  for(i=1;i<32;i++) r->v[i]=0;
}

void fe25519_setzero(fe25519 *r)
{
  int i;
  for(i=0;i<32;i++) r->v[i]=0;
}

void fe25519_neg(fe25519 *r, const fe25519 *x)
{
  fe25519 t;
  int i;
  for(i=0;i<32;i++) t.v[i]=x->v[i];
  fe25519_setzero(r);
  fe25519_sub(r, r, &t);
}

void fe25519_add(fe25519 *r, const fe25519 *x, const fe25519 *y)
{
  int i;
  for(i=0;i<32;i++) r->v[i] = x->v[i] + y->v[i];
  reduce_add_sub(r);
}

void fe25519_sub(fe25519 *r, const fe25519 *x, const fe25519 *y)
{
  int i;
  crypto_uint32 t[32];
  t[0] = x->v[0] + 0x1da;
  t[31] = x->v[31] + 0xfe;
  for(i=1;i<31;i++) t[i] = x->v[i] + 0x1fe;
  for(i=0;i<32;i++) r->v[i] = t[i] - y->v[i];
  reduce_add_sub(r);
}

void fe25519_mul(fe25519 *r, const fe25519 *x, const fe25519 *y)
{
  int i,j;
  crypto_uint32 t[63];
  for(i=0;i<63;i++)t[i] = 0;

  for(i=0;i<32;i++)
    for(j=0;j<32;j++)
      t[i+j] += x->v[i] * y->v[j];

  for(i=32;i<63;i++)
    r->v[i-32] = t[i-32] + 38*t[i];
  r->v[31] = t[31]; /* result now in r[0]...r[31] */

  reduce_mul(r);
}

void fe25519_square(fe25519 *r, const fe25519 *x)
{
  fe25519_mul(r, x, x);
}

/*XXX: Make constant time! */
void fe25519_pow(fe25519 *r, const fe25519 *x, const unsigned char *e)
{
  /*
  fe25519 g;
  fe25519_setone(&g);
  int i;
  unsigned char j;
  for(i=32;i>0;i--)
  {
    for(j=128;j>0;j>>=1)
    {
      fe25519_square(&g,&g);
      if(e[i-1] & j)
        fe25519_mul(&g,&g,x);
    }
  }
  for(i=0;i<32;i++) r->v[i] = g.v[i];
  */
  fe25519 g;
  int i,j,k;
  fe25519 t;
  unsigned char w;
  fe25519 pre[(1 << WINDOWSIZE)];

  fe25519_setone(&g);

  // Precomputation
  fe25519_setone(pre);
  pre[1] = *x;
  for(i=2;i<(1<<WINDOWSIZE);i+=2)
  {
    fe25519_square(pre+i, pre+i/2);
    fe25519_mul(pre+i+1, pre+i, pre+1);
  }

  // Fixed-window scalar multiplication
  for(i=32;i>0;i--)
  {
    for(j=8-WINDOWSIZE;j>=0;j-=WINDOWSIZE)
    {
      for(k=0;k<WINDOWSIZE;k++)
        fe25519_square(&g, &g);
      // Cache-timing resistant loading of precomputed value:
      w = (e[i-1]>>j) & WINDOWMASK;
      t = pre[0];
      for(k=1;k<(1<<WINDOWSIZE);k++)
        fe25519_cmov(&t, &pre[k], k==w);
      fe25519_mul(&g, &g, &t);
    }
  }
  *r = g;
}

/* Return 0 on success, 1 otherwise */
int fe25519_sqrt_vartime(fe25519 *r, const fe25519 *x, unsigned char parity)
{
  unsigned char e[32] = {0xfb,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0x1f}; /* (p-1)/4 */
  unsigned char e2[32] = {0xfe,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0x0f}; /* (p+3)/8 */
  unsigned char e3[32] = {0xfd,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0x0f}; /* (p-5)/8 */
  fe25519 p = {{0}};
  fe25519 d;
  int i;

  /* See HAC, Alg. 3.37 */
  if (!issquare(x)) return -1;
  fe25519_pow(&d,x,e);
  freeze(&d);
  if(isone(&d))
    fe25519_pow(r,x,e2);
  else
  {
    for(i=0;i<32;i++)
      d.v[i] = 4*x->v[i];
    fe25519_pow(&d,&d,e3);
    for(i=0;i<32;i++)
      r->v[i] = 2*x->v[i];
    fe25519_mul(r,r,&d);
  }
  freeze(r);
  if((r->v[0] & 1) != (parity & 1))
  {
    fe25519_sub(r,&p,r);
  }
  return 0;
}

void fe25519_invert(fe25519 *r, const fe25519 *x)
{
        fe25519 z2;
        fe25519 z9;
        fe25519 z11;
        fe25519 z2_5_0;
        fe25519 z2_10_0;
        fe25519 z2_20_0;
        fe25519 z2_50_0;
        fe25519 z2_100_0;
        fe25519 t0;
        fe25519 t1;
        int i;

        /* 2 */ fe25519_square(&z2,x);
        /* 4 */ fe25519_square(&t1,&z2);
        /* 8 */ fe25519_square(&t0,&t1);
        /* 9 */ fe25519_mul(&z9,&t0,x);
        /* 11 */ fe25519_mul(&z11,&z9,&z2);
        /* 22 */ fe25519_square(&t0,&z11);
        /* 2^5 - 2^0 = 31 */ fe25519_mul(&z2_5_0,&t0,&z9);

        /* 2^6 - 2^1 */ fe25519_square(&t0,&z2_5_0);
        /* 2^7 - 2^2 */ fe25519_square(&t1,&t0);
        /* 2^8 - 2^3 */ fe25519_square(&t0,&t1);
        /* 2^9 - 2^4 */ fe25519_square(&t1,&t0);
        /* 2^10 - 2^5 */ fe25519_square(&t0,&t1);
        /* 2^10 - 2^0 */ fe25519_mul(&z2_10_0,&t0,&z2_5_0);

        /* 2^11 - 2^1 */ fe25519_square(&t0,&z2_10_0);
        /* 2^12 - 2^2 */ fe25519_square(&t1,&t0);
        /* 2^20 - 2^10 */ for (i = 2;i < 10;i += 2) { fe25519_square(&t0,&t1); fe25519_square(&t1,&t0); }
        /* 2^20 - 2^0 */ fe25519_mul(&z2_20_0,&t1,&z2_10_0);

        /* 2^21 - 2^1 */ fe25519_square(&t0,&z2_20_0);
        /* 2^22 - 2^2 */ fe25519_square(&t1,&t0);
        /* 2^40 - 2^20 */ for (i = 2;i < 20;i += 2) { fe25519_square(&t0,&t1); fe25519_square(&t1,&t0); }
        /* 2^40 - 2^0 */ fe25519_mul(&t0,&t1,&z2_20_0);

        /* 2^41 - 2^1 */ fe25519_square(&t1,&t0);
        /* 2^42 - 2^2 */ fe25519_square(&t0,&t1);
        /* 2^50 - 2^10 */ for (i = 2;i < 10;i += 2) { fe25519_square(&t1,&t0); fe25519_square(&t0,&t1); }
        /* 2^50 - 2^0 */ fe25519_mul(&z2_50_0,&t0,&z2_10_0);

        /* 2^51 - 2^1 */ fe25519_square(&t0,&z2_50_0);
        /* 2^52 - 2^2 */ fe25519_square(&t1,&t0);
        /* 2^100 - 2^50 */ for (i = 2;i < 50;i += 2) { fe25519_square(&t0,&t1); fe25519_square(&t1,&t0); }
        /* 2^100 - 2^0 */ fe25519_mul(&z2_100_0,&t1,&z2_50_0);

        /* 2^101 - 2^1 */ fe25519_square(&t1,&z2_100_0);
        /* 2^102 - 2^2 */ fe25519_square(&t0,&t1);
        /* 2^200 - 2^100 */ for (i = 2;i < 100;i += 2) { fe25519_square(&t1,&t0); fe25519_square(&t0,&t1); }
        /* 2^200 - 2^0 */ fe25519_mul(&t1,&t0,&z2_100_0);

        /* 2^201 - 2^1 */ fe25519_square(&t0,&t1);
        /* 2^202 - 2^2 */ fe25519_square(&t1,&t0);
        /* 2^250 - 2^50 */ for (i = 2;i < 50;i += 2) { fe25519_square(&t0,&t1); fe25519_square(&t1,&t0); }
        /* 2^250 - 2^0 */ fe25519_mul(&t0,&t1,&z2_50_0);

        /* 2^251 - 2^1 */ fe25519_square(&t1,&t0);
        /* 2^252 - 2^2 */ fe25519_square(&t0,&t1);
        /* 2^253 - 2^3 */ fe25519_square(&t1,&t0);
        /* 2^254 - 2^4 */ fe25519_square(&t0,&t1);
        /* 2^255 - 2^5 */ fe25519_square(&t1,&t0);
        /* 2^255 - 21 */ fe25519_mul(r,&t1,&z11);
}
