#import "WindowServerBridge.h"
#import <CoreGraphics/CoreGraphics.h>

NSArray<NSNumber *> *DrapletOnScreenWindowIDs(void) {
    CFArrayRef ids = CGWindowListCreate(kCGWindowListOptionOnScreenOnly, kCGNullWindowID);
    if (!ids) return nil;
    NSMutableArray<NSNumber *> *result = [NSMutableArray arrayWithCapacity:CFArrayGetCount(ids)];
    for (CFIndex i = 0; i < CFArrayGetCount(ids); i++) {
        [result addObject:@((CGWindowID)(uintptr_t)CFArrayGetValueAtIndex(ids, i))];
    }
    CFRelease(ids);
    return result;
}
