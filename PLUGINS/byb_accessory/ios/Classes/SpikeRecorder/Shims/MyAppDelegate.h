#import <Foundation/Foundation.h>

@class DemoProtocol;

@interface MyAppDelegate : NSObject

@property (nonatomic, assign) BOOL shouldReinitializeAudio;

+ (DemoProtocol *)getEaManager;

@end
