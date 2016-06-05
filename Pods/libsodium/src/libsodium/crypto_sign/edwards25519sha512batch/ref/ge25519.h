#ifndef GE25519_H
#define GE25519_H

#include "fe25519.h"
#include "sc25519.h"

#define ge25519 crypto_sign_edwards25519sha512batch_ge25519
#define ge25519_unpack_vartime crypto_sign_edwards25519sha512batch_ge25519_unpack_vartime
#define ge25519_pack crypto_sign_edwards25519sha512batch_ge25519_pack
#define ge25519_add crypto_sign_edwards25519sha512batch_ge25519_add
#define ge25519_double crypto_sign_edwards25519sha512batch_ge25519_double
#define ge25519_scalarmult crypto_sign_edwards25519sha512batch_ge25519_scalarmult
#define ge25519_scalarmult_base crypto_sign_edwards25519sha512batch_ge25519_scalarmult_base

typedef struct {
  fe25519 x;
  fe25519 y;
  fe25519 z;
  fe25519 t;
} ge25519;

int ge25519_unpack_vartime(ge25519 *r, const unsigned char p[32]);

void ge25519_pack(unsigned char r[32], const ge25519 *p);

void ge25519_add(ge25519 *r, const ge25519 *p, const ge25519 *q);

void ge25519_double(ge25519 *r, const ge25519 *p);

void ge25519_scalarmult(ge25519 *r, const ge25519 *p, const sc25519 *s);

void ge25519_scalarmult_base(ge25519 *r, const sc25519 *s);

#endif
