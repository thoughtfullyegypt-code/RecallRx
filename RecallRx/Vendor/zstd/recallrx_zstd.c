#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "zstddeclib.c"

#define RX_ZSTD_CONTENTSIZE_UNKNOWN (0ULL - 1)
#define RX_ZSTD_CONTENTSIZE_ERROR (0ULL - 2)

static void rx_set_err(char *err, size_t errLen, const char *msg) {
    if (!err || errLen == 0) return;
    snprintf(err, errLen, "%s", msg);
}

int recallrx_zstd_decompress(const void *src, size_t srcSize, void **outPtr, size_t *outSize, char *err, size_t errLen) {
    if (!src || !outPtr || !outSize || srcSize < 4) {
        rx_set_err(err, errLen, "Not a zstd frame.");
        return 1;
    }
    const unsigned char *bytes = (const unsigned char *)src;
    if (!(bytes[0] == 0x28 && bytes[1] == 0xB5 && bytes[2] == 0x2F && bytes[3] == 0xFD)) {
        rx_set_err(err, errLen, "collection.anki21b is not a zstd frame.");
        return 1;
    }

    unsigned long long frame = ZSTD_getFrameContentSize(src, srcSize);
    if (frame != RX_ZSTD_CONTENTSIZE_UNKNOWN && frame != RX_ZSTD_CONTENTSIZE_ERROR && frame > 0 && frame < (1ULL << 32)) {
        void *dst = malloc((size_t)frame);
        if (!dst) {
            rx_set_err(err, errLen, "Out of memory.");
            return 1;
        }
        size_t got = ZSTD_decompress(dst, (size_t)frame, src, srcSize);
        if (ZSTD_isError(got) || got != (size_t)frame) {
            free(dst);
            rx_set_err(err, errLen, "Could not decompress collection.anki21b.");
            return 1;
        }
        *outPtr = dst;
        *outSize = got;
        return 0;
    }

    ZSTD_DCtx *ctx = ZSTD_createDCtx();
    if (!ctx) {
        rx_set_err(err, errLen, "Out of memory.");
        return 1;
    }
    size_t cap = srcSize * 8 + 65536;
    unsigned char *dst = malloc(cap);
    if (!dst) {
        ZSTD_freeDCtx(ctx);
        rx_set_err(err, errLen, "Out of memory.");
        return 1;
    }
    ZSTD_inBuffer input = { src, srcSize, 0 };
    size_t produced = 0;
    while (input.pos < input.size) {
        if (produced == cap) {
            size_t next = cap * 2;
            unsigned char *grown = realloc(dst, next);
            if (!grown) {
                free(dst);
                ZSTD_freeDCtx(ctx);
                rx_set_err(err, errLen, "Out of memory.");
                return 1;
            }
            dst = grown;
            cap = next;
        }
        ZSTD_outBuffer output = { dst + produced, cap - produced, 0 };
        size_t ret = ZSTD_decompressStream(ctx, &output, &input);
        if (ZSTD_isError(ret)) {
            free(dst);
            ZSTD_freeDCtx(ctx);
            rx_set_err(err, errLen, "Could not decompress collection.anki21b.");
            return 1;
        }
        produced += output.pos;
        if (ret == 0) break;
        if (output.pos == 0) {
            free(dst);
            ZSTD_freeDCtx(ctx);
            rx_set_err(err, errLen, "zstd made no progress.");
            return 1;
        }
    }
    ZSTD_freeDCtx(ctx);
    *outPtr = dst;
    *outSize = produced;
    return 0;
}
