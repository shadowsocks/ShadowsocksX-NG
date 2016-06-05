#include "ge.h"

void ge_p3_0(ge_p3 *h)
{
  fe_0(h->X);
  fe_1(h->Y);
  fe_1(h->Z);
  fe_0(h->T);
}
