/* Author: Peter Schwabe, ported from an assembly implementation by Emilia Käsper
 * Date: 2009-03-19
 * Public domain */

#include "api.h"
#include "consts.h"
#include "int128.h"
#include "common.h"

int crypto_stream_beforenm(unsigned char *c, const unsigned char *k)
{

  /*
     int64 x0;
     int64 x1;
     int64 x2;
     int64 x3;
     int64 e;
     int64 q0;
     int64 q1;
     int64 q2;
     int64 q3;
     */

  int128 xmm0;
  int128 xmm1;
  int128 xmm2;
  int128 xmm3;
  int128 xmm4;
  int128 xmm5;
  int128 xmm6;
  int128 xmm7;
  int128 xmm8;
  int128 xmm9;
  int128 xmm10;
  int128 xmm11;
  int128 xmm12;
  int128 xmm13;
  int128 xmm14;
  int128 xmm15;
  int128 t;

  bitslicekey0(k, c)

    keyexpbs1(xmm0, xmm1, xmm2, xmm3, xmm4, xmm5, xmm6, xmm7, xmm8, xmm9, xmm10, xmm11, xmm12, xmm13, xmm14, xmm15,c)
    keyexpbs(xmm0, xmm1, xmm4, xmm6, xmm3, xmm7, xmm2, xmm5, xmm8, xmm9, xmm10, xmm11, xmm12, xmm13, xmm14, xmm15, xor_rcon(&xmm1);, 2,c)
    keyexpbs(xmm0, xmm1, xmm3, xmm2, xmm6, xmm5, xmm4, xmm7, xmm8, xmm9, xmm10, xmm11, xmm12, xmm13, xmm14, xmm15, xor_rcon(&xmm6);, 3,c)
    keyexpbs(xmm0, xmm1, xmm6, xmm4, xmm2, xmm7, xmm3, xmm5, xmm8, xmm9, xmm10, xmm11, xmm12, xmm13, xmm14, xmm15, xor_rcon(&xmm3);, 4,c)

    keyexpbs(xmm0, xmm1, xmm2, xmm3, xmm4, xmm5, xmm6, xmm7, xmm8, xmm9, xmm10, xmm11, xmm12, xmm13, xmm14, xmm15, xor_rcon(&xmm3);, 5,c)
    keyexpbs(xmm0, xmm1, xmm4, xmm6, xmm3, xmm7, xmm2, xmm5, xmm8, xmm9, xmm10, xmm11, xmm12, xmm13, xmm14, xmm15, xor_rcon(&xmm5);, 6,c)
    keyexpbs(xmm0, xmm1, xmm3, xmm2, xmm6, xmm5, xmm4, xmm7, xmm8, xmm9, xmm10, xmm11, xmm12, xmm13, xmm14, xmm15, xor_rcon(&xmm3);, 7,c)
    keyexpbs(xmm0, xmm1, xmm6, xmm4, xmm2, xmm7, xmm3, xmm5, xmm8, xmm9, xmm10, xmm11, xmm12, xmm13, xmm14, xmm15, xor_rcon(&xmm7);, 8,c)

    keyexpbs(xmm0, xmm1, xmm2, xmm3, xmm4, xmm5, xmm6, xmm7, xmm8, xmm9, xmm10, xmm11, xmm12, xmm13, xmm14, xmm15, xor_rcon(&xmm0); xor_rcon(&xmm1); xor_rcon(&xmm6); xor_rcon(&xmm3);, 9,c)
    keyexpbs10(xmm0, xmm1, xmm4, xmm6, xmm3, xmm7, xmm2, xmm5, xmm8, xmm9, xmm10, xmm11, xmm12, xmm13, xmm14, xmm15,c)

    return 0;
}
