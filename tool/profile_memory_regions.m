// Read-only region accounting for a supplied local app PID. No memory contents.
#import <Foundation/Foundation.h>
#include <libproc.h>
#include <unistd.h>

int main(int argc, const char **argv) {
    @autoreleasepool {
        if (argc != 2) return 2;
        pid_t pid = (pid_t)atoi(argv[1]);
        uint64_t address = 0, page = (uint64_t)getpagesize();
        NSMutableDictionary *categories = [NSMutableDictionary dictionary];
        unsigned count = 0;
        for (; count < 100000; ++count) {
            struct proc_regionwithpathinfo info = {0};
            int size = proc_pidinfo(pid, PROC_PIDREGIONPATHINFO, address, &info, sizeof(info));
            if (size != sizeof(info)) break;
            struct proc_regioninfo r = info.prp_prinfo;
            NSString *path = [NSString stringWithUTF8String:info.prp_vip.vip_path] ?: @"";
            NSString *key = [path hasSuffix:@".gguf"] ? @"model_file" :
                ([path containsString:@"FlutterMacOS.framework"] ? @"flutter_engine_file" :
                 ([path containsString:@"App.framework"] ? @"dart_app_file" :
                  (path.length ? @"other_file_mappings" : @"anonymous_or_shared_regions")));
            NSMutableDictionary *row = categories[key];
            if (!row) {
                row = [@{@"regions":@0, @"virtualBytes":@0, @"residentBytes":@0,
                          @"privateResidentBytes":@0, @"swappedBytes":@0} mutableCopy];
                categories[key] = row;
            }
            row[@"regions"] = @([row[@"regions"] unsignedLongLongValue] + 1);
            row[@"virtualBytes"] = @([row[@"virtualBytes"] unsignedLongLongValue] + r.pri_size);
            row[@"residentBytes"] = @([row[@"residentBytes"] unsignedLongLongValue] + r.pri_pages_resident * page);
            row[@"privateResidentBytes"] = @([row[@"privateResidentBytes"] unsignedLongLongValue] + r.pri_private_pages_resident * page);
            row[@"swappedBytes"] = @([row[@"swappedBytes"] unsignedLongLongValue] + r.pri_pages_swapped_out * page);
            uint64_t next = r.pri_address + r.pri_size;
            if (next <= address) break;
            address = next;
        }
        NSDictionary *out = @{@"pid":@(pid), @"regions":@(count), @"pageBytes":@(page), @"categories":categories};
        NSData *json = [NSJSONSerialization dataWithJSONObject:out options:NSJSONWritingPrettyPrinted error:nil];
        fwrite(json.bytes, 1, json.length, stdout); puts("");
        return count ? 0 : 1;
    }
}
