/*
   BLAKE2 reference source code package - reference C implementations

   Written in 2012 by Samuel Neves <sneves@dei.uc.pt>

   To the extent possible under law, the author(s) have dedicated all copyright
   and related and neighboring rights to this software to the public domain
   worldwide. This software is distributed without any warranty.

   You should have received a copy of the CC0 Public Domain Dedication along with
   this software. If not, see <http://creativecommons.org/publicdomain/zero/1.0/>.
*/

#ifndef blake2_H
#define blake2_H

#include <stddef.h>
#include <stdint.h>

#include "crypto_generichash_blake2b.h"

#define blake2b_init_param             crypto_generichash_blake2b__init_param
#define blake2b_init                   crypto_generichash_blake2b__init
#define blake2b_init_salt_personal     crypto_generichash_blake2b__init_salt_personal
#define blake2b_init_key               crypto_generichash_blake2b__init_key
#define blake2b_init_key_salt_personal crypto_generichash_blake2b__init_key_salt_personal
#define blake2b_update                 crypto_generichash_blake2b__update
#define blake2b_final                  crypto_generichash_blake2b__final
#define blake2b                        crypto_generichash_blake2b__blake2b
#define blake2b_salt_personal          crypto_generichash_blake2b__blake2b_salt_personal

#if defined(_MSC_VER)
#define ALIGN(x) __declspec(align(x))
#else
#define ALIGN(x) __attribute__((aligned(x)))
#endif

#if defined(__cplusplus)
extern "C" {
#endif

  enum blake2s_constant
  {
    BLAKE2S_BLOCKBYTES = 64,
    BLAKE2S_OUTBYTES   = 32,
    BLAKE2S_KEYBYTES   = 32,
    BLAKE2S_SALTBYTES  = 8,
    BLAKE2S_PERSONALBYTES = 8
  };

  enum blake2b_constant
  {
    BLAKE2B_BLOCKBYTES = 128,
    BLAKE2B_OUTBYTES   = 64,
    BLAKE2B_KEYBYTES   = 64,
    BLAKE2B_SALTBYTES  = 16,
    BLAKE2B_PERSONALBYTES = 16
  };

#pragma pack(push, 1)
  typedef struct blake2s_param_
  {
    uint8_t  digest_length; // 1
    uint8_t  key_length;    // 2
    uint8_t  fanout;        // 3
    uint8_t  depth;         // 4
    uint32_t leaf_length;   // 8
    uint8_t  node_offset[6];// 14
    uint8_t  node_depth;    // 15
    uint8_t  inner_length;  // 16
    // uint8_t  reserved[0];
    uint8_t  salt[BLAKE2S_SALTBYTES]; // 24
    uint8_t  personal[BLAKE2S_PERSONALBYTES];  // 32
  } blake2s_param;

  ALIGN( 64 ) typedef struct blake2s_state_
  {
    uint32_t h[8];
    uint32_t t[2];
    uint32_t f[2];
    uint8_t  buf[2 * BLAKE2S_BLOCKBYTES];
    size_t   buflen;
    uint8_t  last_node;
  } blake2s_state ;

  typedef struct blake2b_param_
  {
    uint8_t  digest_length; // 1
    uint8_t  key_length;    // 2
    uint8_t  fanout;        // 3
    uint8_t  depth;         // 4
    uint32_t leaf_length;   // 8
    uint64_t node_offset;   // 16
    uint8_t  node_depth;    // 17
    uint8_t  inner_length;  // 18
    uint8_t  reserved[14];  // 32
    uint8_t  salt[BLAKE2B_SALTBYTES]; // 48
    uint8_t  personal[BLAKE2B_PERSONALBYTES];  // 64
  } blake2b_param;

#ifndef DEFINE_BLAKE2B_STATE
typedef crypto_generichash_blake2b_state blake2b_state;
#else
  ALIGN( 64 ) typedef struct blake2b_state_
  {
    uint64_t h[8];
    uint64_t t[2];
    uint64_t f[2];
    uint8_t  buf[2 * BLAKE2B_BLOCKBYTES];
    size_t   buflen;
    uint8_t  last_node;
  } blake2b_state;
#endif

  typedef struct blake2sp_state_
  {
    blake2s_state S[8][1];
    blake2s_state R[1];
    uint8_t buf[8 * BLAKE2S_BLOCKBYTES];
    size_t  buflen;
  } blake2sp_state;

  typedef struct blake2bp_state_
  {
    blake2b_state S[4][1];
    blake2b_state R[1];
    uint8_t buf[4 * BLAKE2B_BLOCKBYTES];
    size_t  buflen;
  } blake2bp_state;
#pragma pack(pop)

  // Streaming API
  int blake2s_init( blake2s_state *S, const uint8_t outlen );
  int blake2s_init_key( blake2s_state *S, const uint8_t outlen, const void *key, const uint8_t keylen );
  int blake2s_init_param( blake2s_state *S, const blake2s_param *P );
  int blake2s_update( blake2s_state *S, const uint8_t *in, uint64_t inlen );
  int blake2s_final( blake2s_state *S, uint8_t *out, uint8_t outlen );

  int blake2b_init( blake2b_state *S, const uint8_t outlen );
  int blake2b_init_salt_personal( blake2b_state *S, const uint8_t outlen,
                                  const void *personal, const void *salt );
  int blake2b_init_key( blake2b_state *S, const uint8_t outlen, const void *key, const uint8_t keylen );
  int blake2b_init_key_salt_personal( blake2b_state *S, const uint8_t outlen, const void *key, const uint8_t keylen,
                                      const void *salt, const void *personal );
  int blake2b_init_param( blake2b_state *S, const blake2b_param *P );
  int blake2b_update( blake2b_state *S, const uint8_t *in, uint64_t inlen );
  int blake2b_final( blake2b_state *S, uint8_t *out, uint8_t outlen );

  int blake2sp_init( blake2sp_state *S, const uint8_t outlen );
  int blake2sp_init_key( blake2sp_state *S, const uint8_t outlen, const void *key, const uint8_t keylen );
  int blake2sp_update( blake2sp_state *S, const uint8_t *in, uint64_t inlen );
  int blake2sp_final( blake2sp_state *S, uint8_t *out, uint8_t outlen );

  int blake2bp_init( blake2bp_state *S, const uint8_t outlen );
  int blake2bp_init_key( blake2bp_state *S, const uint8_t outlen, const void *key, const uint8_t keylen );
  int blake2bp_update( blake2bp_state *S, const uint8_t *in, uint64_t inlen );
  int blake2bp_final( blake2bp_state *S, uint8_t *out, uint8_t outlen );

  // Simple API
  int blake2s( uint8_t *out, const void *in, const void *key, const uint8_t outlen, const uint64_t inlen, uint8_t keylen );
  int blake2b( uint8_t *out, const void *in, const void *key, const uint8_t outlen, const uint64_t inlen, uint8_t keylen );
  int blake2b_salt_personal( uint8_t *out, const void *in, const void *key, const uint8_t outlen, const uint64_t inlen, uint8_t keylen, const void *salt, const void *personal );

  int blake2sp( uint8_t *out, const void *in, const void *key, const uint8_t outlen, const uint64_t inlen, uint8_t keylen );
  int blake2bp( uint8_t *out, const void *in, const void *key, const uint8_t outlen, const uint64_t inlen, uint8_t keylen );

  static inline int blake2( uint8_t *out, const void *in, const void *key, const uint8_t outlen, const uint64_t inlen, uint8_t keylen )
  {
    return blake2b( out, in, key, outlen, inlen, keylen );
  }

#if defined(__cplusplus)
}
#endif

#endif

