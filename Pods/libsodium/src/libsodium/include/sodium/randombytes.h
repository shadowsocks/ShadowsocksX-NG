
#ifndef randombytes_H
#define randombytes_H

#include <sys/types.h>

#include <stddef.h>
#include <stdint.h>

#include "export.h"

#ifdef __cplusplus
# if __GNUC__
#  pragma GCC diagnostic ignored "-Wlong-long"
# endif
extern "C" {
#endif

typedef struct randombytes_implementation {
    const char *(*implementation_name)(void); /* required */
    uint32_t    (*random)(void);              /* required */
    void        (*stir)(void);                /* optional */
    uint32_t    (*uniform)(const uint32_t upper_bound); /* optional, a default implementation will be used if NULL */
    void        (*buf)(void * const buf, const size_t size); /* required */
    int         (*close)(void);               /* optional */
} randombytes_implementation;

SODIUM_EXPORT
void randombytes_buf(void * const buf, const size_t size);

SODIUM_EXPORT
uint32_t randombytes_random(void);

SODIUM_EXPORT
uint32_t randombytes_uniform(const uint32_t upper_bound);

SODIUM_EXPORT
void randombytes_stir(void);

SODIUM_EXPORT
int randombytes_close(void);

SODIUM_EXPORT
int randombytes_set_implementation(randombytes_implementation *impl);

SODIUM_EXPORT
const char *randombytes_implementation_name(void);

/* -- NaCl compatibility interface -- */

SODIUM_EXPORT
void randombytes(unsigned char * const buf, const unsigned long long buf_len);

#ifdef __cplusplus
}
#endif

#endif
