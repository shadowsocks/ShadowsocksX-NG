#include "ConnectivityHTTPTransport.h"
#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <time.h>
#include <unistd.h>

struct ConnectivityHTTPCancellation { atomic_bool cancelled; };

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

static double milliseconds(uint64_t end, uint64_t start) {
  return (double)(end - start) / 1000000.0;
}

/* Every wait shares one monotonic deadline. Cancellation is checked at most
   25 ms apart, including peers that accept but never read or send anything. */
static int ready(int fd, short events, uint64_t deadline, ConnectivityHTTPCancellation *token) {
  while (!atomic_load(&token->cancelled)) {
    uint64_t now = ConnectivityHTTPNow();
    if (now >= deadline) return 0;
    uint64_t remaining = (deadline - now + 999999ULL) / 1000000ULL;
    int timeout = remaining > 25 ? 25 : (int)remaining;
    struct pollfd descriptor = { .fd = fd, .events = events };
    int result = poll(&descriptor, 1, timeout);
    if (result > 0) return 1; /* recv / SO_ERROR also handle HUP and ERR. */
    if (result < 0 && errno != EINTR) return 0;
  }
  return 0;
}

/* Only HTTP/1.x final headers are accepted. The cumulative header budget also
   bounds arbitrarily many informational responses; bodies are never awaited. */
static int response_status(const char *bytes, size_t length) {
  if (length < 16 ||
      (memcmp(bytes, "HTTP/1.1 ", 9) && memcmp(bytes, "HTTP/1.0 ", 9))) return -1;
  for (int i = 9; i < 12; i++) if (bytes[i] < '0' || bytes[i] > '9') return -1;
  if (bytes[12] != ' ' && bytes[12] != '\r') return -1;
  int status = (bytes[9] - '0') * 100 + (bytes[10] - '0') * 10 + bytes[11] - '0';
  if (status < 100 || status > 599) return -1;
  const char *end = bytes + length;
  const char *line = memmem(bytes, length, "\r\n", 2);
  if (!line) return -1;
  line += 2;
  while (line < end - 2) {
    const char *next = memmem(line, (size_t)(end - line), "\r\n", 2);
    if (!next || next == line || !memchr(line, ':', (size_t)(next - line))) return -1;
    for (const char *p = line; p < next; p++) {
      if ((unsigned char)*p < 32 && *p != '\t') return -1;
    }
    line = next + 2;
  }
  return status;
}

ConnectivityHTTPResult ConnectivityHTTPProbe(const char *request, int proxy_port,
  int timeout_ms, ConnectivityHTTPCancellation *token) {
  return ConnectivityHTTPProbeWithReader(request, proxy_port, timeout_ms, token, NULL, NULL);
}

ConnectivityHTTPResult ConnectivityHTTPProbeWithReader(const char *request, int proxy_port,
  int timeout_ms, ConnectivityHTTPCancellation *token, ConnectivityHTTPReader reader, void *context) {
  ConnectivityHTTPResult result = { .stage = 1, .local_tcp_ms = -1, .send_ms = -1,
    .first_byte_ms = -1, .headers_ms = -1 };
  int fd = -1;
  uint64_t started = ConnectivityHTTPNow();
  uint64_t deadline = started + (uint64_t)(timeout_ms > 0 ? timeout_ms : 0) * 1000000ULL;
  if (!token || !request || proxy_port < 1 || proxy_port > 65535) goto cleanup;
  fd = socket(AF_INET, SOCK_STREAM, 0);
  if (fd < 0) goto cleanup;
  int one = 1;
  setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, sizeof(one));
  if (fcntl(fd, F_SETFL, O_NONBLOCK) < 0) goto cleanup;
  struct sockaddr_in address = { .sin_family = AF_INET,
    .sin_port = htons((uint16_t)proxy_port), .sin_addr.s_addr = htonl(INADDR_LOOPBACK) };
  if (connect(fd, (struct sockaddr *)&address, sizeof(address)) < 0 && errno != EINPROGRESS)
    goto cleanup;
  if (!ready(fd, POLLOUT, deadline, token)) goto cleanup;
  int error = 0;
  socklen_t size = sizeof(error);
  if (getsockopt(fd, SOL_SOCKET, SO_ERROR, &error, &size) || error) goto cleanup;
  uint64_t connected = ConnectivityHTTPNow();
  result.local_tcp_ms = milliseconds(connected, started);
  result.stage = 2;
  size_t length = strlen(request), offset = 0;
  while (offset < length) {
    if (!ready(fd, POLLOUT, deadline, token)) goto cleanup;
    ssize_t sent = send(fd, request + offset, length - offset, 0);
    if (sent > 0) offset += (size_t)sent;
    else if (sent == 0 || (errno != EAGAIN && errno != EWOULDBLOCK && errno != EINTR)) goto cleanup;
  }
  uint64_t sent = ConnectivityHTTPNow(), first = 0;
  result.send_ms = milliseconds(sent, connected);
  result.stage = 3;
  char bytes[65536];
  size_t used = 0, consumed = 0, cumulative = 0;
  while (used < sizeof(bytes)) {
    if (!ready(fd, POLLIN, deadline, token)) goto cleanup;
    ssize_t count = reader ? reader(bytes + used, sizeof(bytes) - used, context)
      : recv(fd, bytes + used, sizeof(bytes) - used, 0);
    if (count <= 0) {
      if (count < 0 && (errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR)) continue;
      goto cleanup;
    }
    if (!first) {
      first = ConnectivityHTTPNow();
      result.first_byte_ms = milliseconds(first, sent);
      result.stage = 4;
    }
    used += (size_t)count;
    const char *end;
    while ((end = memmem(bytes + consumed, used - consumed, "\r\n\r\n", 4))) {
      size_t header_length = (size_t)(end - (bytes + consumed)) + 4;
      if (cumulative + consumed + header_length > sizeof(bytes)) goto cleanup;
      int status = response_status(bytes + consumed, header_length);
      if (status < 0) goto cleanup;
      consumed += header_length;
      if (status >= 200 || status == 101) {
        uint64_t finished = ConnectivityHTTPNow();
        result.status = status;
        result.headers_ms = milliseconds(finished, first);
        result.received_headers = finished < deadline && !atomic_load(&token->cancelled);
        if (result.received_headers) result.stage = 5;
        goto cleanup;
      }
    }
    cumulative += consumed;
    if (cumulative + used - consumed >= sizeof(bytes)) goto cleanup;
    if (consumed) {
      memmove(bytes, bytes + consumed, used - consumed);
      used -= consumed;
      consumed = 0;
    }
  }
cleanup:
  result.milliseconds = milliseconds(ConnectivityHTTPNow(), started);
  result.timed_out = !result.received_headers && ConnectivityHTTPNow() >= deadline;
  if (fd >= 0) close(fd);
  return result;
}
