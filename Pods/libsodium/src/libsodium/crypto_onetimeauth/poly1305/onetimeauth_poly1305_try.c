
#include <stdlib.h>
#include <string.h>
#include "crypto_onetimeauth.h"
#include "crypto_onetimeauth_poly1305.h"
#include "utils.h"
#include "donna/poly1305_donna.h"

crypto_onetimeauth_poly1305_implementation *
crypto_onetimeauth_pick_best_implementation(void)
{
    return &crypto_onetimeauth_poly1305_donna_implementation;
}
