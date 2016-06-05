#include "crypto_core_salsa20.h"

size_t
crypto_core_salsa20_outputbytes(void) {
    return crypto_core_salsa20_OUTPUTBYTES;
}

size_t
crypto_core_salsa20_inputbytes(void) {
    return crypto_core_salsa20_INPUTBYTES;
}

size_t
crypto_core_salsa20_keybytes(void) {
    return crypto_core_salsa20_KEYBYTES;
}

size_t
crypto_core_salsa20_constbytes(void) {
    return crypto_core_salsa20_CONSTBYTES;
}
