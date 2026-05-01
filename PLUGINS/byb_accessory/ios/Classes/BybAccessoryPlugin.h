#import <Flutter/Flutter.h>
#import <ExternalAccessory/ExternalAccessory.h>

@interface BybAccessoryPlugin : NSObject <FlutterPlugin, NSStreamDelegate, FlutterStreamHandler>
{
    int cBufHead;
    int cBufTail;
}

@property NSString *accessoryInfoString;
@property NSMutableString *debugString;

- (bool)isConnected;
- (id)initWithProtocol:(NSString *)protocol;
- (void)queueTxData:(NSData *)data;
- (void)openSessionWithProtocol:(NSString *)protocolString;
- (void)closeSession;

- (void)addDebugString:(NSString *)string;
- (void) setupProtocol;
- (void) reAddExistingAccessory;
@end