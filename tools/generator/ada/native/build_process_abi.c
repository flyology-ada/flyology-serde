#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif

/*
 * Offline generator subprocess ABI leaves only.
 *
 * Ada owns process and descriptor lifetime, retries, deadlines, charging,
 * capture, status mapping, and publication.  C owns only the mandatory local
 * initialization and destruction of its opaque posix_spawn objects, variadic
 * fcntl calls, host-header macros, and ABI assertions.
 */

#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <signal.h>
#include <spawn.h>
#include <stddef.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

_Static_assert(_Generic((pid_t)0, int: 1, default: 0),
               "pid_t must be exactly C int");
_Static_assert((pid_t)-1 < (pid_t)0, "pid_t must be signed");
_Static_assert(sizeof(pid_t) == sizeof(int), "pid_t size must match C int");
_Static_assert(_Alignof(pid_t) == _Alignof(int),
               "pid_t alignment must match C int");

_Static_assert(_Generic((ssize_t)0, long: 1, default: 0),
               "ssize_t must be exactly C long");
_Static_assert((ssize_t)-1 < (ssize_t)0, "ssize_t must be signed");
_Static_assert(sizeof(ssize_t) == sizeof(long),
               "ssize_t size must match C long");
_Static_assert(_Alignof(ssize_t) == _Alignof(long),
               "ssize_t alignment must match C long");

_Static_assert(_Generic(errno, int: 1, default: 0),
               "errno must have C int type");

int flyology_serde_build_current_errno(void)
{
    return errno;
}

int flyology_serde_build_dupfd_cloexec(int descriptor,
                                       int minimum,
                                       int *replacement)
{
    int candidate;

    if (replacement == NULL) return EINVAL;
#if defined(F_DUPFD_CLOEXEC)
    candidate = fcntl(descriptor, F_DUPFD_CLOEXEC, minimum);
#else
    candidate = fcntl(descriptor, F_DUPFD, minimum);
    if (candidate >= 0 && fcntl(candidate, F_SETFD, FD_CLOEXEC) < 0) {
        int saved = errno;
        (void)close(candidate);
        errno = saved;
        candidate = -1;
    }
#endif
    if (candidate < 0) return errno;
    *replacement = candidate;
    return 0;
}

int flyology_serde_build_set_nonblocking(int descriptor)
{
    int flags = fcntl(descriptor, F_GETFL);

    if (flags < 0) return errno;
    if (fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) < 0) return errno;
    return 0;
}

static void flyology_serde_build_record_cleanup(int result,
                                                int *cleanup_error)
{
    if (*cleanup_error == 0 && result != 0) *cleanup_error = result;
}

int flyology_serde_build_posix_spawn_exact(
  int *pid_output,
  const char *executable,
  char *const arguments[],
  char *const environment[],
  int stdin_source,
  int stdout_source,
  int stderr_source,
  int *cleanup_error_output)
{
    posix_spawn_file_actions_t actions;
    posix_spawnattr_t attributes;
    sigset_t empty_mask;
    sigset_t default_signals;
    pid_t candidate_pid;
    short flags = POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_SETSIGMASK |
                  POSIX_SPAWN_SETSIGDEF;
    int actions_initialized = 0;
    int attributes_initialized = 0;
    int primary = 0;
    int cleanup_error = 0;
    int result;

    if (cleanup_error_output == NULL) return EINVAL;
    *cleanup_error_output = 0;
    if (pid_output == NULL || executable == NULL || executable[0] != '/' ||
        arguments == NULL ||
        environment == NULL || stdin_source <= STDERR_FILENO ||
        stdout_source <= STDERR_FILENO || stderr_source <= STDERR_FILENO ||
        stdin_source == stdout_source || stdin_source == stderr_source ||
        stdout_source == stderr_source) {
        return EINVAL;
    }

    result = posix_spawn_file_actions_init(&actions);
    if (result != 0) {
        primary = result;
        goto finished;
    }
    actions_initialized = 1;

    result = posix_spawnattr_init(&attributes);
    if (result != 0) {
        primary = result;
        goto finished;
    }
    attributes_initialized = 1;

#define FLYOLOGY_SERDE_BUILD_ACTION(call) \
    do {                                  \
        result = (call);                  \
        if (result != 0) {                \
            primary = result;             \
            goto finished;                \
        }                                 \
    } while (0)

    FLYOLOGY_SERDE_BUILD_ACTION(
      posix_spawn_file_actions_adddup2(&actions, stdin_source, STDIN_FILENO));
    FLYOLOGY_SERDE_BUILD_ACTION(
      posix_spawn_file_actions_adddup2(&actions, stdout_source, STDOUT_FILENO));
    FLYOLOGY_SERDE_BUILD_ACTION(
      posix_spawn_file_actions_adddup2(&actions, stderr_source, STDERR_FILENO));
    FLYOLOGY_SERDE_BUILD_ACTION(
      posix_spawn_file_actions_addclose(&actions, stdin_source));
    FLYOLOGY_SERDE_BUILD_ACTION(
      posix_spawn_file_actions_addclose(&actions, stdout_source));
    FLYOLOGY_SERDE_BUILD_ACTION(
      posix_spawn_file_actions_addclose(&actions, stderr_source));

    if (sigemptyset(&empty_mask) != 0 || sigfillset(&default_signals) != 0 ||
        sigdelset(&default_signals, SIGKILL) != 0 ||
        sigdelset(&default_signals, SIGSTOP) != 0) {
        primary = errno;
        goto finished;
    }
    FLYOLOGY_SERDE_BUILD_ACTION(
      posix_spawnattr_setsigmask(&attributes, &empty_mask));
    FLYOLOGY_SERDE_BUILD_ACTION(
      posix_spawnattr_setsigdefault(&attributes, &default_signals));
    FLYOLOGY_SERDE_BUILD_ACTION(posix_spawnattr_setpgroup(&attributes, 0));
    FLYOLOGY_SERDE_BUILD_ACTION(posix_spawnattr_setflags(&attributes, flags));

    primary = posix_spawn(&candidate_pid, executable, &actions, &attributes,
                          arguments, environment);

finished:
    if (attributes_initialized) {
        flyology_serde_build_record_cleanup(
          posix_spawnattr_destroy(&attributes), &cleanup_error);
    }
    if (actions_initialized) {
        flyology_serde_build_record_cleanup(
          posix_spawn_file_actions_destroy(&actions), &cleanup_error);
    }
    *cleanup_error_output = cleanup_error;
    if (primary == 0) *pid_output = candidate_pid;
    return primary;

#undef FLYOLOGY_SERDE_BUILD_ACTION
}

int flyology_serde_build_signal_kill(void) { return SIGKILL; }
int flyology_serde_build_signal_pipe(void) { return SIGPIPE; }
int flyology_serde_build_errno_interrupted(void) { return EINTR; }
int flyology_serde_build_errno_invalid(void) { return EINVAL; }
int flyology_serde_build_errno_would_block(void) { return EAGAIN; }
int flyology_serde_build_errno_no_child(void) { return ECHILD; }
int flyology_serde_build_errno_no_process(void) { return ESRCH; }
int flyology_serde_build_errno_permission(void) { return EPERM; }
int flyology_serde_build_wait_nohang(void) { return WNOHANG; }

int flyology_serde_build_status_exited(int status)
{
    return WIFEXITED(status);
}

int flyology_serde_build_status_exit_code(int status)
{
    return WEXITSTATUS(status);
}

int flyology_serde_build_status_signaled(int status)
{
    return WIFSIGNALED(status);
}

int flyology_serde_build_status_signal(int status)
{
    return WTERMSIG(status);
}

size_t flyology_serde_build_pollfd_size(void) { return sizeof(struct pollfd); }
size_t flyology_serde_build_pollfd_alignment(void)
{
    return _Alignof(struct pollfd);
}
size_t flyology_serde_build_pollfd_fd_offset(void)
{
    return offsetof(struct pollfd, fd);
}
size_t flyology_serde_build_pollfd_events_offset(void)
{
    return offsetof(struct pollfd, events);
}
size_t flyology_serde_build_pollfd_revents_offset(void)
{
    return offsetof(struct pollfd, revents);
}
int flyology_serde_build_poll_input(void) { return POLLIN; }
int flyology_serde_build_poll_output(void) { return POLLOUT; }
int flyology_serde_build_poll_error(void) { return POLLERR; }
int flyology_serde_build_poll_hangup(void) { return POLLHUP; }
int flyology_serde_build_poll_invalid(void) { return POLLNVAL; }
