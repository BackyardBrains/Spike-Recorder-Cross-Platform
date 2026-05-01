#import "BybAccessoryPlugin.h"
#import "SpikeRecorder/Audio/BBAudioManager.h"

@interface BybAccessoryPlugin ()
- (void)connectToAccessory:(NSString *)name;
/// Call only on main thread; uses NSRunLoop main for stream scheduling teardown.
- (void)tearDownExistingSessionAssumeMainThread;
@end

@implementation BybAccessoryPlugin {
    EASession *_session;
    NSString *_protocol;
    NSMutableData *_txData;
    EAAccessory *lastAccessory;
    FlutterEventSink _rxEventSink;

}
// Set the size of the buffer used to receive data from the input stream
#define RX_BUFFER_SIZE 1024
// #define RX_BUFFER_SIZE 32
#define PROTOCOL_HEADER_SIZE    2
const uint8_t kHeaderBytes[] = {0xCA, 0x5C};

+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
  FlutterMethodChannel* channel = [FlutterMethodChannel
      methodChannelWithName:@"byb_accessory"
            binaryMessenger:[registrar messenger]];
  FlutterEventChannel *rxChannel = [FlutterEventChannel
      eventChannelWithName:@"byb_accessory/rx"
           binaryMessenger:[registrar messenger]];
  BybAccessoryPlugin* instance = [[BybAccessoryPlugin alloc] init];
  [registrar addMethodCallDelegate:instance channel:channel];
  [rxChannel setStreamHandler:instance];
}

- (void)handleMethodCall:(FlutterMethodCall*)call result:(FlutterResult)result {
  if ([@"getPlatformVersion" isEqualToString:call.method]) {
    result([@"iOS " stringByAppendingString:[[UIDevice currentDevice] systemVersion]]);
  } else if ([@"getConnectedAccessories" isEqualToString:call.method]) {
    NSArray<EAAccessory *> *accessories = [[EAAccessoryManager sharedAccessoryManager] connectedAccessories];
    NSLog(@"BYB iOS getConnectedAccessories count=%lu", (unsigned long)accessories.count);
    NSMutableArray *accessoryNames = [NSMutableArray array];
    for (EAAccessory *obj in accessories) {
        NSLog(@"BYB iOS accessory name=%@ manufacturer=%@ model=%@ protocols=%@",
              obj.name, obj.manufacturer, obj.modelNumber, obj.protocolStrings);
        [accessoryNames addObject:obj.name];
    }
    if (accessories.count == 0) {
        NSLog(@"BYB iOS no visible accessories. Verify Info.plist UISupportedExternalAccessoryProtocols matches accessory protocol.");
    }
    result(accessoryNames);
  } else if ([@"initWithProtocol" isEqualToString:call.method]) {
    NSString *protocol = call.arguments[@"protocol"];
    if (![protocol isKindOfClass:[NSString class]] || protocol.length == 0) {
        result([FlutterError errorWithCode:@"missing_protocol"
                                   message:@"protocol argument is required"
                                   details:nil]);
        return;
    }
    _protocol = protocol;
    [self openSessionWithProtocol:_protocol];
    result(@YES);
  } else if ([@"connect" isEqualToString:call.method]) {
    NSString *name = call.arguments[@"name"];
    if ([name isKindOfClass:[NSString class]] && name.length > 0) {
        [self connectToAccessory:name];
    } else if (_protocol.length > 0) {
        [self openSessionWithProtocol:_protocol];
    } else {
        result([FlutterError errorWithCode:@"missing_target"
                                   message:@"Provide either accessory name or call initWithProtocol first"
                                   details:nil]);
        return;
    }
    result(@([self isConnected]));
  } else if ([@"disconnect" isEqualToString:call.method]) {
    [self closeSession];
    result(@YES);
  } else if ([@"isConnected" isEqualToString:call.method]) {
    result(@([self isConnected]));
  } else if ([@"getAccessoryInfo" isEqualToString:call.method]) {
    result(_accessoryInfoString ?: @"Accessory Not Connected\n");
  } else if ([@"sendBytes" isEqualToString:call.method]) {
    id bytesArg = nil;
    if ([call.arguments isKindOfClass:[NSDictionary class]]) {
        bytesArg = call.arguments[@"bytes"];
    }
    NSData *payload = nil;
    if ([bytesArg isKindOfClass:[FlutterStandardTypedData class]]) {
        payload = ((FlutterStandardTypedData *)bytesArg).data;
    } else if ([bytesArg isKindOfClass:[NSData class]]) {
        payload = (NSData *)bytesArg;
    }

    if (payload == nil || payload.length == 0) {
        result([FlutterError errorWithCode:@"invalid_payload"
                                   message:@"sendBytes requires non-empty Uint8List payload"
                                   details:nil]);
        return;
    }
    if (![self isConnected]) {
        result([FlutterError errorWithCode:@"not_connected"
                                   message:@"Accessory is not connected"
                                   details:nil]);
        return;
    }

    [self queuePacket:(uint8_t *)payload.bytes length:payload.length];
    result(@YES);
  } else if ([@"setProtocol" isEqualToString:call.method]) {
    NSString *protocol = call.arguments[@"protocol"];
    if (![protocol isKindOfClass:[NSString class]] || protocol.length == 0) {
        result([FlutterError errorWithCode:@"missing_protocol"
                                   message:@"protocol argument is required"
                                   details:nil]);
        return;
    }
    _protocol = protocol;
    result(@YES);
  } else {
    result(FlutterMethodNotImplemented);
  }
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _debugString = [NSMutableString stringWithString:@"BybAccessoryPlugin init\n"];
        _txData = [[NSMutableData alloc] init];
        _accessoryInfoString = @"Accessory Not Connected\n";
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(accessoryDidConnect:)
                                                     name:EAAccessoryDidConnectNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(accessoryDidDisconnect:)
                                                     name:EAAccessoryDidDisconnectNotification
                                                   object:nil];
        [[EAAccessoryManager sharedAccessoryManager] registerForLocalNotifications];
    }
    return self;
}

- (void)connectToAccessory:(NSString *)name {
    EAAccessoryManager *manager = [EAAccessoryManager sharedAccessoryManager];
    NSLog(@"BYB iOS connectToAccessory name=%@ requestedProtocol=%@", name, _protocol);
    for (EAAccessory *accessory in [manager connectedAccessories]) {
        NSLog(@"BYB log  - connectToAccessory - accessory.name : %@", accessory.name);
        NSLog(@"BYB iOS connectToAccessory candidate protocols=%@", accessory.protocolStrings);
        if ([accessory.name isEqualToString:name]) {
            NSString *selectedProtocol = _protocol;
            if (selectedProtocol.length == 0) {
                selectedProtocol = accessory.protocolStrings.firstObject;
            }
            if (selectedProtocol.length == 0) {
                [self addDebugString:@"No protocol found for accessory\n"];
                return;
            }
            [self openSessionWithProtocol:selectedProtocol];
            return;
        }
    }
}

- (void)tearDownExistingSessionAssumeMainThread {
    if (!_session) {
        return;
    }
    EAAccessory *attached = [_session accessory];
    // [[BBAudioManager bbAudioManager] removeMfiDeviceWithModelNumber:attached.modelNumber
    //                                                        andSerial:attached.serialNumber];
    NSRunLoop *mainLoop = [NSRunLoop mainRunLoop];
    [[_session inputStream] close];
    [[_session inputStream] removeFromRunLoop:mainLoop forMode:NSDefaultRunLoopMode];
    [[_session inputStream] setDelegate:nil];
    [[_session outputStream] close];
    [[_session outputStream] removeFromRunLoop:mainLoop forMode:NSDefaultRunLoopMode];
    [[_session outputStream] setDelegate:nil];
    _session = nil;
}


// Adds a string to the end of a debug log.
- (void)addDebugString:(NSString *)string
{
#ifdef DEBUG_MFI
    [_debugString appendString:string];
#endif
}

// Dumps a buffer to the debug log.
- (void)addDebugBuffer:(const uint8_t *)buf length:(int)len prefixString:(NSString*)prefix
{
#ifdef DEBUG_MFI
    NSMutableString *hexString = [NSMutableString stringWithString:prefix];
    for (int i=0; i<len; i++) {
        [hexString appendFormat:@"%02x ", buf[i]];
    }
    // [self addDebugString:[NSString stringWithFormat:@"%@\n", hexString]];
//    NSLog(@"RX (%ld): %@", (long)len, hexString);    
#endif
}

// Protocol implementation (subclass) must override this method which is called whenever
// bytes are received from the accessory.
- (void)processRxBytes:(uint8_t *)bytes length:(NSUInteger)len
{
    if (len == 0 || _rxEventSink == nil) {
        return;
    }
    NSData *payload = [NSData dataWithBytes:bytes length:len];
    FlutterStandardTypedData *typedData = [FlutterStandardTypedData typedDataWithBytes:payload];
    if ([NSThread isMainThread]) {
        if (_rxEventSink) _rxEventSink(typedData);
    } else {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self->_rxEventSink) self->_rxEventSink(typedData);
        });
    }
}

// Handles input stream has bytes events. Receives data from the accessory input stream.
- (void)rxBytes
{
    uint8_t buffer[RX_BUFFER_SIZE];
    while ([[_session inputStream] hasBytesAvailable])
    {
        NSInteger bytesRead = [[_session inputStream] read:buffer maxLength:RX_BUFFER_SIZE];
        [self processRxBytes:buffer length:bytesRead];
        // [self addDebugBuffer:buffer length:bytesRead prefixString:@"RX: "];
         NSMutableString *hex = [NSMutableString stringWithCapacity:bytesRead * 3];
         for (NSInteger i = 0; i < bytesRead; i++) {
             [hex appendFormat:@"%02X ", buffer[i]];
         }
//        NSLog(@"RX (%ld): %@", (long)bytesRead, hex);

    }
}

// Adds data to the transmit queue waiting to send to the accessory.
- (void)queueTxData:(NSData *)data
{
    // Ignore data if we are not connected to an accessory
    if ([self isConnected]) {
        // _txData = [data mutableCopy];
       [_txData appendData:data];
        [self txBytes];
    }
}

// Handles output stream has space events. Moves data from the transmit queue to the accessory output stream.
- (void)txBytes
{
    while (([[_session outputStream] hasSpaceAvailable]) && ([_txData length] > 0))
    {
        NSInteger bytesSent = [[_session outputStream] write:(const unsigned char *)[_txData bytes] maxLength:[_txData length]];
        // NSLog(@"TX (%ld): %@", (long)bytesSent, (const unsigned char *)[_txData bytes]);
        NSLog(@"TX (%ld): %@", (long)bytesSent, @"OLDDD");
        const uint8_t *bytes = (const uint8_t *) _txData.bytes;
        NSMutableArray<NSNumber *> *arr = [NSMutableArray arrayWithCapacity:_txData.length];
        for (NSUInteger i = 0; i < _txData.length; i++) {
            [arr addObject:@(bytes[i])];
        }
        NSLog(@"QUEUE TX (%ld): %@", (long)_txData.length, arr);

        if (bytesSent > 0)
        {
            //[self addDebugBuffer:[_txData bytes] length:bytesSent prefixString:@"TX: "];
            [_txData replaceBytesInRange:NSMakeRange(0, bytesSent) withBytes:NULL length:0];
        }
        else if (bytesSent == -1)
        {
            [self addDebugString:@"!outputStream error"];
            break;
        }
    }

}

- (void)queuePacket:(uint8_t *)payload length:(NSUInteger)len
{
    NSMutableData *packet = [NSMutableData dataWithCapacity:(PROTOCOL_HEADER_SIZE + len)];

    [packet appendBytes:kHeaderBytes length:PROTOCOL_HEADER_SIZE];
    [packet appendBytes:payload length:len];
    [self queueTxData:packet];
}

// Stream delegate handles events from both streams.
- (void)stream:(NSStream*)stream handleEvent:(NSStreamEvent)streamEvent
{
    //[self addDebugString:[NSString stringWithFormat:@"Stream Event: %d\n", streamEvent]];

    switch (streamEvent) {
    case NSStreamEventHasBytesAvailable:
        [self rxBytes];
        break;

    case NSStreamEventHasSpaceAvailable:
        [self txBytes];
        break;

    case NSStreamEventErrorOccurred:
        [self addDebugString:@"!streamEvent error"];
        break;

    default:
        break;
    }
}

// Create a string with all of the accessory info properties listed.
- (void) gatherAccessoryInfo:(EAAccessory *)accessory
{
    NSMutableString *infoString = [NSMutableString stringWithString:@"Accessory Info:\n"];
    [infoString appendFormat:@"Name.... %@\n", accessory.name];
    [infoString appendFormat:@"Manufacturer.... %@\n", accessory.manufacturer];
    [infoString appendFormat:@"Model Number.... %@\n", accessory.modelNumber];
    [infoString appendFormat:@"Serial Number.... %@\n", accessory.serialNumber];
    [infoString appendFormat:@"Firmware Revision.... %@\n", accessory.firmwareRevision];
    [infoString appendFormat:@"Hardware Revision.... %@\n", accessory.hardwareRevision];
    _accessoryInfoString = infoString;
}


- (void) reAddExistingAccessory
{
    
    lastAccessory  = [self getCurrentAccessoryWithProtocol:_protocol];
    NSLog(@"lastAccessory - before");
    // If the requested protocol was found, open a session and hook up the related streams
    if (lastAccessory) {
        NSLog(@"lastAccessory - OK");
        //_session = [[EASession alloc] initWithAccessory:lastAccessory forProtocol:_protocol];
        
        if (_session) {
            NSLog(@"_session - OK");
            //change audio manager input to external accessory
            cBufHead=0;
            cBufTail=0;
            // [[BBAudioManager bbAudioManager] addMfiDeviceWithModelNumber:lastAccessory.modelNumber andSerial:lastAccessory.serialNumber];
        }
    }
}

// Search connected accessories for the requested protocol. If found, open a session
// and hook up the associated streams.
- (void) openSessionWithProtocol:(NSString *)protocolString
{
    NSLog(@"BYB log  - openSessionWithProtocol protocol=%@", protocolString);
    if (protocolString.length == 0) {
        return;
    }
    _accessoryInfoString = @"Accessory Not Connected\n";

    void (^openWork)(void) = ^{
        EAAccessory *accessory = [self getCurrentAccessoryWithProtocol:protocolString];
        self->lastAccessory = accessory;

        if (!accessory) {
            NSLog(@"BYB iOS openSessionWithProtocol no accessory for protocol %@", protocolString);
            return;
        }

        [self gatherAccessoryInfo:accessory];
        [self addDebugString:@"Opening session...\n"];

        if (self->_session != nil) {
            [self tearDownExistingSessionAssumeMainThread];
        }

        NSRunLoop *mainLoop = [NSRunLoop mainRunLoop];
        self->_session = [[EASession alloc] initWithAccessory:accessory forProtocol:protocolString];

        if (!self->_session) {
            [self addDebugString:@"Failed opening session\n"];
            NSLog(@"BYB iOS EASession init failed");
            return;
        }

        self->cBufHead = 0;
        self->cBufTail = 0;
        // [[BBAudioManager bbAudioManager] addMfiDeviceWithModelNumber:accessory.modelNumber andSerial:accessory.serialNumber];

        [self addDebugString:@"Opening streams...\n"];
        NSInputStream *inStream = self->_session.inputStream;
        NSOutputStream *outStream = self->_session.outputStream;
        [inStream setDelegate:self];
        [outStream setDelegate:self];
        // Flutter invokes method-channel handlers off the main thread; NSStream delegates only fire
        // if streams are scheduled on a run loop that is actually running (typically the main run loop).
        [inStream scheduleInRunLoop:mainLoop forMode:NSDefaultRunLoopMode];
        [outStream scheduleInRunLoop:mainLoop forMode:NSDefaultRunLoopMode];
        [inStream open];
        [outStream open];

        [self setupProtocol];
    };

    if ([NSThread isMainThread]) {
        openWork();
    } else {
        dispatch_sync(dispatch_get_main_queue(), openWork);
    }
}

// Close an open session and disconnect the associated streams.
- (void)closeSession
{
    _accessoryInfoString = @"Accessory Not Connected\n";
    [self addDebugString:@"closeSession\n"];
    void (^work)(void) = ^{
        if (self->_session == nil) {
            return;
        }
        [self tearDownExistingSessionAssumeMainThread];
    };
    if ([NSThread isMainThread]) {
        work();
    } else {
        dispatch_sync(dispatch_get_main_queue(), work);
    }
}

// Init instance with the requested accessory protocol. Open a session if the accessory is already
// connected and start listening for connect/disconnect events.
- (id)initWithProtocol:(NSString *)protocol
{
    
    if([[UIApplication sharedApplication] isProtectedDataAvailable])
    {
        NSLog(@"Device is unlocked! initWithProtocol");
    }
    else
    {
        NSLog(@"Device is locked! initWithProtocol");
    }
    self = [super init];
    if (self) {
        _debugString = [NSMutableString stringWithString:@"initWithProtocol:\n"];
        _txData = [[NSMutableData alloc] init];
        _protocol = protocol;

        // Start session if an accessory is already attached
        [self openSessionWithProtocol:_protocol];

        // Listen for connect/disconnect events
        [[NSNotificationCenter defaultCenter] addObserver:self
            selector:@selector(accessoryDidConnect:)
            name:EAAccessoryDidConnectNotification
            object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
            selector:@selector(accessoryDidDisconnect:)
            name:EAAccessoryDidDisconnectNotification
            object:nil];

        [[EAAccessoryManager sharedAccessoryManager] registerForLocalNotifications];
    }
    return self;
}


-(EAAccessory *) getCurrentAccessoryWithProtocol:(NSString *) protocol
{
    NSArray *accessories = [[EAAccessoryManager sharedAccessoryManager] connectedAccessories];
    EAAccessory *accessory = nil;

    // Search connected accessories for the requested protocol
    for (EAAccessory *nextAccessory in accessories) {
        if ([[nextAccessory protocolStrings] containsObject:protocol]) {
            accessory = nextAccessory;
            break;
        }
    }
    return accessory;
}


// On instance removal, stop listening for connect/disconnect events and close the session if
// there is one.
- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [[EAAccessoryManager sharedAccessoryManager] unregisterForLocalNotifications];
    [self closeSession];
    
}

// Checks if the accessory is currently connected.
- (bool)isConnected
{
    return [[_session accessory] isConnected];
}

#pragma mark - EAAccessory Notifications

// Observer method for accessory connect notifications posted by the EAAccessoryManager.
// Attemps to open a session with the desired protocol if one is not already open.
- (void)accessoryDidConnect:(NSNotification *)notification
{
    if([[UIApplication sharedApplication] isProtectedDataAvailable])
    {
        NSLog(@"Device is unlocked! accessoryDidConnect");
    }
    else
    {
        NSLog(@"Device is locked! accessoryDidConnect");
    }
    [self addDebugString:@"DidConnect:\n"];
    if (_session == nil) {
        [self openSessionWithProtocol:_protocol];
    }
}

// Observer method for accessory disconnect notifications posted by the EAAccessoryManager.
// Closes the session if our accessory disconnected.
- (void)accessoryDidDisconnect:(NSNotification *)notification
{
    EAAccessory *disconnectedAccessory = [[notification userInfo] objectForKey:EAAccessoryKey];
    NSArray *protocolStrings = [disconnectedAccessory protocolStrings];
    
    [self addDebugString:[NSString stringWithFormat:@"DidDisconnect: %@\n", protocolStrings]];
    if ([protocolStrings containsObject:_protocol]) {
        [self closeSession];
    }
}

- (void) setupProtocol
{
    //init all things that you need
}

- (FlutterError *_Nullable)onListenWithArguments:(id _Nullable)arguments
                                        eventSink:(FlutterEventSink)events
{
    _rxEventSink = events;
    return nil;
}

- (FlutterError *_Nullable)onCancelWithArguments:(id _Nullable)arguments
{
    _rxEventSink = nil;
    return nil;
}

@end
