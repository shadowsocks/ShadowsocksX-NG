#include "ConnectivityHTTPTransport.h"
#include <curl/curl.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

struct ConnectivityHTTPCancellation { atomic_bool cancelled; };
static pthread_once_t initialized = PTHREAD_ONCE_INIT;
static void initialize_curl(void) { curl_global_init(CURL_GLOBAL_DEFAULT); }

uint64_t ConnectivityHTTPNow(void) {
  struct timespec time;
  clock_gettime(CLOCK_MONOTONIC, &time);
  return (uint64_t)time.tv_sec * 1000000000ULL + (uint64_t)time.tv_nsec;
}
ConnectivityHTTPCancellation *ConnectivityHTTPCreateCancellation(void) {
  ConnectivityHTTPCancellation *token = malloc(sizeof(*token));
  if (token) atomic_init(&token->cancelled, 0);
  return token;
}
void ConnectivityHTTPCancel(ConnectivityHTTPCancellation *token) {
  if (token) atomic_store(&token->cancelled, 1);
}
void ConnectivityHTTPDestroyCancellation(ConnectivityHTTPCancellation *token) { free(token); }

typedef struct {
  CURL *curl;
  uint64_t started;
  ConnectivityHTTPResult result;
} Measurement;

static size_t headers(char *bytes, size_t size, size_t count, void *opaque) {
  Measurement *measurement = opaque;
  size_t length = size * count;
  if (length == 2 && bytes[0] == '\r' && bytes[1] == '\n') {
    long status = 0;
    curl_easy_getinfo(measurement->curl, CURLINFO_RESPONSE_CODE, &status);
    if (status >= 200 || status == 101) {
      uint64_t elapsed = ConnectivityHTTPNow() - measurement->started;
      measurement->result.status = (int)status;
      measurement->result.milliseconds = (int64_t)(elapsed / 1000000ULL);
      measurement->result.received_headers = elapsed < 5000000000ULL;
      measurement->result.timed_out = !measurement->result.received_headers;
      // Aborting at the empty header line prevents all response-body delivery.
      return 0;
    }
  }
  return length;
}
static size_t discard_body(char *bytes, size_t size, size_t count, void *opaque) {
  (void)bytes; (void)size; (void)count; (void)opaque;
  return 0;
}

ConnectivityHTTPResult ConnectivityHTTPMeasure(const char *url, int proxy_port,
  uint64_t started, ConnectivityHTTPCancellation *token) {
  Measurement measurement = {0};
  measurement.started = started;
  pthread_once(&initialized, initialize_curl);
  CURL *curl = curl_easy_init();
  CURLM *multi = curl_multi_init();
  if (!curl || !multi || !token) goto cleanup;
  measurement.curl = curl;
  char proxy[64];
  snprintf(proxy, sizeof(proxy), "http://127.0.0.1:%d", proxy_port);
  curl_easy_setopt(curl, CURLOPT_URL, url);
  curl_easy_setopt(curl, CURLOPT_PROXY, proxy);
  // Explicitly override environment bypasses, including loopback destinations.
  curl_easy_setopt(curl, CURLOPT_NOPROXY, "");
  curl_easy_setopt(curl, CURLOPT_PROTOCOLS_STR, "http,https");
  curl_easy_setopt(curl, CURLOPT_HTTPGET, 1L);
  curl_easy_setopt(curl, CURLOPT_FOLLOWLOCATION, 0L);
  curl_easy_setopt(curl, CURLOPT_SSL_VERIFYPEER, 1L);
  curl_easy_setopt(curl, CURLOPT_SSL_VERIFYHOST, 2L);
  curl_easy_setopt(curl, CURLOPT_NOSIGNAL, 1L);
  curl_easy_setopt(curl, CURLOPT_TIMEOUT_MS, 5000L);
  curl_easy_setopt(curl, CURLOPT_SUPPRESS_CONNECT_HEADERS, 1L);
  curl_easy_setopt(curl, CURLOPT_HEADERFUNCTION, headers);
  curl_easy_setopt(curl, CURLOPT_HEADERDATA, &measurement);
  curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, discard_body);
  curl_easy_setopt(curl, CURLOPT_FRESH_CONNECT, 1L);
  curl_easy_setopt(curl, CURLOPT_FORBID_REUSE, 1L);
  if (curl_multi_add_handle(multi, curl) != CURLM_OK) goto cleanup;
  int running = 1;
  while (running && !atomic_load(&token->cancelled)) {
    if (ConnectivityHTTPNow() - started >= 5000000000ULL) {
      measurement.result.timed_out = 1;
      break;
    }
    if (curl_multi_perform(multi, &running) != CURLM_OK) break;
    if (!running) break;
    int descriptors = 0;
    if (curl_multi_poll(multi, NULL, 0, 50, &descriptors) != CURLM_OK) break;
  }
  int pending = 0;
  CURLMsg *message;
  while ((message = curl_multi_info_read(multi, &pending))) {
    if (message->msg == CURLMSG_DONE && message->data.result == CURLE_OPERATION_TIMEDOUT)
      measurement.result.timed_out = 1;
  }
  if (atomic_load(&token->cancelled)) measurement.result.received_headers = 0;
  curl_multi_remove_handle(multi, curl);
cleanup:
  if (multi) curl_multi_cleanup(multi);
  if (curl) curl_easy_cleanup(curl);
  return measurement.result;
}
