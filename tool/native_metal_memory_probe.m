// Profiling only: logical Metal allocations in the current process, not RSS.
#import <Metal/Metal.h>
#include <stdint.h>
uint64_t aurascribe_profile_metal_bytes(void) {
    @autoreleasepool {
        id<MTLDevice> device = MTLCreateSystemDefaultDevice();
        uint64_t bytes = device.currentAllocatedSize;
        [device release];
        return bytes;
    }
}
