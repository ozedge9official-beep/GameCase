// GameCase modification, 2026-11-17. Enumerate only this process's open files.
// F_GETPATH comes from the platform SDK; no copied vnode/stat ABI is needed.
#ifndef LC_CURRENT_PROCESS_FILES_H
#define LC_CURRENT_PROCESS_FILES_H
#include <fcntl.h>
#include <limits.h>
#include <stdint.h>
#include <stdlib.h>
#include <unistd.h>

// libSystem entry point, also available on iOS where libproc.h is not public.
extern int proc_pidinfo(int, int, uint64_t, void *, int);
typedef struct { int32_t descriptor; uint32_t kind; } LCDescriptorEntry;
typedef void (*LCFilePathVisitor)(const char *, void *);

static inline void LCVisitCurrentProcessFilePaths(LCFilePathVisitor visitor, void *context) {
    const int listDescriptors = 1;
    const uint32_t vnodeDescriptor = 1;
    int capacity = proc_pidinfo(getpid(), listDescriptors, 0, NULL, 0);
    if (capacity <= 0 || !visitor) return;
    LCDescriptorEntry *entries = malloc((size_t)capacity);
    if (!entries) return;
    int size = proc_pidinfo(getpid(), listDescriptors, 0, entries, capacity);
    if (size > 0 && size <= capacity) {
        for (size_t i = 0; i < (size_t)size / sizeof(*entries); ++i) {
            if (entries[i].kind != vnodeDescriptor) continue;
            char path[PATH_MAX] = {0};
            // A descriptor may close between enumeration and this call.
            if (fcntl(entries[i].descriptor, F_GETPATH, path) == 0 && path[0]) {
                path[sizeof(path) - 1] = '\0';
                visitor(path, context);
            }
        }
    }
    free(entries);
}
#endif
