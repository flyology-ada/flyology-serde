#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif

#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stddef.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static struct sigaction saved_action;
static struct sigaction saved_sigchld_action;
static sigset_t saved_mask;
static int active;
static int sigchld_active;

extern int flyology_serde_build_dupfd_cloexec(int, int, int *);
extern int flyology_serde_build_sigchld_disposition(int *, int *);
extern int flyology_serde_build_peek_child(int, int *, int *, int *, int *);
extern int flyology_serde_build_posix_spawn_exact(
  int *, const char *, char *const [], char *const [], int, int, int, int *);

int flyology_serde_test_null_build_outputs(void)
{
    if (flyology_serde_build_dupfd_cloexec(-1, 3, NULL) != EINVAL) return 1;
    if (flyology_serde_build_posix_spawn_exact(
          NULL, NULL, NULL, NULL, -1, -1, -1, NULL) != EINVAL)
        return 2;
    if (flyology_serde_build_sigchld_disposition(NULL, NULL) != EINVAL)
        return 3;
    if (flyology_serde_build_peek_child(-1, NULL, NULL, NULL, NULL) != EINVAL)
        return 4;
    return 0;
}

int flyology_serde_test_create_private_directory(char *path, size_t capacity)
{
    static const char pattern[] = "/tmp/flyology-serde-runner.XXXXXX";

    if (path == NULL || capacity < sizeof(pattern)) return EINVAL;
    (void)memcpy(path, pattern, sizeof(pattern));
    return mkdtemp(path) == NULL ? errno : 0;
}

int flyology_serde_test_remove_private_directory(const char *path)
{
    if (path == NULL) return EINVAL;
    return rmdir(path) == 0 ? 0 : errno;
}

int flyology_serde_test_descriptor_is_closed(int descriptor)
{
    if (descriptor < 0) return 0;
    errno = 0;
    if (fcntl(descriptor, F_GETFD) >= 0) return 0;
    return errno == EBADF ? 1 : 0;
}

int flyology_serde_test_deviate_sigpipe(void)
{
    struct sigaction ignored;
    sigset_t blocked;
    int result;

    if (active) return EALREADY;
    if (sigprocmask(SIG_SETMASK, NULL, &saved_mask) != 0) return errno;
    if (sigaction(SIGPIPE, NULL, &saved_action) != 0) return errno;

    ignored.sa_handler = SIG_IGN;
    (void)sigemptyset(&ignored.sa_mask);
    ignored.sa_flags = 0;
    if (sigaction(SIGPIPE, &ignored, NULL) != 0) return errno;

    (void)sigemptyset(&blocked);
    (void)sigaddset(&blocked, SIGPIPE);
    result = sigprocmask(SIG_BLOCK, &blocked, NULL);
    if (result != 0) {
        int saved = errno;
        (void)sigaction(SIGPIPE, &saved_action, NULL);
        errno = saved;
        return saved;
    }
    active = 1;
    return 0;
}

int flyology_serde_test_restore_sigpipe(void)
{
    int first = 0;

    if (!active) return EINVAL;
    if (sigaction(SIGPIPE, &saved_action, NULL) != 0) first = errno;
    if (sigprocmask(SIG_SETMASK, &saved_mask, NULL) != 0 && first == 0)
        first = errno;
    active = 0;
    return first;
}

int flyology_serde_test_deviate_sigchld_ignored(void)
{
    struct sigaction ignored;

    if (sigchld_active) return EALREADY;
    if (sigaction(SIGCHLD, NULL, &saved_sigchld_action) != 0) return errno;
    ignored.sa_handler = SIG_IGN;
    (void)sigemptyset(&ignored.sa_mask);
    ignored.sa_flags = 0;
    if (sigaction(SIGCHLD, &ignored, NULL) != 0) return errno;
    sigchld_active = 1;
    return 0;
}

int flyology_serde_test_deviate_sigchld_no_child_wait(void)
{
#if defined(SA_NOCLDWAIT)
    struct sigaction disposition;

    if (sigchld_active) return EALREADY;
    if (sigaction(SIGCHLD, NULL, &saved_sigchld_action) != 0) return errno;
    disposition = saved_sigchld_action;
    disposition.sa_flags |= SA_NOCLDWAIT;
    if (sigaction(SIGCHLD, &disposition, NULL) != 0) return errno;
    sigchld_active = 1;
    return 0;
#else
    return -1;
#endif
}

int flyology_serde_test_restore_sigchld(void)
{
    int result;

    if (!sigchld_active) return EINVAL;
    result = sigaction(SIGCHLD, &saved_sigchld_action, NULL);
    sigchld_active = 0;
    return result == 0 ? 0 : errno;
}
