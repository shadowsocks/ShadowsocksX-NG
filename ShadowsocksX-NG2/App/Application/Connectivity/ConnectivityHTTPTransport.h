#ifndef ConnectivityHTTPTransport_h
#define ConnectivityHTTPTransport_h
#include <stdint.h>
#include <sys/types.h>

typedef struct ConnectivityHTTPCancellation ConnectivityHTTPCancellation;
typedef struct {
  int status;
  int timed_out;
  int received_headers;
  int stage; /* 1: local TCP, 2: send, 3: first byte, 4: headers, 5: complete */
  double milliseconds;
  double local_tcp_ms;
  double send_ms;
  double first_byte_ms;
  double headers_ms;
} ConnectivityHTTPResult;
ConnectivityHTTPCancellation *ConnectivityHTTPCreateCancellation(void);
void ConnectivityHTTPCancel(ConnectivityHTTPCancellation *token);
void ConnectivityHTTPDestroyCancellation(ConnectivityHTTPCancellation *token);
uint64_t ConnectivityHTTPNow(void);
ConnectivityHTTPResult ConnectivityHTTPProbe(const char *request, int proxy_port,
  int timeout_ms, ConnectivityHTTPCancellation *token);
/* A reader override makes response fragmentation independent of TCP packet boundaries. */
typedef ssize_t (*ConnectivityHTTPReader)(void *buffer, size_t capacity, void *context);
ConnectivityHTTPResult ConnectivityHTTPProbeWithReader(const char *request, int proxy_port,
  int timeout_ms, ConnectivityHTTPCancellation *token, ConnectivityHTTPReader reader, void *context);
#endif
