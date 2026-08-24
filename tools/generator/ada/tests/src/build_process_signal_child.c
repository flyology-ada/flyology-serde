#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif

#include <signal.h>
#include <stddef.h>

int main(void)
{
    struct sigaction action;
    sigset_t mask;

    if (sigaction(SIGPIPE, NULL, &action) != 0) return 10;
    if (sigprocmask(SIG_SETMASK, NULL, &mask) != 0) return 11;
    if (action.sa_handler != SIG_DFL) return 12;
    if (sigismember(&mask, SIGPIPE) != 0) return 13;
    return 0;
}
