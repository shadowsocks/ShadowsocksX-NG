
#include <sys/types.h>
#ifndef _WIN32
# include <sys/stat.h>
# include <sys/time.h>
#endif
#ifdef __linux__
# include <sys/syscall.h>
#endif

#include <assert.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#ifndef _WIN32
# include <unistd.h>
#endif

#include "randombytes.h"
#include "randombytes_sysrandom.h"
#include "utils.h"

#ifdef _WIN32
# include <windows.h>
# define RtlGenRandom SystemFunction036
# if defined(__cplusplus)
extern "C"
# endif
BOOLEAN NTAPI RtlGenRandom(PVOID RandomBuffer, ULONG RandomBufferLength);
# pragma comment(lib, "advapi32.lib")
#endif

#ifdef __OpenBSD__

uint32_t
randombytes_sysrandom(void)
{
    return arc4random();
}

void
randombytes_sysrandom_stir(void)
{
}

void
randombytes_sysrandom_buf(void * const buf, const size_t size)
{
    return arc4random_buf(buf, size);
}

int
randombytes_sysrandom_close(void)
{
    return 0;
}

#else /* __OpenBSD__ */

typedef struct SysRandom_ {
    int random_data_source_fd;
    int initialized;
    int getrandom_available;
} SysRandom;

static SysRandom stream = {
    SODIUM_C99(.random_data_source_fd =) -1,
    SODIUM_C99(.initialized =) 0,
    SODIUM_C99(.getrandom_available =) 0
};

#ifndef _WIN32
static ssize_t
safe_read(const int fd, void * const buf_, size_t size)
{
    unsigned char *buf = (unsigned char *) buf_;
    ssize_t        readnb;

    assert(size > (size_t) 0U);
    do {
        while ((readnb = read(fd, buf, size)) < (ssize_t) 0 &&
               (errno == EINTR || errno == EAGAIN)); /* LCOV_EXCL_LINE */
        if (readnb < (ssize_t) 0) {
            return readnb; /* LCOV_EXCL_LINE */
        }
        if (readnb == (ssize_t) 0) {
            break; /* LCOV_EXCL_LINE */
        }
        size -= (size_t) readnb;
        buf += readnb;
    } while (size > (ssize_t) 0);

    return (ssize_t) (buf - (unsigned char *) buf_);
}
#endif

#ifndef _WIN32
static int
randombytes_sysrandom_random_dev_open(void)
{
/* LCOV_EXCL_START */
    struct stat        st;
    static const char *devices[] = {
# ifndef USE_BLOCKING_RANDOM
        "/dev/urandom",
# endif
        "/dev/random", NULL
    };
    const char **      device = devices;
    int                fd;

    do {
        fd = open(*device, O_RDONLY);
        if (fd != -1) {
            if (fstat(fd, &st) == 0 && S_ISCHR(st.st_mode)) {
# if defined(F_SETFD) && defined(FD_CLOEXEC)
                (void) fcntl(fd, F_SETFD, fcntl(fd, F_GETFD) | FD_CLOEXEC);
# endif
                return fd;
            }
            (void) close(fd);
        } else if (errno == EINTR) {
            continue;
        }
        device++;
    } while (*device != NULL);

    errno = EIO;
    return -1;
/* LCOV_EXCL_STOP */
}

# ifdef SYS_getrandom
static int
_randombytes_linux_getrandom(void * const buf, const size_t size)
{
    int readnb;

    assert(size <= 256U);
    do {
        readnb = syscall(SYS_getrandom, buf, (int) size, 0);
    } while (readnb < 0 && (errno == EINTR || errno == EAGAIN));

    return (readnb == (int) size) - 1;
}

static int
randombytes_linux_getrandom(void * const buf_, size_t size)
{
    unsigned char *buf = (unsigned char *) buf_;
    size_t         chunk_size = 256U;

    do {
        if (size < chunk_size) {
            chunk_size = size;
            assert(chunk_size > (size_t) 0U);
        }
        if (_randombytes_linux_getrandom(buf, chunk_size) != 0) {
            return -1;
        }
        size -= chunk_size;
        buf += chunk_size;
    } while (size > (size_t) 0U);

    return 0;
}
# endif

static void
randombytes_sysrandom_init(void)
{
    const int     errno_save = errno;

# ifdef SYS_getrandom
    {
	unsigned char fodder[16];

	if (randombytes_linux_getrandom(fodder, sizeof fodder) == 0) {
	    stream.getrandom_available = 1;
	    errno = errno_save;
	    return;
	}
	stream.getrandom_available = 0;
    }
# endif

    if ((stream.random_data_source_fd =
         randombytes_sysrandom_random_dev_open()) == -1) {
        abort(); /* LCOV_EXCL_LINE */
    }
    errno = errno_save;
}

#else /* _WIN32 */

static void
randombytes_sysrandom_init(void)
{
}
#endif

void
randombytes_sysrandom_stir(void)
{
    if (stream.initialized == 0) {
        randombytes_sysrandom_init();
        stream.initialized = 1;
    }
}

static void
randombytes_sysrandom_stir_if_needed(void)
{
    if (stream.initialized == 0) {
        randombytes_sysrandom_stir();
    }
}

int
randombytes_sysrandom_close(void)
{
    int ret = -1;

#ifndef _WIN32
    if (stream.random_data_source_fd != -1 &&
        close(stream.random_data_source_fd) == 0) {
        stream.random_data_source_fd = -1;
        stream.initialized = 0;
        ret = 0;
    }
# ifdef SYS_getrandom
    if (stream.getrandom_available != 0) {
        ret = 0;
    }
# endif
#else /* _WIN32 */
    if (stream.initialized != 0) {
        stream.initialized = 0;
        ret = 0;
    }
#endif
    return ret;
}

uint32_t
randombytes_sysrandom(void)
{
    uint32_t r;

    randombytes_sysrandom_buf(&r, sizeof r);

    return r;
}

void
randombytes_sysrandom_buf(void * const buf, const size_t size)
{
    randombytes_sysrandom_stir_if_needed();
#ifdef ULONG_LONG_MAX
    /* coverity[result_independent_of_operands] */
    assert(size <= ULONG_LONG_MAX);
#endif
#ifndef _WIN32
# ifdef SYS_getrandom
    if (stream.getrandom_available != 0) {
        if (randombytes_linux_getrandom(buf, size) != 0) {
            abort();
        }
        return;
    }
# endif
    if (stream.random_data_source_fd == -1 ||
        safe_read(stream.random_data_source_fd, buf, size) != (ssize_t) size) {
        abort(); /* LCOV_EXCL_LINE */
    }
#else
    if (size > (size_t) 0xffffffff) {
        abort(); /* LCOV_EXCL_LINE */
    }
    if (! RtlGenRandom((PVOID) buf, (ULONG) size)) {
        abort(); /* LCOV_EXCL_LINE */
    }
#endif
}

#endif /* __OpenBSD__ */

const char *
randombytes_sysrandom_implementation_name(void)
{
    return "sysrandom";
}

struct randombytes_implementation randombytes_sysrandom_implementation = {
    SODIUM_C99(.implementation_name =) randombytes_sysrandom_implementation_name,
    SODIUM_C99(.random =) randombytes_sysrandom,
    SODIUM_C99(.stir =) randombytes_sysrandom_stir,
    SODIUM_C99(.uniform =) NULL,
    SODIUM_C99(.buf =) randombytes_sysrandom_buf,
    SODIUM_C99(.close =) randombytes_sysrandom_close
};
