#ifndef INT128_H
#define INT128_H

#include <stdint.h>

#include "common.h"

#ifdef __cplusplus
# if __GNUC__
#  pragma GCC diagnostic ignored "-Wlong-long"
# endif
#endif

typedef union {
  uint64_t u64[2];
  uint32_t u32[4];
  uint8_t  u8[16];
} int128;

#define xor2 crypto_stream_aes128ctr_portable_xor2
void xor2(int128 *r, const int128 *x);

#define and2 crypto_stream_aes128ctr_portable_and2
void and2(int128 *r, const int128 *x);

#define or2 crypto_stream_aes128ctr_portable_or2
void or2(int128 *r, const int128 *x);

#define copy2 crypto_stream_aes128ctr_portable_copy2
void copy2(int128 *r, const int128 *x);

#define shufb crypto_stream_aes128ctr_portable_shufb
void shufb(int128 *r, const unsigned char *l);

#define shufd crypto_stream_aes128ctr_portable_shufd
void shufd(int128 *r, const int128 *x, const unsigned int c);

#define rshift32_littleendian crypto_stream_aes128ctr_portable_rshift32_littleendian
void rshift32_littleendian(int128 *r, const unsigned int n);

#define rshift64_littleendian crypto_stream_aes128ctr_portable_rshift64_littleendian
void rshift64_littleendian(int128 *r, const unsigned int n);

#define lshift64_littleendian crypto_stream_aes128ctr_portable_lshift64_littleendian
void lshift64_littleendian(int128 *r, const unsigned int n);

#define toggle crypto_stream_aes128ctr_portable_toggle
void toggle(int128 *r);

#define xor_rcon crypto_stream_aes128ctr_portable_xor_rcon
void xor_rcon(int128 *r);

#define add_uint32_big crypto_stream_aes128ctr_portable_add_uint32_big
void add_uint32_big(int128 *r, uint32 x);

#endif
