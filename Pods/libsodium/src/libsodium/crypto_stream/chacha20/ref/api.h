
#include "crypto_stream_chacha20.h"

int
crypto_stream_chacha20_ref(unsigned char *c, unsigned long long clen,
                           const unsigned char *n, const unsigned char *k);

int
crypto_stream_chacha20_ref_xor_ic(unsigned char *c, const unsigned char *m,
                                  unsigned long long mlen,
                                  const unsigned char *n, uint64_t ic,
                                  const unsigned char *k);
