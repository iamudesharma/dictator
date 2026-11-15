#include <stdint.h>
// Reads a bounded mono PCM16 slice into caller-owned float storage.
// Returns 0 on success, 1 for silence, -1 for invalid bounds, -2 for I/O failure.
int aurascribe_pcm_read(const char *path, int64_t byte_offset, int32_t count,
                       float *output, int32_t skip_silence);
