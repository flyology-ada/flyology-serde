#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif

#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <time.h>
#include <unistd.h>

_Static_assert(sizeof(dev_t) <= sizeof(uint64_t), "dev_t must fit uint64_t");
_Static_assert(sizeof(ino_t) <= sizeof(uint64_t), "ino_t must fit uint64_t");
_Static_assert(sizeof(off_t) <= sizeof(int64_t), "off_t must fit int64_t");
_Static_assert(sizeof(time_t) <= sizeof(int64_t), "time_t must fit int64_t");
_Static_assert((off_t)-1 < (off_t)0, "off_t must be signed");
_Static_assert((time_t)-1 < (time_t)0, "time_t must be signed");
_Static_assert(_Generic((ssize_t)0, long: 1, default: 0),
               "ssize_t must have the C long type used by Ada");
_Static_assert((ssize_t)-1 < (ssize_t)0, "ssize_t must be signed");

enum {
  FLYOLOGY_SERDE_UNKNOWN_OBJECT = 0,
  FLYOLOGY_SERDE_DIRECTORY_OBJECT = 1,
  FLYOLOGY_SERDE_REGULAR_OBJECT = 2,
  FLYOLOGY_SERDE_OTHER_OBJECT = 3
};

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

int flyology_serde_snapshot_open_directory(const char *path) {
  return open(path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_DIRECTORY);
}

int flyology_serde_snapshot_openat_directory(int parent, const char *name) {
  return openat(parent, name, O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_DIRECTORY);
}

int flyology_serde_snapshot_openat_object(int parent, const char *name) {
  return openat(parent, name,
                O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK | O_NOCTTY);
}

int flyology_serde_snapshot_fstat(int descriptor, uint64_t *device,
                                  uint64_t *inode, int64_t *size,
                                  int64_t *modification_second,
                                  int64_t *modification_nanosecond,
                                  int64_t *change_second,
                                  int64_t *change_nanosecond, int *object_kind) {
  struct stat status;
  int kind = FLYOLOGY_SERDE_OTHER_OBJECT;
  int64_t modification_nsec;
  int64_t change_nsec;

  if (device == NULL || inode == NULL || size == NULL ||
      modification_second == NULL || modification_nanosecond == NULL ||
      change_second == NULL || change_nanosecond == NULL ||
      object_kind == NULL) {
    errno = EINVAL;
    return -1;
  }
  if (fstat(descriptor, &status) != 0) return -1;

  if (S_ISDIR(status.st_mode)) {
    kind = FLYOLOGY_SERDE_DIRECTORY_OBJECT;
  } else if (S_ISREG(status.st_mode)) {
    kind = FLYOLOGY_SERDE_REGULAR_OBJECT;
  }

#if defined(__APPLE__)
  modification_nsec = (int64_t)status.st_mtimespec.tv_nsec;
  change_nsec = (int64_t)status.st_ctimespec.tv_nsec;
#else
  modification_nsec = (int64_t)status.st_mtim.tv_nsec;
  change_nsec = (int64_t)status.st_ctim.tv_nsec;
#endif
  if (modification_nsec < 0 || modification_nsec > 999999999 ||
      change_nsec < 0 || change_nsec > 999999999) {
    errno = EINVAL;
    return -1;
  }

  *device = (uint64_t)status.st_dev;
  *inode = (uint64_t)status.st_ino;
  *size = (int64_t)status.st_size;
#if defined(__APPLE__)
  *modification_second = (int64_t)status.st_mtimespec.tv_sec;
  *change_second = (int64_t)status.st_ctimespec.tv_sec;
#else
  *modification_second = (int64_t)status.st_mtim.tv_sec;
  *change_second = (int64_t)status.st_ctim.tv_sec;
#endif
  *modification_nanosecond = modification_nsec;
  *change_nanosecond = change_nsec;
  *object_kind = kind;
  return 0;
}
