#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif

#include <errno.h>
#include <signal.h>
#include <stddef.h>

static struct sigaction saved_action;
static sigset_t saved_mask;
static int active;

extern int flyology_serde_build_dupfd_cloexec(int, int, int *);
extern int flyology_serde_build_posix_spawn_exact(
  int *, const char *, char *const [], char *const [], int, int, int, int *);

int flyology_serde_test_null_build_outputs(void)
{
    if (flyology_serde_build_dupfd_cloexec(-1, 3, NULL) != EINVAL) return 1;
    if (flyology_serde_build_posix_spawn_exact(
          NULL, NULL, NULL, NULL, -1, -1, -1, NULL) != EINVAL)
        return 2;
    return 0;
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
