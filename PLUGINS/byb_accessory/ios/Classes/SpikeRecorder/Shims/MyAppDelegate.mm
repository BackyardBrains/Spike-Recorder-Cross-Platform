#import "MyAppDelegate.h"
#import "DemoProtocol.h"

@implementation MyAppDelegate

+ (DemoProtocol *)getEaManager {
    static DemoProtocol *eaManager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // Default BYB protocol used by legacy iOS app code paths.
        eaManager = [[DemoProtocol alloc] initWithProtocol:@"com.backyardbrains.protocol"];
    });
    return eaManager;
}

@end
