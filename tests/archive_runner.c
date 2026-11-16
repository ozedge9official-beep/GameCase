#include "LCArchiveExtraction.h"
#include <locale.h>
int main(int argc, char **argv) {
    setlocale(LC_ALL, "");
    if (argc != 3) return 2;
    return LCExtractArchive(argv[1], argv[2], NULL, NULL);
}
