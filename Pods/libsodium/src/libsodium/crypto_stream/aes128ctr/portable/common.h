/* Author: Peter Schwabe, ported from an assembly implementation by Emilia Käsper
 Date: 2009-03-19
 Public domain */
#ifndef COMMON_H
#define COMMON_H

#include "types.h"

#define load32_bigendian crypto_stream_aes128ctr_portable_load32_bigendian
uint32 load32_bigendian(const unsigned char *x);

#define store32_bigendian crypto_stream_aes128ctr_portable_store32_bigendian
void store32_bigendian(unsigned char *x,uint32 u);

#define load32_littleendian crypto_stream_aes128ctr_portable_load32_littleendian
uint32 load32_littleendian(const unsigned char *x);

#define store32_littleendian crypto_stream_aes128ctr_portable_store32_littleendian
void store32_littleendian(unsigned char *x,uint32 u);

#define load64_littleendian crypto_stream_aes128ctr_portable_load64_littleendian
uint64 load64_littleendian(const unsigned char *x);

#define store64_littleendian crypto_stream_aes128ctr_portable_store64_littleendian
void store64_littleendian(unsigned char *x,uint64 u);

/* Macros required only for key expansion */

#define keyexpbs1(b0, b1, b2, b3, b4, b5, b6, b7, t0, t1, t2, t3, t4, t5, t6, t7, bskey) \
  rotbyte(&b0);\
  rotbyte(&b1);\
  rotbyte(&b2);\
  rotbyte(&b3);\
  rotbyte(&b4);\
  rotbyte(&b5);\
  rotbyte(&b6);\
  rotbyte(&b7);\
  ;\
  sbox(b0, b1, b2, b3, b4, b5, b6, b7, t0, t1, t2, t3, t4, t5, t6, t7);\
  ;\
  xor_rcon(&b0);\
  shufb(&b0, EXPB0);\
  shufb(&b1, EXPB0);\
  shufb(&b4, EXPB0);\
  shufb(&b6, EXPB0);\
  shufb(&b3, EXPB0);\
  shufb(&b7, EXPB0);\
  shufb(&b2, EXPB0);\
  shufb(&b5, EXPB0);\
  shufb(&b0, EXPB0);\
  ;\
  t0 = *(int128 *)(bskey + 0);\
  t1 = *(int128 *)(bskey + 16);\
  t2 = *(int128 *)(bskey + 32);\
  t3 = *(int128 *)(bskey + 48);\
  t4 = *(int128 *)(bskey + 64);\
  t5 = *(int128 *)(bskey + 80);\
  t6 = *(int128 *)(bskey + 96);\
  t7 = *(int128 *)(bskey + 112);\
  ;\
  xor2(&b0, &t0);\
  xor2(&b1, &t1);\
  xor2(&b4, &t2);\
  xor2(&b6, &t3);\
  xor2(&b3, &t4);\
  xor2(&b7, &t5);\
  xor2(&b2, &t6);\
  xor2(&b5, &t7);\
  ;\
  rshift32_littleendian(&t0, 8);\
  rshift32_littleendian(&t1, 8);\
  rshift32_littleendian(&t2, 8);\
  rshift32_littleendian(&t3, 8);\
  rshift32_littleendian(&t4, 8);\
  rshift32_littleendian(&t5, 8);\
  rshift32_littleendian(&t6, 8);\
  rshift32_littleendian(&t7, 8);\
  ;\
  xor2(&b0, &t0);\
  xor2(&b1, &t1);\
  xor2(&b4, &t2);\
  xor2(&b6, &t3);\
  xor2(&b3, &t4);\
  xor2(&b7, &t5);\
  xor2(&b2, &t6);\
  xor2(&b5, &t7);\
  ;\
  rshift32_littleendian(&t0, 8);\
  rshift32_littleendian(&t1, 8);\
  rshift32_littleendian(&t2, 8);\
  rshift32_littleendian(&t3, 8);\
  rshift32_littleendian(&t4, 8);\
  rshift32_littleendian(&t5, 8);\
  rshift32_littleendian(&t6, 8);\
  rshift32_littleendian(&t7, 8);\
  ;\
  xor2(&b0, &t0);\
  xor2(&b1, &t1);\
  xor2(&b4, &t2);\
  xor2(&b6, &t3);\
  xor2(&b3, &t4);\
  xor2(&b7, &t5);\
  xor2(&b2, &t6);\
  xor2(&b5, &t7);\
  ;\
  rshift32_littleendian(&t0, 8);\
  rshift32_littleendian(&t1, 8);\
  rshift32_littleendian(&t2, 8);\
  rshift32_littleendian(&t3, 8);\
  rshift32_littleendian(&t4, 8);\
  rshift32_littleendian(&t5, 8);\
  rshift32_littleendian(&t6, 8);\
  rshift32_littleendian(&t7, 8);\
  ;\
  xor2(&b0, &t0);\
  xor2(&b1, &t1);\
  xor2(&b4, &t2);\
  xor2(&b6, &t3);\
  xor2(&b3, &t4);\
  xor2(&b7, &t5);\
  xor2(&b2, &t6);\
  xor2(&b5, &t7);\
  ;\
  *(int128 *)(bskey + 128) = b0;\
  *(int128 *)(bskey + 144) = b1;\
  *(int128 *)(bskey + 160) = b4;\
  *(int128 *)(bskey + 176) = b6;\
  *(int128 *)(bskey + 192) = b3;\
  *(int128 *)(bskey + 208) = b7;\
  *(int128 *)(bskey + 224) = b2;\
  *(int128 *)(bskey + 240) = b5;\

#define keyexpbs10(b0, b1, b2, b3, b4, b5, b6, b7, t0, t1, t2, t3, t4, t5, t6, t7, bskey) ;\
  toggle(&b0);\
  toggle(&b1);\
  toggle(&b5);\
  toggle(&b6);\
  rotbyte(&b0);\
  rotbyte(&b1);\
  rotbyte(&b2);\
  rotbyte(&b3);\
  rotbyte(&b4);\
  rotbyte(&b5);\
  rotbyte(&b6);\
  rotbyte(&b7);\
  ;\
  sbox(b0, b1, b2, b3, b4, b5, b6, b7, t0, t1, t2, t3, t4, t5, t6, t7);\
  ;\
  xor_rcon(&b1);\
  xor_rcon(&b4);\
  xor_rcon(&b3);\
  xor_rcon(&b7);\
  shufb(&b0, EXPB0);\
  shufb(&b1, EXPB0);\
  shufb(&b4, EXPB0);\
  shufb(&b6, EXPB0);\
  shufb(&b3, EXPB0);\
  shufb(&b7, EXPB0);\
  shufb(&b2, EXPB0);\
  shufb(&b5, EXPB0);\
  ;\
  t0 = *(int128 *)(bskey + 9 * 128 +   0);\
  t1 = *(int128 *)(bskey + 9 * 128 +  16);\
  t2 = *(int128 *)(bskey + 9 * 128 +  32);\
  t3 = *(int128 *)(bskey + 9 * 128 +  48);\
  t4 = *(int128 *)(bskey + 9 * 128 +  64);\
  t5 = *(int128 *)(bskey + 9 * 128 +  80);\
  t6 = *(int128 *)(bskey + 9 * 128 +  96);\
  t7 = *(int128 *)(bskey + 9 * 128 + 112);\
  ;\
  toggle(&t0);\
  toggle(&t1);\
  toggle(&t5);\
  toggle(&t6);\
  ;\
  xor2(&b0, &t0);\
  xor2(&b1, &t1);\
  xor2(&b4, &t2);\
  xor2(&b6, &t3);\
  xor2(&b3, &t4);\
  xor2(&b7, &t5);\
  xor2(&b2, &t6);\
  xor2(&b5, &t7);\
  ;\
  rshift32_littleendian(&t0, 8);\
  rshift32_littleendian(&t1, 8);\
  rshift32_littleendian(&t2, 8);\
  rshift32_littleendian(&t3, 8);\
  rshift32_littleendian(&t4, 8);\
  rshift32_littleendian(&t5, 8);\
  rshift32_littleendian(&t6, 8);\
  rshift32_littleendian(&t7, 8);\
  ;\
  xor2(&b0, &t0);\
  xor2(&b1, &t1);\
  xor2(&b4, &t2);\
  xor2(&b6, &t3);\
  xor2(&b3, &t4);\
  xor2(&b7, &t5);\
  xor2(&b2, &t6);\
  xor2(&b5, &t7);\
  ;\
  rshift32_littleendian(&t0, 8);\
  rshift32_littleendian(&t1, 8);\
  rshift32_littleendian(&t2, 8);\
  rshift32_littleendian(&t3, 8);\
  rshift32_littleendian(&t4, 8);\
  rshift32_littleendian(&t5, 8);\
  rshift32_littleendian(&t6, 8);\
  rshift32_littleendian(&t7, 8);\
  ;\
  xor2(&b0, &t0);\
  xor2(&b1, &t1);\
  xor2(&b4, &t2);\
  xor2(&b6, &t3);\
  xor2(&b3, &t4);\
  xor2(&b7, &t5);\
  xor2(&b2, &t6);\
  xor2(&b5, &t7);\
  ;\
  rshift32_littleendian(&t0, 8);\
  rshift32_littleendian(&t1, 8);\
  rshift32_littleendian(&t2, 8);\
  rshift32_littleendian(&t3, 8);\
  rshift32_littleendian(&t4, 8);\
  rshift32_littleendian(&t5, 8);\
  rshift32_littleendian(&t6, 8);\
  rshift32_littleendian(&t7, 8);\
  ;\
  xor2(&b0, &t0);\
  xor2(&b1, &t1);\
  xor2(&b4, &t2);\
  xor2(&b6, &t3);\
  xor2(&b3, &t4);\
  xor2(&b7, &t5);\
  xor2(&b2, &t6);\
  xor2(&b5, &t7);\
  ;\
  shufb(&b0, M0);\
  shufb(&b1, M0);\
  shufb(&b2, M0);\
  shufb(&b3, M0);\
  shufb(&b4, M0);\
  shufb(&b5, M0);\
  shufb(&b6, M0);\
  shufb(&b7, M0);\
  ;\
  *(int128 *)(bskey + 1280) = b0;\
  *(int128 *)(bskey + 1296) = b1;\
  *(int128 *)(bskey + 1312) = b4;\
  *(int128 *)(bskey + 1328) = b6;\
  *(int128 *)(bskey + 1344) = b3;\
  *(int128 *)(bskey + 1360) = b7;\
  *(int128 *)(bskey + 1376) = b2;\
  *(int128 *)(bskey + 1392) = b5;\


#define keyexpbs(b0, b1, b2, b3, b4, b5, b6, b7, t0, t1, t2, t3, t4, t5, t6, t7, rcon, i, bskey) \
  toggle(&b0);\
  toggle(&b1);\
  toggle(&b5);\
  toggle(&b6);\
  rotbyte(&b0);\
  rotbyte(&b1);\
  rotbyte(&b2);\
  rotbyte(&b3);\
  rotbyte(&b4);\
  rotbyte(&b5);\
  rotbyte(&b6);\
  rotbyte(&b7);\
  ;\
  sbox(b0, b1, b2, b3, b4, b5, b6, b7, t0, t1, t2, t3, t4, t5, t6, t7);\
  ;\
  rcon;\
  shufb(&b0, EXPB0);\
  shufb(&b1, EXPB0);\
  shufb(&b4, EXPB0);\
  shufb(&b6, EXPB0);\
  shufb(&b3, EXPB0);\
  shufb(&b7, EXPB0);\
  shufb(&b2, EXPB0);\
  shufb(&b5, EXPB0);\
  ;\
  t0 = *(int128 *)(bskey + (i-1) * 128 +   0);\
  t1 = *(int128 *)(bskey + (i-1) * 128 +  16);\
  t2 = *(int128 *)(bskey + (i-1) * 128 +  32);\
  t3 = *(int128 *)(bskey + (i-1) * 128 +  48);\
  t4 = *(int128 *)(bskey + (i-1) * 128 +  64);\
  t5 = *(int128 *)(bskey + (i-1) * 128 +  80);\
  t6 = *(int128 *)(bskey + (i-1) * 128 +  96);\
  t7 = *(int128 *)(bskey + (i-1) * 128 + 112);\
  ;\
  toggle(&t0);\
  toggle(&t1);\
  toggle(&t5);\
  toggle(&t6);\
  ;\
  xor2(&b0, &t0);\
  xor2(&b1, &t1);\
  xor2(&b4, &t2);\
  xor2(&b6, &t3);\
  xor2(&b3, &t4);\
  xor2(&b7, &t5);\
  xor2(&b2, &t6);\
  xor2(&b5, &t7);\
  ;\
  rshift32_littleendian(&t0, 8);\
  rshift32_littleendian(&t1, 8);\
  rshift32_littleendian(&t2, 8);\
  rshift32_littleendian(&t3, 8);\
  rshift32_littleendian(&t4, 8);\
  rshift32_littleendian(&t5, 8);\
  rshift32_littleendian(&t6, 8);\
  rshift32_littleendian(&t7, 8);\
  ;\
  xor2(&b0, &t0);\
  xor2(&b1, &t1);\
  xor2(&b4, &t2);\
  xor2(&b6, &t3);\
  xor2(&b3, &t4);\
  xor2(&b7, &t5);\
  xor2(&b2, &t6);\
  xor2(&b5, &t7);\
  ;\
  rshift32_littleendian(&t0, 8);\
  rshift32_littleendian(&t1, 8);\
  rshift32_littleendian(&t2, 8);\
  rshift32_littleendian(&t3, 8);\
  rshift32_littleendian(&t4, 8);\
  rshift32_littleendian(&t5, 8);\
  rshift32_littleendian(&t6, 8);\
  rshift32_littleendian(&t7, 8);\
  ;\
  xor2(&b0, &t0);\
  xor2(&b1, &t1);\
  xor2(&b4, &t2);\
  xor2(&b6, &t3);\
  xor2(&b3, &t4);\
  xor2(&b7, &t5);\
  xor2(&b2, &t6);\
  xor2(&b5, &t7);\
  ;\
  rshift32_littleendian(&t0, 8);\
  rshift32_littleendian(&t1, 8);\
  rshift32_littleendian(&t2, 8);\
  rshift32_littleendian(&t3, 8);\
  rshift32_littleendian(&t4, 8);\
  rshift32_littleendian(&t5, 8);\
  rshift32_littleendian(&t6, 8);\
  rshift32_littleendian(&t7, 8);\
  ;\
  xor2(&b0, &t0);\
  xor2(&b1, &t1);\
  xor2(&b4, &t2);\
  xor2(&b6, &t3);\
  xor2(&b3, &t4);\
  xor2(&b7, &t5);\
  xor2(&b2, &t6);\
  xor2(&b5, &t7);\
  ;\
  *(int128 *)(bskey + i*128 +   0) = b0;\
  *(int128 *)(bskey + i*128 +  16) = b1;\
  *(int128 *)(bskey + i*128 +  32) = b4;\
  *(int128 *)(bskey + i*128 +  48) = b6;\
  *(int128 *)(bskey + i*128 +  64) = b3;\
  *(int128 *)(bskey + i*128 +  80) = b7;\
  *(int128 *)(bskey + i*128 +  96) = b2;\
  *(int128 *)(bskey + i*128 + 112) = b5;\

/* Macros used in multiple contexts */

#define bitslicekey0(key, bskey) \
  xmm0 = *(const int128 *) (key + 0);\
  shufb(&xmm0, M0);\
  copy2(&xmm1, &xmm0);\
  copy2(&xmm2, &xmm0);\
  copy2(&xmm3, &xmm0);\
  copy2(&xmm4, &xmm0);\
  copy2(&xmm5, &xmm0);\
  copy2(&xmm6, &xmm0);\
  copy2(&xmm7, &xmm0);\
  ;\
  bitslice(xmm7, xmm6, xmm5, xmm4, xmm3, xmm2, xmm1, xmm0, t);\
  ;\
  *(int128 *) (bskey + 0) = xmm0;\
  *(int128 *) (bskey + 16) = xmm1;\
  *(int128 *) (bskey + 32) = xmm2;\
  *(int128 *) (bskey + 48) = xmm3;\
  *(int128 *) (bskey + 64) = xmm4;\
  *(int128 *) (bskey + 80) = xmm5;\
  *(int128 *) (bskey + 96) = xmm6;\
  *(int128 *) (bskey + 112) = xmm7;\


#define bitslicekey10(key, bskey) \
  xmm0 = *(int128 *) (key + 0);\
  copy2(xmm1, xmm0);\
  copy2(xmm2, xmm0);\
  copy2(xmm3, xmm0);\
  copy2(xmm4, xmm0);\
  copy2(xmm5, xmm0);\
  copy2(xmm6, xmm0);\
  copy2(xmm7, xmm0);\
  ;\
  bitslice(xmm7, xmm6, xmm5, xmm4, xmm3, xmm2, xmm1, xmm0, t);\
  ;\
  toggle(&xmm6);\
  toggle(&xmm5);\
  toggle(&xmm1);\
  toggle(&xmm0);\
  ;\
  *(int128 *) (bskey +   0 + 1280) = xmm0;\
  *(int128 *) (bskey +  16 + 1280) = xmm1;\
  *(int128 *) (bskey +  32 + 1280) = xmm2;\
  *(int128 *) (bskey +  48 + 1280) = xmm3;\
  *(int128 *) (bskey +  64 + 1280) = xmm4;\
  *(int128 *) (bskey +  80 + 1280) = xmm5;\
  *(int128 *) (bskey +  96 + 1280) = xmm6;\
  *(int128 *) (bskey + 112 + 1280) = xmm7;\


#define bitslicekey(i,key,bskey) \
  xmm0 = *(int128 *) (key + 0);\
  shufb(&xmm0, M0);\
  copy2(&xmm1, &xmm0);\
  copy2(&xmm2, &xmm0);\
  copy2(&xmm3, &xmm0);\
  copy2(&xmm4, &xmm0);\
  copy2(&xmm5, &xmm0);\
  copy2(&xmm6, &xmm0);\
  copy2(&xmm7, &xmm0);\
  ;\
  bitslice(xmm7, xmm6, xmm5, xmm4, xmm3, xmm2, xmm1, xmm0, t);\
  ;\
  toggle(&xmm6);\
  toggle(&xmm5);\
  toggle(&xmm1);\
  toggle(&xmm0);\
  ;\
  *(int128 *) (bskey +   0 + 128*i) = xmm0;\
  *(int128 *) (bskey +  16 + 128*i) = xmm1;\
  *(int128 *) (bskey +  32 + 128*i) = xmm2;\
  *(int128 *) (bskey +  48 + 128*i) = xmm3;\
  *(int128 *) (bskey +  64 + 128*i) = xmm4;\
  *(int128 *) (bskey +  80 + 128*i) = xmm5;\
  *(int128 *) (bskey +  96 + 128*i) = xmm6;\
  *(int128 *) (bskey + 112 + 128*i) = xmm7;\


#define bitslice(x0, x1, x2, x3, x4, x5, x6, x7, t) \
        swapmove(x0, x1, 1, BS0, t);\
        swapmove(x2, x3, 1, BS0, t);\
        swapmove(x4, x5, 1, BS0, t);\
        swapmove(x6, x7, 1, BS0, t);\
        ;\
        swapmove(x0, x2, 2, BS1, t);\
        swapmove(x1, x3, 2, BS1, t);\
        swapmove(x4, x6, 2, BS1, t);\
        swapmove(x5, x7, 2, BS1, t);\
        ;\
        swapmove(x0, x4, 4, BS2, t);\
        swapmove(x1, x5, 4, BS2, t);\
        swapmove(x2, x6, 4, BS2, t);\
        swapmove(x3, x7, 4, BS2, t);\


#define swapmove(a, b, n, m, t) \
        copy2(&t, &b);\
  rshift64_littleendian(&t, n);\
        xor2(&t, &a);\
  and2(&t, &m);\
  xor2(&a, &t);\
  lshift64_littleendian(&t, n);\
  xor2(&b, &t);

#define rotbyte(x) \
  shufb(x, ROTB) /* TODO: Make faster */


/* Macros used for encryption (and decryption) */

#define shiftrows(x0, x1, x2, x3, x4, x5, x6, x7, i, M, bskey) \
        xor2(&x0, (const int128 *)(bskey + 128*(i-1) + 0));\
  shufb(&x0, M);\
        xor2(&x1, (const int128 *)(bskey + 128*(i-1) + 16));\
  shufb(&x1, M);\
        xor2(&x2, (const int128 *)(bskey + 128*(i-1) + 32));\
  shufb(&x2, M);\
        xor2(&x3, (const int128 *)(bskey + 128*(i-1) + 48));\
  shufb(&x3, M);\
        xor2(&x4, (const int128 *)(bskey + 128*(i-1) + 64));\
  shufb(&x4, M);\
        xor2(&x5, (const int128 *)(bskey + 128*(i-1) + 80));\
  shufb(&x5, M);\
        xor2(&x6, (const int128 *)(bskey + 128*(i-1) + 96));\
  shufb(&x6, M);\
        xor2(&x7, (const int128 *)(bskey + 128*(i-1) + 112));\
  shufb(&x7, M);\


#define mixcolumns(x0, x1, x2, x3, x4, x5, x6, x7, t0, t1, t2, t3, t4, t5, t6, t7) \
  shufd(&t0, &x0, 0x93);\
  shufd(&t1, &x1, 0x93);\
  shufd(&t2, &x2, 0x93);\
  shufd(&t3, &x3, 0x93);\
  shufd(&t4, &x4, 0x93);\
  shufd(&t5, &x5, 0x93);\
  shufd(&t6, &x6, 0x93);\
  shufd(&t7, &x7, 0x93);\
        ;\
        xor2(&x0, &t0);\
        xor2(&x1, &t1);\
        xor2(&x2, &t2);\
        xor2(&x3, &t3);\
        xor2(&x4, &t4);\
        xor2(&x5, &t5);\
        xor2(&x6, &t6);\
        xor2(&x7, &t7);\
        ;\
        xor2(&t0, &x7);\
        xor2(&t1, &x0);\
        xor2(&t2, &x1);\
        xor2(&t1, &x7);\
        xor2(&t3, &x2);\
        xor2(&t4, &x3);\
        xor2(&t5, &x4);\
        xor2(&t3, &x7);\
        xor2(&t6, &x5);\
        xor2(&t7, &x6);\
        xor2(&t4, &x7);\
        ;\
  shufd(&x0, &x0, 0x4e);\
  shufd(&x1, &x1, 0x4e);\
  shufd(&x2, &x2, 0x4e);\
  shufd(&x3, &x3, 0x4e);\
  shufd(&x4, &x4, 0x4e);\
  shufd(&x5, &x5, 0x4e);\
  shufd(&x6, &x6, 0x4e);\
  shufd(&x7, &x7, 0x4e);\
        ;\
        xor2(&t0, &x0);\
        xor2(&t1, &x1);\
        xor2(&t2, &x2);\
        xor2(&t3, &x3);\
        xor2(&t4, &x4);\
        xor2(&t5, &x5);\
        xor2(&t6, &x6);\
        xor2(&t7, &x7);\


#define aesround(i, b0, b1, b2, b3, b4, b5, b6, b7, t0, t1, t2, t3, t4, t5, t6, t7, bskey) \
        shiftrows(b0, b1, b2, b3, b4, b5, b6, b7, i, SR, bskey);\
        sbox(b0, b1, b2, b3, b4, b5, b6, b7, t0, t1, t2, t3, t4, t5, t6, t7);\
        mixcolumns(b0, b1, b4, b6, b3, b7, b2, b5, t0, t1, t2, t3, t4, t5, t6, t7);\


#define lastround(b0, b1, b2, b3, b4, b5, b6, b7, t0, t1, t2, t3, t4, t5, t6, t7, bskey) \
        shiftrows(b0, b1, b2, b3, b4, b5, b6, b7, 10, SRM0, bskey);\
        sbox(b0, b1, b2, b3, b4, b5, b6, b7, t0, t1, t2, t3, t4, t5, t6, t7);\
        xor2(&b0,(const int128 *)(bskey + 128*10));\
        xor2(&b1,(const int128 *)(bskey + 128*10+16));\
        xor2(&b4,(const int128 *)(bskey + 128*10+32));\
        xor2(&b6,(const int128 *)(bskey + 128*10+48));\
        xor2(&b3,(const int128 *)(bskey + 128*10+64));\
        xor2(&b7,(const int128 *)(bskey + 128*10+80));\
        xor2(&b2,(const int128 *)(bskey + 128*10+96));\
        xor2(&b5,(const int128 *)(bskey + 128*10+112));\


#define sbox(b0, b1, b2, b3, b4, b5, b6, b7, t0, t1, t2, t3, s0, s1, s2, s3) \
        InBasisChange(b0, b1, b2, b3, b4, b5, b6, b7); \
        Inv_GF256(b6, b5, b0, b3, b7, b1, b4, b2, t0, t1, t2, t3, s0, s1, s2, s3); \
        OutBasisChange(b7, b1, b4, b2, b6, b5, b0, b3); \


#define InBasisChange(b0, b1, b2, b3, b4, b5, b6, b7) \
        xor2(&b5, &b6);\
        xor2(&b2, &b1);\
        xor2(&b5, &b0);\
        xor2(&b6, &b2);\
        xor2(&b3, &b0);\
        ;\
        xor2(&b6, &b3);\
        xor2(&b3, &b7);\
        xor2(&b3, &b4);\
        xor2(&b7, &b5);\
        xor2(&b3, &b1);\
        ;\
        xor2(&b4, &b5);\
        xor2(&b2, &b7);\
        xor2(&b1, &b5);\

#define OutBasisChange(b0, b1, b2, b3, b4, b5, b6, b7) \
        xor2(&b0, &b6);\
        xor2(&b1, &b4);\
        xor2(&b2, &b0);\
        xor2(&b4, &b6);\
        xor2(&b6, &b1);\
        ;\
        xor2(&b1, &b5);\
        xor2(&b5, &b3);\
        xor2(&b2, &b5);\
        xor2(&b3, &b7);\
        xor2(&b7, &b5);\
        ;\
        xor2(&b4, &b7);\

#define Mul_GF4(x0, x1, y0, y1, t0) \
        copy2(&t0, &y0);\
        xor2(&t0, &y1);\
        and2(&t0, &x0);\
        xor2(&x0, &x1);\
        and2(&x0, &y1);\
        and2(&x1, &y0);\
        xor2(&x0, &x1);\
        xor2(&x1, &t0);\

#define Mul_GF4_N(x0, x1, y0, y1, t0) \
        copy2(&t0, &y0);\
        xor2(&t0, &y1);\
        and2(&t0, &x0);\
        xor2(&x0, &x1);\
        and2(&x0, &y1);\
        and2(&x1, &y0);\
        xor2(&x1, &x0);\
        xor2(&x0, &t0);\

#define Mul_GF4_2(x0, x1, x2, x3, y0, y1, t0, t1) \
        copy2(&t0, = y0);\
        xor2(&t0, &y1);\
        copy2(&t1, &t0);\
        and2(&t0, &x0);\
        and2(&t1, &x2);\
        xor2(&x0, &x1);\
        xor2(&x2, &x3);\
        and2(&x0, &y1);\
        and2(&x2, &y1);\
        and2(&x1, &y0);\
        and2(&x3, &y0);\
        xor2(&x0, &x1);\
        xor2(&x2, &x3);\
        xor2(&x1, &t0);\
        xor2(&x3, &t1);\

#define Mul_GF16(x0, x1, x2, x3, y0, y1, y2, y3, t0, t1, t2, t3) \
        copy2(&t0, &x0);\
        copy2(&t1, &x1);\
        Mul_GF4(x0, x1, y0, y1, t2);\
        xor2(&t0, &x2);\
        xor2(&t1, &x3);\
        xor2(&y0, &y2);\
        xor2(&y1, &y3);\
        Mul_GF4_N(t0, t1, y0, y1, t2);\
        Mul_GF4(x2, x3, y2, y3, t3);\
        ;\
        xor2(&x0, &t0);\
        xor2(&x2, &t0);\
        xor2(&x1, &t1);\
        xor2(&x3, &t1);\

#define Mul_GF16_2(x0, x1, x2, x3, x4, x5, x6, x7, y0, y1, y2, y3, t0, t1, t2, t3) \
        copy2(&t0, &x0);\
        copy2(&t1, &x1);\
        Mul_GF4(x0, x1, y0, y1, t2);\
        xor2(&t0, &x2);\
        xor2(&t1, &x3);\
        xor2(&y0, &y2);\
        xor2(&y1, &y3);\
        Mul_GF4_N(t0, t1, y0, y1, t3);\
        Mul_GF4(x2, x3, y2, y3, t2);\
        ;\
        xor2(&x0, &t0);\
        xor2(&x2, &t0);\
        xor2(&x1, &t1);\
        xor2(&x3, &t1);\
        ;\
        copy2(&t0, &x4);\
        copy2(&t1, &x5);\
        xor2(&t0, &x6);\
        xor2(&t1, &x7);\
        Mul_GF4_N(t0, t1, y0, y1, t3);\
        Mul_GF4(x6, x7, y2, y3, t2);\
        xor2(&y0, &y2);\
        xor2(&y1, &y3);\
        Mul_GF4(x4, x5, y0, y1, t3);\
        ;\
        xor2(&x4, &t0);\
        xor2(&x6, &t0);\
        xor2(&x5, &t1);\
        xor2(&x7, &t1);\

#define Inv_GF16(x0, x1, x2, x3, t0, t1, t2, t3) \
        copy2(&t0, &x1);\
        copy2(&t1, &x0);\
        and2(&t0, &x3);\
        or2(&t1, &x2);\
        copy2(&t2, &x1);\
        copy2(&t3, &x0);\
        or2(&t2, &x2);\
        or2(&t3, &x3);\
        xor2(&t2, &t3);\
        ;\
        xor2(&t0, &t2);\
        xor2(&t1, &t2);\
        ;\
        Mul_GF4_2(x0, x1, x2, x3, t1, t0, t2, t3);\


#define Inv_GF256(x0,  x1, x2, x3, x4, x5, x6, x7, t0, t1, t2, t3, s0, s1, s2, s3) \
        copy2(&t3, &x4);\
        copy2(&t2, &x5);\
        copy2(&t1, &x1);\
        copy2(&s1, &x7);\
        copy2(&s0, &x0);\
        ;\
        xor2(&t3, &x6);\
        xor2(&t2, &x7);\
        xor2(&t1, &x3);\
        xor2(&s1, &x6);\
        xor2(&s0, &x2);\
        ;\
        copy2(&s2, &t3);\
        copy2(&t0, &t2);\
        copy2(&s3, &t3);\
        ;\
        or2(&t2, &t1);\
        or2(&t3, &s0);\
        xor2(&s3, &t0);\
        and2(&s2, &s0);\
        and2(&t0, &t1);\
        xor2(&s0, &t1);\
        and2(&s3, &s0);\
        copy2(&s0, &x3);\
        xor2(&s0, &x2);\
        and2(&s1, &s0);\
        xor2(&t3, &s1);\
        xor2(&t2, &s1);\
        copy2(&s1, &x4);\
        xor2(&s1, &x5);\
        copy2(&s0, &x1);\
        copy2(&t1, &s1);\
        xor2(&s0, &x0);\
        or2(&t1, &s0);\
        and2(&s1, &s0);\
        xor2(&t0, &s1);\
        xor2(&t3, &s3);\
        xor2(&t2, &s2);\
        xor2(&t1, &s3);\
        xor2(&t0, &s2);\
        xor2(&t1, &s2);\
        copy2(&s0, &x7);\
        copy2(&s1, &x6);\
        copy2(&s2, &x5);\
        copy2(&s3, &x4);\
        and2(&s0, &x3);\
        and2(&s1, &x2);\
        and2(&s2, &x1);\
        or2(&s3, &x0);\
        xor2(&t3, &s0);\
        xor2(&t2, &s1);\
        xor2(&t1, &s2);\
        xor2(&t0, &s3);\
  ;\
  copy2(&s0, &t3);\
  xor2(&s0, &t2);\
  and2(&t3, &t1);\
  copy2(&s2, &t0);\
  xor2(&s2, &t3);\
  copy2(&s3, &s0);\
  and2(&s3, &s2);\
  xor2(&s3, &t2);\
  copy2(&s1, &t1);\
  xor2(&s1, &t0);\
  xor2(&t3, &t2);\
  and2(&s1, &t3);\
  xor2(&s1, &t0);\
  xor2(&t1, &s1);\
  copy2(&t2, &s2);\
  xor2(&t2, &s1);\
  and2(&t2, &t0);\
  xor2(&t1, &t2);\
  xor2(&s2, &t2);\
  and2(&s2, &s3);\
  xor2(&s2, &s0);\
  ;\
  Mul_GF16_2(x0, x1, x2, x3, x4, x5, x6, x7, s3, s2, s1, t1, s0, t0, t2, t3);\

#endif
