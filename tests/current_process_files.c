// Verify the real Darwin descriptor API and SDK F_GETPATH on the CI host.
#include "../LiveContainer/Tweaks/LCCurrentProcessFiles.h"
#include <assert.h>
#include <stdio.h>
#include <sys/stat.h>

struct Search { struct stat expected; int found; };
static void visit(const char *path, void *context) {
    struct Search *search = context;
    struct stat actual;
    if (stat(path, &actual) == 0 && actual.st_dev == search->expected.st_dev && actual.st_ino == search->expected.st_ino)
        search->found++;
}
int main(void) {
    char path[] = "/tmp/gamecase-open-file-XXXXXX";
    int fd = mkstemp(path);
    assert(fd >= 0);
    struct Search search = {0};
    assert(fstat(fd, &search.expected) == 0);
    LCVisitCurrentProcessFilePaths(visit, &search);
    assert(search.found > 0);
    close(fd);
    search.found = 0;
    LCVisitCurrentProcessFilePaths(visit, &search);
    assert(search.found == 0);
    unlink(path);
    puts("Current-process file enumeration passed (open and closed descriptors)");
}
