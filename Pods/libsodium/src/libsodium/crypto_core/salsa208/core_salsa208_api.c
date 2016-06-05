#include "crypto_core_salsa208.h"

size_t
crypto_core_salsa208_outputbytes(void) {
    return crypto_core_salsa208_OUTPUTBYTES;
}

size_t
crypto_core_salsa208_inputbytes(void) {
    return crypto_core_salsa208_INPUTBYTES;
}

size_t
crypto_core_salsa208_keybytes(void) {
    return crypto_core_salsa208_KEYBYTES;
}

size_t
crypto_core_salsa208_constbytes(void) {
    return crypto_core_salsa208_CONSTBYTES;
}
