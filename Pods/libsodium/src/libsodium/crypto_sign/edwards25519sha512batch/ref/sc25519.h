#ifndef SC25519_H
#define SC25519_H

#define sc25519 crypto_sign_edwards25519sha512batch_sc25519
#define sc25519_from32bytes crypto_sign_edwards25519sha512batch_sc25519_from32bytes
#define sc25519_from64bytes crypto_sign_edwards25519sha512batch_sc25519_from64bytes
#define sc25519_to32bytes crypto_sign_edwards25519sha512batch_sc25519_to32bytes
#define sc25519_pack crypto_sign_edwards25519sha512batch_sc25519_pack
#define sc25519_getparity crypto_sign_edwards25519sha512batch_sc25519_getparity
#define sc25519_setone crypto_sign_edwards25519sha512batch_sc25519_setone
#define sc25519_setzero crypto_sign_edwards25519sha512batch_sc25519_setzero
#define sc25519_neg crypto_sign_edwards25519sha512batch_sc25519_neg
#define sc25519_add crypto_sign_edwards25519sha512batch_sc25519_add
#define sc25519_sub crypto_sign_edwards25519sha512batch_sc25519_sub
#define sc25519_mul crypto_sign_edwards25519sha512batch_sc25519_mul
#define sc25519_square crypto_sign_edwards25519sha512batch_sc25519_square
#define sc25519_invert crypto_sign_edwards25519sha512batch_sc25519_invert

#include "crypto_uint32.h"

typedef struct {
  crypto_uint32 v[32];
} sc25519;

void sc25519_from32bytes(sc25519 *r, const unsigned char x[32]);

void sc25519_from64bytes(sc25519 *r, const unsigned char x[64]);

void sc25519_to32bytes(unsigned char r[32], const sc25519 *x);

void sc25519_pack(unsigned char r[32], const sc25519 *x);

unsigned char sc25519_getparity(const sc25519 *x);

void sc25519_setone(sc25519 *r);

void sc25519_setzero(sc25519 *r);

void sc25519_neg(sc25519 *r, const sc25519 *x);

void sc25519_add(sc25519 *r, const sc25519 *x, const sc25519 *y);

void sc25519_sub(sc25519 *r, const sc25519 *x, const sc25519 *y);

void sc25519_mul(sc25519 *r, const sc25519 *x, const sc25519 *y);

void sc25519_square(sc25519 *r, const sc25519 *x);

void sc25519_invert(sc25519 *r, const sc25519 *x);

#endif
