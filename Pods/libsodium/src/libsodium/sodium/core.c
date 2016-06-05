
#include "core.h"
#include "crypto_onetimeauth.h"
#include "randombytes.h"
#include "runtime.h"
#include "utils.h"

static int initialized;

int
sodium_init(void)
{
    if (initialized != 0) {
        return 1;
    }
    sodium_runtime_get_cpu_features();
    if (crypto_onetimeauth_pick_best_implementation() == NULL) {
        return -1; /* LCOV_EXCL_LINE */
    }
    randombytes_stir();
    _sodium_alloc_init();
    initialized = 1;

    return 0;
}
