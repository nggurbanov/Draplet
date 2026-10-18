// Adapted from Ice, Jordan Baird and contributors, GPL-3.0.
// See Vendor/Ice/ORIGIN.md for upstream revision and local changes.
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
NS_ASSUME_NONNULL_BEGIN
NSArray<NSDictionary *> *DrapletPocketWindows(void);
CGImageRef _Nullable DrapletPocketCopyImage(CGWindowID windowID) CF_RETURNS_RETAINED;
NS_ASSUME_NONNULL_END
