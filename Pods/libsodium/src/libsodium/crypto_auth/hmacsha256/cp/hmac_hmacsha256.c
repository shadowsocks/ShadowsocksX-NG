
/*-
 * Copyright 2005,2007,2009 Colin Percival
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 *
 */

#include "api.h"
#include "crypto_auth_hmacsha256.h"
#include "crypto_hash_sha256.h"
#include "utils.h"

#include <sys/types.h>

#include <stdint.h>
#include <string.h>

int
crypto_auth_hmacsha256_init(crypto_auth_hmacsha256_state *state,
                            const unsigned char *key,
                            size_t keylen)
{
    unsigned char pad[64];
    unsigned char khash[32];
    size_t        i;

    if (keylen > 64) {
        crypto_hash_sha256_init(&state->ictx);
        crypto_hash_sha256_update(&state->ictx, key, keylen);
        crypto_hash_sha256_final(&state->ictx, khash);
        key = khash;
        keylen = 32;
    }
    crypto_hash_sha256_init(&state->ictx);
    memset(pad, 0x36, 64);
    for (i = 0; i < keylen; i++) {
        pad[i] ^= key[i];
    }
    crypto_hash_sha256_update(&state->ictx, pad, 64);

    crypto_hash_sha256_init(&state->octx);
    memset(pad, 0x5c, 64);
    for (i = 0; i < keylen; i++) {
        pad[i] ^= key[i];
    }
    crypto_hash_sha256_update(&state->octx, pad, 64);

    sodium_memzero((void *) khash, sizeof khash);

    return 0;
}

int
crypto_auth_hmacsha256_update(crypto_auth_hmacsha256_state *state,
                              const unsigned char *in,
                              unsigned long long inlen)
{
    crypto_hash_sha256_update(&state->ictx, in, inlen);

    return 0;
}

int
crypto_auth_hmacsha256_final(crypto_auth_hmacsha256_state *state,
                             unsigned char *out)
{
    unsigned char ihash[32];

    crypto_hash_sha256_final(&state->ictx, ihash);
    crypto_hash_sha256_update(&state->octx, ihash, 32);
    crypto_hash_sha256_final(&state->octx, out);

    sodium_memzero((void *) ihash, sizeof ihash);

    return 0;
}

int
crypto_auth(unsigned char *out, const unsigned char *in,
            unsigned long long inlen, const unsigned char *k)
{
    crypto_auth_hmacsha256_state state;

    crypto_auth_hmacsha256_init(&state, k, crypto_auth_KEYBYTES);
    crypto_auth_hmacsha256_update(&state, in, inlen);
    crypto_auth_hmacsha256_final(&state, out);

    return 0;
}
