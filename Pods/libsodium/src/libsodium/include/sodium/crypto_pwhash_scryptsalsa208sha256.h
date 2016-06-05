#ifndef crypto_pwhash_scryptsalsa208sha256_H
#define crypto_pwhash_scryptsalsa208sha256_H

#include <stddef.h>
#include <stdint.h>

#include "export.h"

#ifdef __cplusplus
# if __GNUC__
#  pragma GCC diagnostic ignored "-Wlong-long"
# endif
extern "C" {
#endif

#define crypto_pwhash_scryptsalsa208sha256_SALTBYTES 32U
SODIUM_EXPORT
size_t crypto_pwhash_scryptsalsa208sha256_saltbytes(void);

#define crypto_pwhash_scryptsalsa208sha256_STRBYTES 102U
SODIUM_EXPORT
size_t crypto_pwhash_scryptsalsa208sha256_strbytes(void);

#define crypto_pwhash_scryptsalsa208sha256_STRPREFIX "$7$"
SODIUM_EXPORT
const char *crypto_pwhash_scryptsalsa208sha256_strprefix(void);

#define crypto_pwhash_scryptsalsa208sha256_OPSLIMIT_INTERACTIVE 524288ULL
SODIUM_EXPORT
size_t crypto_pwhash_scryptsalsa208sha256_opslimit_interactive(void);

#define crypto_pwhash_scryptsalsa208sha256_MEMLIMIT_INTERACTIVE 16777216ULL
SODIUM_EXPORT
size_t crypto_pwhash_scryptsalsa208sha256_memlimit_interactive(void);

#define crypto_pwhash_scryptsalsa208sha256_OPSLIMIT_SENSITIVE 33554432ULL
SODIUM_EXPORT
size_t crypto_pwhash_scryptsalsa208sha256_opslimit_sensitive(void);

#define crypto_pwhash_scryptsalsa208sha256_MEMLIMIT_SENSITIVE 1073741824ULL
SODIUM_EXPORT
size_t crypto_pwhash_scryptsalsa208sha256_memlimit_sensitive(void);

SODIUM_EXPORT
int crypto_pwhash_scryptsalsa208sha256(unsigned char * const out,
                                       unsigned long long outlen,
                                       const char * const passwd,
                                       unsigned long long passwdlen,
                                       const unsigned char * const salt,
                                       unsigned long long opslimit,
                                       size_t memlimit);

SODIUM_EXPORT
int crypto_pwhash_scryptsalsa208sha256_str(char out[crypto_pwhash_scryptsalsa208sha256_STRBYTES],
                                           const char * const passwd,
                                           unsigned long long passwdlen,
                                           unsigned long long opslimit,
                                           size_t memlimit);

SODIUM_EXPORT
int crypto_pwhash_scryptsalsa208sha256_str_verify(const char str[crypto_pwhash_scryptsalsa208sha256_STRBYTES],
                                                  const char * const passwd,
                                                  unsigned long long passwdlen);

SODIUM_EXPORT
int crypto_pwhash_scryptsalsa208sha256_ll(const uint8_t * passwd, size_t passwdlen,
                                          const uint8_t * salt, size_t saltlen,
                                          uint64_t N, uint32_t r, uint32_t p,
                                          uint8_t * buf, size_t buflen);

#ifdef __cplusplus
}
#endif

#endif
