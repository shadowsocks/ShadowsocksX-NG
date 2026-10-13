#ifndef ConnectivityHTTPTransport_h
#define ConnectivityHTTPTransport_h
#include <stdint.h>

typedef struct ConnectivityHTTPCancellation ConnectivityHTTPCancellation;
typedef struct {
  int status;
  int64_t milliseconds;
  int timed_out;
  int received_headers;
} ConnectivityHTTPResult;
ConnectivityHTTPCancellation *ConnectivityHTTPCreateCancellation(void);
void ConnectivityHTTPCancel(ConnectivityHTTPCancellation *token);
void ConnectivityHTTPDestroyCancellation(ConnectivityHTTPCancellation *token);
uint64_t ConnectivityHTTPNow(void);
ConnectivityHTTPResult ConnectivityHTTPMeasure(const char *url, int proxy_port,
  uint64_t started, ConnectivityHTTPCancellation *token);
#endif
