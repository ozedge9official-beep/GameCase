#import "unarchive.h"
#include "LCArchiveExtraction.h"

static void reportArchiveProgress(void *context, int64_t total, int64_t completed) {
    NSProgress *progress = (__bridge NSProgress *)context;
    progress.totalUnitCount = total;
    progress.completedUnitCount = completed;
}

int extract(NSString *fileToExtract, NSString *extractionPath, NSProgress *progress) {
    return LCExtractArchive(fileToExtract.fileSystemRepresentation,
                            extractionPath.fileSystemRepresentation,
                            reportArchiveProgress, (__bridge void *)progress);
}
