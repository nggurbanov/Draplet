// Adapted from Ice Bridging.swift and ScreenCapture.swift, GPL-3.0.
// Modified for Draplet on 2026-10-18: bounded dynamic lookup, isolated captures,
// Objective-C raw-CFArray bridging, and no permanent image-refresh timer.
#import "PocketWindowAccess.h"
#import <dlfcn.h>

NSArray<NSDictionary *> *DrapletPocketWindows(void) {
    typedef int32_t (*Connection)(void);
    typedef CGError (*Count)(int32_t, int32_t, int32_t *);
    typedef CGError (*List)(int32_t, int32_t, int32_t, CGWindowID *, int32_t *);
    Connection connection = (Connection)dlsym(RTLD_DEFAULT, "CGSMainConnectionID");
    Count count = (Count)dlsym(RTLD_DEFAULT, "CGSGetWindowCount");
    List list = (List)dlsym(RTLD_DEFAULT, "CGSGetProcessMenuBarWindowList");
    if (!connection || !count || !list) return @[];
    int32_t capacity = 0, actual = 0;
    if (count(connection(), 0, &capacity) != kCGErrorSuccess || capacity <= 0 || capacity > 65536) return @[];
    CGWindowID *ids = calloc((size_t)capacity, sizeof(CGWindowID));
    if (!ids) return @[];
    CGError error = list(connection(), 0, capacity, ids, &actual);
    if (error != kCGErrorSuccess || actual < 0 || actual > capacity) { free(ids); return @[]; }
    const void **values = calloc((size_t)MAX(actual, 1), sizeof(void *));
    if (!values) { free(ids); return @[]; }
    for (int32_t i = 0; i < actual; i++) values[i] = (const void *)(uintptr_t)ids[i];
    CFArrayRef array = CFArrayCreate(kCFAllocatorDefault, values, actual, NULL);
    NSArray *result = array ? CFBridgingRelease(CGWindowListCreateDescriptionFromArray(array)) : nil;
    if (array) CFRelease(array);
    free(values); free(ids);
    return result ?: @[];
}

CGImageRef DrapletPocketCopyImage(CGWindowID windowID) {
    // Ice uses this API because ScreenCaptureKit cannot capture offscreen menu
    // extras. Look it up at runtime so removal fails open instead of preventing launch.
    typedef CGImageRef (*Capture)(CGRect, CFArrayRef, CGWindowImageOption);
    Capture capture = (Capture)dlsym(RTLD_DEFAULT, "CGWindowListCreateImageFromArray");
    if (!capture) return NULL;
    const void *value = (const void *)(uintptr_t)windowID;
    CFArrayRef array = CFArrayCreate(kCFAllocatorDefault, &value, 1, NULL);
    if (!array) return NULL;
    CGImageRef image = capture(CGRectNull, array, kCGWindowImageBoundsIgnoreFraming | kCGWindowImageBestResolution);
    CFRelease(array);
    return image;
}
