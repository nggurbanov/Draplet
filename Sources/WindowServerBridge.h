#import <Foundation/Foundation.h>
#import "../Vendor/HiddenBar/Engine/Native/HBNativeVisibilityShim.h"

// CGWindowListCreate uses a raw-pointer CFArray and is not imported into Swift.
NSArray<NSNumber *> * _Nullable DrapletOnScreenWindowIDs(void);

#import "../Vendor/Ice/PocketWindowAccess.h"
