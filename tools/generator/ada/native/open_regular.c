#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif

#include <fcntl.h>
#include <sys/stat.h>

/* Header-dependent constants and struct stat inspection stay in these ABI leaves. */
int flyology_serde_open_nofollow(const char *path) {
  return open(path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK);
}

int flyology_serde_is_regular(int descriptor) {
  struct stat status;

  if (fstat(descriptor, &status) != 0) {
    return -1;
  }
  return S_ISREG(status.st_mode) ? 1 : 0;
}
