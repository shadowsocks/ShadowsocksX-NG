#include <string.h>

#include "crypto_hash_sha512.h"
#include "crypto_scalarmult_curve25519.h"
#include "api.h"
#include "randombytes.h"

int crypto_box_seed_keypair(
  unsigned char *pk,
  unsigned char *sk,
  const unsigned char *seed
)
{
  unsigned char hash[64];
  crypto_hash_sha512(hash,seed,32);
  memmove(sk,hash,32);
  return crypto_scalarmult_curve25519_base(pk,sk);
}

int crypto_box_keypair(
  unsigned char *pk,
  unsigned char *sk
)
{
  randombytes_buf(sk,32);
  return crypto_scalarmult_curve25519_base(pk,sk);
}
