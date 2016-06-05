#include "api.h"
#include "crypto_hash_sha512.h"
#include "randombytes.h"
#include "crypto_verify_32.h"

#include "ge25519.h"

int crypto_sign_keypair(
    unsigned char *pk,
    unsigned char *sk
    )
{
  sc25519 scsk;
  ge25519 gepk;

  randombytes_buf(sk, 32);
  crypto_hash_sha512(sk, sk, 32);
  sk[0] &= 248;
  sk[31] &= 127;
  sk[31] |= 64;

  sc25519_from32bytes(&scsk,sk);

  ge25519_scalarmult_base(&gepk, &scsk);
  ge25519_pack(pk, &gepk);
  return 0;
}

int crypto_sign(
    unsigned char *sm,unsigned long long *smlen_p,
    const unsigned char *m,unsigned long long mlen,
    const unsigned char *sk
    )
{
  sc25519 sck, scs, scsk;
  ge25519 ger;
  unsigned char r[32];
  unsigned char s[32];
  unsigned long long i;
  unsigned char hmg[crypto_hash_sha512_BYTES];
  unsigned char hmr[crypto_hash_sha512_BYTES];

  if (smlen_p != NULL) {
    *smlen_p = mlen+64;
  }
  for(i=0;i<mlen;i++)
    sm[32 + i] = m[i];
  for(i=0;i<32;i++)
    sm[i] = sk[32+i];
  crypto_hash_sha512(hmg, sm, mlen+32); /* Generate k as h(m,sk[32],...,sk[63]) */

  sc25519_from64bytes(&sck, hmg);
  ge25519_scalarmult_base(&ger, &sck);
  ge25519_pack(r, &ger);

  for(i=0;i<32;i++)
    sm[i] = r[i];

  crypto_hash_sha512(hmr, sm, mlen+32); /* Compute h(m,r) */
  sc25519_from64bytes(&scs, hmr);
  sc25519_mul(&scs, &scs, &sck);

  sc25519_from32bytes(&scsk, sk);
  sc25519_add(&scs, &scs, &scsk);

  sc25519_to32bytes(s,&scs); /* cat s */
  for(i=0;i<32;i++)
    sm[mlen+32+i] = s[i];

  return 0;
}

int crypto_sign_open(
    unsigned char *m,unsigned long long *mlen_p,
    const unsigned char *sm,unsigned long long smlen,
    const unsigned char *pk
    )
{
  unsigned long long i;
  unsigned char t1[32], t2[32];
  ge25519 get1, get2, gepk;
  sc25519 schmr, scs;
  unsigned char hmr[crypto_hash_sha512_BYTES];

  if (ge25519_unpack_vartime(&get1, sm)) return -1;
  if (ge25519_unpack_vartime(&gepk, pk)) return -1;

  crypto_hash_sha512(hmr,sm,smlen-32);

  sc25519_from64bytes(&schmr, hmr);
  ge25519_scalarmult(&get1, &get1, &schmr);
  ge25519_add(&get1, &get1, &gepk);
  ge25519_pack(t1, &get1);

  sc25519_from32bytes(&scs, &sm[smlen-32]);
  ge25519_scalarmult_base(&get2, &scs);
  ge25519_pack(t2, &get2);

  for(i=0;i<smlen-64;i++) {
    m[i] = sm[i + 32];
  }
  if (mlen_p != NULL) {
    *mlen_p = smlen-64;
  }
  return crypto_verify_32(t1, t2);
}
