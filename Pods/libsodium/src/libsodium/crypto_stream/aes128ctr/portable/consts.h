#ifndef CONSTS_H
#define CONSTS_H

#include "int128.h"

#define ROTB crypto_stream_aes128ctr_portable_ROTB
#define M0 crypto_stream_aes128ctr_portable_M0
#define EXPB0 crypto_stream_aes128ctr_portable_EXPB0
#define SWAP32 crypto_stream_aes128ctr_portable_SWAP32
#define M0SWAP crypto_stream_aes128ctr_portable_M0SWAP
#define SR crypto_stream_aes128ctr_portable_SR
#define SRM0 crypto_stream_aes128ctr_portable_SRM0
#define BS0 crypto_stream_aes128ctr_portable_BS0
#define BS1 crypto_stream_aes128ctr_portable_BS1
#define BS2 crypto_stream_aes128ctr_portable_BS2

extern const unsigned char ROTB[16];
extern const unsigned char M0[16];
extern const unsigned char EXPB0[16];
extern const unsigned char SWAP32[16];
extern const unsigned char M0SWAP[16];
extern const unsigned char SR[16];
extern const unsigned char SRM0[16];
extern const int128 BS0;
extern const int128 BS1;
extern const int128 BS2;

#endif
