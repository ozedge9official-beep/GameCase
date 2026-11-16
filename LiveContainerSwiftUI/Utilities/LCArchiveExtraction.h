#ifndef LCArchiveExtraction_h
#define LCArchiveExtraction_h

#include "archive.h"
#include "archive_entry.h"
#include <limits.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#ifdef __APPLE__
#include <sys/mount.h>
#else
#include <sys/statvfs.h>
#endif

// Return code 2 means capacity was known to be insufficient before any writes.
static int LCArchiveHasSpace(const char *root, int64_t total) {
    uint64_t available;
#ifdef LC_ARCHIVE_TEST_AVAILABLE_BYTES
    (void)root;
    available = LC_ARCHIVE_TEST_AVAILABLE_BYTES;
#else
#ifdef __APPLE__
    struct statfs volume;
    if (statfs(root, &volume)) return 1;
    uint64_t blocks = volume.f_bavail, blockSize = volume.f_bsize;
#else
    struct statvfs volume;
    if (statvfs(root, &volume)) return 1;
    uint64_t blocks = volume.f_bavail, blockSize = volume.f_frsize;
#endif
    if (!blockSize || blocks > UINT64_MAX / blockSize) return 1;
    available = blocks * blockSize;
#endif
    uint64_t bytes = (uint64_t)total;
    uint64_t reserve = bytes / 100;
    if (reserve < (4u << 20)) reserve = 4u << 20;
    return bytes <= UINT64_MAX - reserve && available >= bytes + reserve;
}

// Shared by the iOS wrapper and the portable regression tests.
typedef void (*LCArchiveProgress)(void *context, int64_t total, int64_t completed);

static int LCArchiveRelativePathIsSafe(const char *path) {
    if (!path || !*path || path[0] == '/' || strchr(path, '\\') || strchr(path, ':')) return 0;
    for (const char *p = path; *p;) {
        const char *end = strchr(p, '/');
        size_t length = end ? (size_t)(end - p) : strlen(p);
        if (length == 2 && p[0] == '.' && p[1] == '.') return 0;
        if (!end) break;
        p = end + 1;
    }
    return 1;
}

static int LCArchiveSymlinkIsSafe(const char *name, const char *target) {
    if (!target || !*target || target[0] == '/' || strchr(target, '\\') || strchr(target, ':')) return 0;
    // A relative symlink may use .. only while it stays inside the archive root.
    int depth = 0;
    for (const char *p = name; *p;) {
        const char *end = strchr(p, '/');
        if (!end) break;
        size_t length = (size_t)(end - p);
        if (length && !(length == 1 && p[0] == '.')) depth++;
        p = end + 1;
    }
    for (const char *p = target; *p;) {
        const char *end = strchr(p, '/');
        size_t length = end ? (size_t)(end - p) : strlen(p);
        if (length == 2 && p[0] == '.' && p[1] == '.') {
            if (--depth < 0) return 0;
        } else if (length && !(length == 1 && p[0] == '.')) {
            depth++;
        }
        if (!end) break;
        p = end + 1;
    }
    return 1;
}

static int LCArchiveEntryIsSafe(struct archive_entry *entry) {
    const char *name = archive_entry_pathname(entry);
    if (!LCArchiveRelativePathIsSafe(name)) return 0;
    const char *hardlink = archive_entry_hardlink(entry);
    if (hardlink && !LCArchiveRelativePathIsSafe(hardlink)) return 0;
    const char *symlink = archive_entry_symlink(entry);
    if (symlink && !LCArchiveSymlinkIsSafe(name, symlink)) return 0;
    mode_t type = archive_entry_filetype(entry);
    return type == AE_IFREG || type == AE_IFDIR || type == AE_IFLNK || (hardlink && type == 0);
}

static int LCArchiveJoin(char *output, size_t capacity, const char *root, const char *relative) {
    int count = snprintf(output, capacity, "%s/%s", root, relative);
    return count >= 0 && (size_t)count < capacity;
}

static int LCExtractArchive(const char *source, const char *destination,
                            LCArchiveProgress report, void *context) {
    char root[PATH_MAX];
    struct stat info;
    if (!realpath(destination, root) || stat(root, &info) || !S_ISDIR(info.st_mode)) return 1;
    int64_t total = 0, completed = 0;
    // Validate all headers before writing; keep an accurate total for progress.
    for (int pass = 0; pass < 2; pass++) {
        int failed = 0, status;
        struct archive *reader = archive_read_new();
        struct archive *writer = NULL;
        if (!reader) return 1;
        archive_read_support_format_all(reader);
        archive_read_support_filter_all(reader);
        if (archive_read_open_filename(reader, source, 10240) != ARCHIVE_OK) {
            archive_read_free(reader);
            return 1;
        }
        if (pass == 1) {
            writer = archive_write_disk_new();
            if (!writer) { archive_read_free(reader); return 1; }
            int flags = ARCHIVE_EXTRACT_TIME | ARCHIVE_EXTRACT_PERM |
                ARCHIVE_EXTRACT_SECURE_SYMLINKS | ARCHIVE_EXTRACT_SECURE_NODOTDOT;
            if (archive_write_disk_set_options(writer, flags) != ARCHIVE_OK) failed = 1;
        }
        struct archive_entry *entry;
        while (!failed && (status = archive_read_next_header(reader, &entry)) != ARCHIVE_EOF) {
            if (status != ARCHIVE_OK || !LCArchiveEntryIsSafe(entry)) { failed = 1; break; }
            if (pass == 0) {
                int64_t size = archive_entry_size(entry);
                if (size < 0 || size > INT64_MAX - total) { failed = 1; break; }
                total += size;
                continue;
            }
            char output[PATH_MAX], hardlinkOutput[PATH_MAX];
            if (!LCArchiveJoin(output, sizeof(output), root, archive_entry_pathname(entry))) { failed = 1; break; }
            const char *hardlink = archive_entry_hardlink(entry);
            if (hardlink) {
                if (!LCArchiveJoin(hardlinkOutput, sizeof(hardlinkOutput), root, hardlink)) { failed = 1; break; }
                archive_entry_set_hardlink(entry, hardlinkOutput);
            }
            archive_entry_set_pathname(entry, output);
            if (archive_write_header(writer, entry) != ARCHIVE_OK) { failed = 1; break; }
            const void *buffer;
            size_t size;
            la_int64_t offset;
            while ((status = archive_read_data_block(reader, &buffer, &size, &offset)) != ARCHIVE_EOF) {
                if (status != ARCHIVE_OK || archive_write_data_block(writer, buffer, size, offset) != ARCHIVE_OK) {
                    failed = 1; break;
                }
                completed += (int64_t)size;
                if (report) report(context, total, completed);
            }
            if (!failed && archive_write_finish_entry(writer) != ARCHIVE_OK) failed = 1;
        }
        if (failed) {
            const char *message = writer ? archive_error_string(writer) : NULL;
            if (!message) message = archive_error_string(reader);
            fprintf(stderr, "Archive extraction failed: %s\n", message ? message : "unsafe path or unsupported entry");
        }
        if (archive_read_close(reader) != ARCHIVE_OK) failed = 1;
        archive_read_free(reader);
        if (writer) {
            if (archive_write_close(writer) != ARCHIVE_OK) failed = 1;
            archive_write_free(writer);
        }
        if (failed) return 1;
        if (pass == 0 && !LCArchiveHasSpace(root, total)) return 2;
        if (report) report(context, total, completed);
    }
    return 0;
}
#endif
