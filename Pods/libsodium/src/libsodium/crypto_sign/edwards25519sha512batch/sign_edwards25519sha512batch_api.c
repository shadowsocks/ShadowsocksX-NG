#include "crypto_sign_edwards25519sha512batch.h"

size_t
crypto_sign_edwards25519sha512batch_bytes(void) {
    return crypto_sign_edwards25519sha512batch_BYTES;
}

size_t
crypto_sign_edwards25519sha512batch_publickeybytes(void) {
    return crypto_sign_edwards25519sha512batch_PUBLICKEYBYTES;
}

size_t
crypto_sign_edwards25519sha512batch_secretkeybytes(void) {
    return crypto_sign_edwards25519sha512batch_SECRETKEYBYTES;
}
