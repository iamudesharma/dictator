#include "pcm_reader.h"
#include <stdio.h>
#include <stdlib.h>

int aurascribe_pcm_read(const char *path, int64_t byte_offset, int32_t count,
                       float *output, int32_t skip_silence) {
    if (!path || !output || byte_offset < 0 || count <= 0 || count > 400000) return -1;
    FILE *file = fopen(path, "rb");
    if (!file) return -2;
    // Native temporary storage never enters the Dart heap and is freed before decode.
    int16_t *pcm = malloc((size_t)count * sizeof(int16_t));
    if (!pcm) { fclose(file); return -2; }
    int ok = fseeko(file, byte_offset, SEEK_SET) == 0 &&
             fread(pcm, sizeof(int16_t), (size_t)count, file) == (size_t)count;
    fclose(file);
    if (!ok) { free(pcm); return -2; }
    uint64_t energy = 0;
    if (skip_silence) {
        for (int32_t i = 0; i < count; ++i) {
            int64_t value = pcm[i];
            energy += (uint64_t)(value * value);
            output[i] = (float)pcm[i] * (1.0f / 32768.0f);
        }
    } else {
        for (int32_t i = 0; i < count; ++i)
            output[i] = (float)pcm[i] * (1.0f / 32768.0f);
    }
    free(pcm);
    // PCM squares sum exactly in the previous Dart double loop at this bound.
    // Integer accumulation preserves its gate without float reduction error.
    return skip_silence && (double)energy / ((double)count * 1073741824.0) < 0.000003 ? 1 : 0;
}
