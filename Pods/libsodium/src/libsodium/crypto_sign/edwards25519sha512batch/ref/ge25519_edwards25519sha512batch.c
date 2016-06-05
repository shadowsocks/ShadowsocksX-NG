#include "fe25519.h"
#include "sc25519.h"
#include "ge25519.h"

/*
 * Arithmetic on the twisted Edwards curve -x^2 + y^2 = 1 + dx^2y^2
 * with d = -(121665/121666) = 37095705934669439343138083508754565189542113879843219016388785533085940283555
 * Base point: (15112221349535400772501151409588531511454012693041857206046113283949847762202,46316835694926478169428394003475163141307993866256225615783033603165251855960);
 */

typedef struct
{
  fe25519 x;
  fe25519 z;
  fe25519 y;
  fe25519 t;
} ge25519_p1p1;

typedef struct
{
  fe25519 x;
  fe25519 y;
  fe25519 z;
} ge25519_p2;

#define ge25519_p3 ge25519

/* Windowsize for fixed-window scalar multiplication */
#define WINDOWSIZE 2                      /* Should be 1,2, or 4 */
#define WINDOWMASK ((1<<WINDOWSIZE)-1)

/* packed parameter d in the Edwards curve equation */
static const unsigned char ecd[32] = {0xA3, 0x78, 0x59, 0x13, 0xCA, 0x4D, 0xEB, 0x75, 0xAB, 0xD8, 0x41, 0x41, 0x4D, 0x0A, 0x70, 0x00,
                                      0x98, 0xE8, 0x79, 0x77, 0x79, 0x40, 0xC7, 0x8C, 0x73, 0xFE, 0x6F, 0x2B, 0xEE, 0x6C, 0x03, 0x52};

/* Packed coordinates of the base point */
static const unsigned char ge25519_base_x[32] = {0x1A, 0xD5, 0x25, 0x8F, 0x60, 0x2D, 0x56, 0xC9, 0xB2, 0xA7, 0x25, 0x95, 0x60, 0xC7, 0x2C, 0x69,
                                                 0x5C, 0xDC, 0xD6, 0xFD, 0x31, 0xE2, 0xA4, 0xC0, 0xFE, 0x53, 0x6E, 0xCD, 0xD3, 0x36, 0x69, 0x21};
static const unsigned char ge25519_base_y[32] = {0x58, 0x66, 0x66, 0x66, 0x66, 0x66, 0x66, 0x66, 0x66, 0x66, 0x66, 0x66, 0x66, 0x66, 0x66, 0x66,
                                                 0x66, 0x66, 0x66, 0x66, 0x66, 0x66, 0x66, 0x66, 0x66, 0x66, 0x66, 0x66, 0x66, 0x66, 0x66, 0x66};
static const unsigned char ge25519_base_z[32] = {1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0};
static const unsigned char ge25519_base_t[32] = {0xA3, 0xDD, 0xB7, 0xA5, 0xB3, 0x8A, 0xDE, 0x6D, 0xF5, 0x52, 0x51, 0x77, 0x80, 0x9F, 0xF0, 0x20,
                                                 0x7D, 0xE3, 0xAB, 0x64, 0x8E, 0x4E, 0xEA, 0x66, 0x65, 0x76, 0x8B, 0xD7, 0x0F, 0x5F, 0x87, 0x67};

/* Packed coordinates of the neutral element */
static const unsigned char ge25519_neutral_x[32] = {0};
static const unsigned char ge25519_neutral_y[32] = {1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0};
static const unsigned char ge25519_neutral_z[32] = {1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0};
static const unsigned char ge25519_neutral_t[32] = {0};

static void p1p1_to_p2(ge25519_p2 *r, const ge25519_p1p1 *p)
{
  fe25519_mul(&r->x, &p->x, &p->t);
  fe25519_mul(&r->y, &p->y, &p->z);
  fe25519_mul(&r->z, &p->z, &p->t);
}

static void p1p1_to_p3(ge25519_p3 *r, const ge25519_p1p1 *p)
{
  p1p1_to_p2((ge25519_p2 *)r, p);
  fe25519_mul(&r->t, &p->x, &p->y);
}

/* Constant-time version of: if(b) r = p */
static void cmov_p3(ge25519_p3 *r, const ge25519_p3 *p, unsigned char b)
{
  fe25519_cmov(&r->x, &p->x, b);
  fe25519_cmov(&r->y, &p->y, b);
  fe25519_cmov(&r->z, &p->z, b);
  fe25519_cmov(&r->t, &p->t, b);
}

/* See http://www.hyperelliptic.org/EFD/g1p/auto-twisted-extended-1.html#doubling-dbl-2008-hwcd */
static void dbl_p1p1(ge25519_p1p1 *r, const ge25519_p2 *p)
{
  fe25519 a,b,c,d;
  fe25519_square(&a, &p->x);
  fe25519_square(&b, &p->y);
  fe25519_square(&c, &p->z);
  fe25519_add(&c, &c, &c);
  fe25519_neg(&d, &a);

  fe25519_add(&r->x, &p->x, &p->y);
  fe25519_square(&r->x, &r->x);
  fe25519_sub(&r->x, &r->x, &a);
  fe25519_sub(&r->x, &r->x, &b);
  fe25519_add(&r->z, &d, &b);
  fe25519_sub(&r->t, &r->z, &c);
  fe25519_sub(&r->y, &d, &b);
}

static void add_p1p1(ge25519_p1p1 *r, const ge25519_p3 *p, const ge25519_p3 *q)
{
  fe25519 a, b, c, d, t, fd;
  fe25519_unpack(&fd, ecd);

  fe25519_sub(&a, &p->y, &p->x); // A = (Y1-X1)*(Y2-X2)
  fe25519_sub(&t, &q->y, &q->x);
  fe25519_mul(&a, &a, &t);
  fe25519_add(&b, &p->x, &p->y); // B = (Y1+X1)*(Y2+X2)
  fe25519_add(&t, &q->x, &q->y);
  fe25519_mul(&b, &b, &t);
  fe25519_mul(&c, &p->t, &q->t); //C = T1*k*T2
  fe25519_mul(&c, &c, &fd);
  fe25519_add(&c, &c, &c);       //XXX: Can save this addition by precomputing 2*ecd
  fe25519_mul(&d, &p->z, &q->z); //D = Z1*2*Z2
  fe25519_add(&d, &d, &d);
  fe25519_sub(&r->x, &b, &a); // E = B-A
  fe25519_sub(&r->t, &d, &c); // F = D-C
  fe25519_add(&r->z, &d, &c); // G = D+C
  fe25519_add(&r->y, &b, &a); // H = B+A
}

/* ********************************************************************
 *                    EXPORTED FUNCTIONS
 ******************************************************************** */

/* return 0 on success, -1 otherwise */
int ge25519_unpack_vartime(ge25519_p3 *r, const unsigned char p[32])
{
  int ret;
  fe25519 t, fd;
  unsigned char par;

  fe25519_setone(&r->z);
  fe25519_unpack(&fd, ecd);
  par = p[31] >> 7;
  fe25519_unpack(&r->y, p);
  fe25519_square(&r->x, &r->y);
  fe25519_mul(&t, &r->x, &fd);
  fe25519_sub(&r->x, &r->x, &r->z);
  fe25519_add(&t, &r->z, &t);
  fe25519_invert(&t, &t);
  fe25519_mul(&r->x, &r->x, &t);
  ret = fe25519_sqrt_vartime(&r->x, &r->x, par);
  fe25519_mul(&r->t, &r->x, &r->y);
  return ret;
}

void ge25519_pack(unsigned char r[32], const ge25519_p3 *p)
{
  fe25519 tx, ty, zi;
  fe25519_invert(&zi, &p->z);
  fe25519_mul(&tx, &p->x, &zi);
  fe25519_mul(&ty, &p->y, &zi);
  fe25519_pack(r, &ty);
  r[31] ^= fe25519_getparity(&tx) << 7;
}

void ge25519_add(ge25519_p3 *r, const ge25519_p3 *p, const ge25519_p3 *q)
{
  ge25519_p1p1 grp1p1;
  add_p1p1(&grp1p1, p, q);
  p1p1_to_p3(r, &grp1p1);
}

void ge25519_double(ge25519_p3 *r, const ge25519_p3 *p)
{
  ge25519_p1p1 grp1p1;
  dbl_p1p1(&grp1p1, (const ge25519_p2 *)p);
  p1p1_to_p3(r, &grp1p1);
}

void ge25519_scalarmult(ge25519_p3 *r, const ge25519_p3 *p, const sc25519 *s)
{
  int i,j,k;
  ge25519_p3 g;
  ge25519_p3 pre[(1 << WINDOWSIZE)];
  ge25519_p3 t;
  ge25519_p1p1 tp1p1;
  unsigned char w;
  unsigned char sb[32];

  fe25519_unpack(&g.x, ge25519_neutral_x);
  fe25519_unpack(&g.y, ge25519_neutral_y);
  fe25519_unpack(&g.z, ge25519_neutral_z);
  fe25519_unpack(&g.t, ge25519_neutral_t);

  sc25519_to32bytes(sb, s);

  // Precomputation
  pre[0] = g;
  pre[1] = *p;
  for(i=2;i<(1<<WINDOWSIZE);i+=2)
  {
    dbl_p1p1(&tp1p1, (ge25519_p2 *)(pre+i/2));
    p1p1_to_p3(pre+i, &tp1p1);
    add_p1p1(&tp1p1, pre+i, pre+1);
    p1p1_to_p3(pre+i+1, &tp1p1);
  }

  // Fixed-window scalar multiplication
  for(i=32;i>0;i--)
  {
    for(j=8-WINDOWSIZE;j>=0;j-=WINDOWSIZE)
    {
      for(k=0;k<WINDOWSIZE-1;k++)
      {
        dbl_p1p1(&tp1p1, (ge25519_p2 *)&g);
        p1p1_to_p2((ge25519_p2 *)&g, &tp1p1);
      }
      dbl_p1p1(&tp1p1, (ge25519_p2 *)&g);
      p1p1_to_p3(&g, &tp1p1);
      // Cache-timing resistant loading of precomputed value:
      w = (sb[i-1]>>j) & WINDOWMASK;
      t = pre[0];
      for(k=1;k<(1<<WINDOWSIZE);k++)
        cmov_p3(&t, &pre[k], k==w);

      add_p1p1(&tp1p1, &g, &t);
      if(j != 0) p1p1_to_p2((ge25519_p2 *)&g, &tp1p1);
      else p1p1_to_p3(&g, &tp1p1); /* convert to p3 representation at the end */
    }
  }
  r->x = g.x;
  r->y = g.y;
  r->z = g.z;
  r->t = g.t;
}

void ge25519_scalarmult_base(ge25519_p3 *r, const sc25519 *s)
{
  /* XXX: Better algorithm for known-base-point scalar multiplication */
  ge25519_p3 t;
  fe25519_unpack(&t.x, ge25519_base_x);
  fe25519_unpack(&t.y, ge25519_base_y);
  fe25519_unpack(&t.z, ge25519_base_z);
  fe25519_unpack(&t.t, ge25519_base_t);
  ge25519_scalarmult(r, &t, s);
}
