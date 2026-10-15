#ifndef RECALLRX_ZSTD_H
#define RECALLRX_ZSTD_H
#include <stddef.h>
/* Returns 0 and a malloc'd buffer on success. Caller frees *outPtr. */
int recallrx_zstd_decompress(const void *src, size_t srcSize, void **outPtr, size_t *outSize, char *err, size_t errLen);
#endif
