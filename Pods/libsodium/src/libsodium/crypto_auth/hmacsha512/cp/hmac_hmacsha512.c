
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
#include "crypto_auth_hmacsha512.h"
#include "crypto_hash_sha512.h"
#include "utils.h"

#include <sys/types.h>

#include <stdint.h>
#include <string.h>

int
crypto_auth_hmacsha512_init(crypto_auth_hmacsha512_state *state,
                            const unsigned char *key,
                            size_t keylen)
{
    unsigned char pad[128];
    unsigned char khash[64];
    size_t        i;

    if (keylen > 128) {
        crypto_hash_sha512_init(&state->ictx);
        crypto_hash_sha512_update(&state->ictx, key, keylen);
        crypto_hash_sha512_final(&state->ictx, khash);
        key = khash;
        keylen = 64;
    }
    crypto_hash_sha512_init(&state->ictx);
    memset(pad, 0x36, 128);
    for (i = 0; i < keylen; i++) {
        pad[i] ^= key[i];
    }
    crypto_hash_sha512_update(&state->ictx, pad, 128);

    crypto_hash_sha512_init(&state->octx);
    memset(pad, 0x5c, 128);
    for (i = 0; i < keylen; i++) {
        pad[i] ^= key[i];
    }
    crypto_hash_sha512_update(&state->octx, pad, 128);

    sodium_memzero((void *) khash, sizeof khash);

    return 0;
}

int
crypto_auth_hmacsha512_update(crypto_auth_hmacsha512_state *state,
                              const unsigned char *in,
                              unsigned long long inlen)
{
    crypto_hash_sha512_update(&state->ictx, in, inlen);

    return 0;
}

int
crypto_auth_hmacsha512_final(crypto_auth_hmacsha512_state *state,
                             unsigned char *out)
{
    unsigned char ihash[64];

    crypto_hash_sha512_final(&state->ictx, ihash);
    crypto_hash_sha512_update(&state->octx, ihash, 64);
    crypto_hash_sha512_final(&state->octx, out);

    sodium_memzero((void *) ihash, sizeof ihash);

    return 0;
}

int
crypto_auth(unsigned char *out, const unsigned char *in,
            unsigned long long inlen, const unsigned char *k)
{
    crypto_auth_hmacsha512_state state;

    crypto_auth_hmacsha512_init(&state, k, crypto_auth_KEYBYTES);
    crypto_auth_hmacsha512_update(&state, in, inlen);
    crypto_auth_hmacsha512_final(&state, out);

    return 0;
}
