#import "BybAccessoryPlugin.h"
#import "SpikeRecorder/Audio/BBAudioManager.h"
#import <math.h>
#import <string.h>

@interface BybAccessoryPlugin ()
/// EA notifications are UIKit; register on the main queue (plugin init may not
/// always run there).
- (void)registerExternalAccessoryObserversOnMainIfNeeded;
- (void)logConnectedAccessoriesDiagnostics;
- (void)bootstrapProtocolFromInfoPlistIfNeeded;
- (void)flushPendingRxToEventSink;
- (void)connectToAccessory:(NSString *)name;
/// Call only on main thread; uses NSRunLoop main for stream scheduling
/// teardown.
- (void)tearDownExistingSessionAssumeMainThread;
/// When iOS cold-launches for MFi, EAAccessoryDidConnect may have fired before
/// this plugin registered.
- (void)tryAttachAlreadyConnectedAccessoryAfterColdLaunch;
/// Avoid EA session vs Flutter UI race when accessory wakes the app before
/// UIApplicationStateActive.
- (void)openSessionWithProtocolDeferringUntilActive:(NSString *)protocolString;
- (void)flushDeferredAccessorySessionOpenAfterActive:
    (NSNotification *)notification;
- (void)cancelDeferredAccessorySessionOpenIfNeeded;
@end

@implementation BybAccessoryPlugin {
  EASession *_session;
  NSString *_protocol;
  NSMutableData *_txData;
  EAAccessory *lastAccessory;
  FlutterEventSink _rxEventSink;
  NSMutableData *_rxPendingBuffer;
  NSString *_pendingDeferProtocol;
  BOOL _didRegisterDeferActiveObserver;
  BOOL _didReceiveDartInit;
  BOOL _didRegisterEAObservers;
  int _samplingRate;
  int _numberOfChannels;
  int _halfTheSampleVoltageRange;
  int currentAddOnBoard;
  BOOL _restartDevice;
  BOOL _p300IsActive;
  BOOL _p300AudioIsActive;
}
// Set the size of the buffer used to receive data from the input stream
#define RX_BUFFER_SIZE 1024
#define RX_PENDING_MAX (256 * 1024)
// #define RX_BUFFER_SIZE 32
#define PROTOCOL_HEADER_SIZE 2
const uint8_t kHeaderBytes[] = {0xCA, 0x5C};
#define BOARD_WITH_EVENT_INPUTS 0
#define BOARD_WITH_ADDITIONAL_INPUTS 1
#define BOARD_WITH_HAMMER 4
#define BOARD_WITH_JOYSTICK 5

+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar> *)registrar {
  FlutterMethodChannel *channel =
      [FlutterMethodChannel methodChannelWithName:@"byb_accessory"
                                  binaryMessenger:[registrar messenger]];
  FlutterEventChannel *rxChannel =
      [FlutterEventChannel eventChannelWithName:@"byb_accessory/rx"
                                binaryMessenger:[registrar messenger]];
  BybAccessoryPlugin *instance = [[BybAccessoryPlugin alloc] init];
  [registrar addMethodCallDelegate:instance channel:channel];
  [rxChannel setStreamHandler:instance];
  dispatch_async(dispatch_get_main_queue(), ^{
    [instance bootstrapProtocolFromInfoPlistIfNeeded];
    [instance logConnectedAccessoriesDiagnostics];
  });
}

+ (NSArray<NSString *> *)readExternalAccessoryProtocolsFromBundlePlist {
  id value = [[NSBundle mainBundle]
      objectForInfoDictionaryKey:@"UISupportedExternalAccessoryProtocols"];
  if (![value isKindOfClass:[NSArray class]]) {
    return @[];
  }
  NSMutableArray *out = [NSMutableArray array];
  for (id item in (NSArray *)value) {
    if ([item isKindOfClass:[NSString class]] &&
        [(NSString *)item length] > 0) {
      [out addObject:(NSString *)item];
    }
  }
  return out;
}

- (void)bootstrapProtocolFromInfoPlistIfNeeded {
  if (_protocol != nil && _protocol.length > 0) {
    return;
  }
  NSArray<NSString *> *protocols =
      [BybAccessoryPlugin readExternalAccessoryProtocolsFromBundlePlist];
  if (protocols.count == 0) {
    return;
  }
  [_protocol release];
  _protocol = [protocols.firstObject copy];
  NSLog(@"BYB iOS bootstrap protocol from Info.plist: %@", _protocol);
}

- (void)logConnectedAccessoriesDiagnostics {
  NSArray<NSString *> *declaredProtocols =
      [BybAccessoryPlugin readExternalAccessoryProtocolsFromBundlePlist];
  NSLog(@"BYB iOS UISupportedExternalAccessoryProtocols (built app): %@",
        declaredProtocols);
  NSLog(@"BYB iOS active Dart/native protocol: %@",
        _protocol.length > 0 ? _protocol : @"(unset)");

  NSArray<EAAccessory *> *accessories =
      [[EAAccessoryManager sharedAccessoryManager] connectedAccessories];
  NSLog(@"BYB iOS connectedAccessories count=%lu",
        (unsigned long)accessories.count);

  for (EAAccessory *accessory in accessories) {
    NSLog(@"BYB iOS accessory name=%@ manufacturer=%@ model=%@ serial=%@ "
          @"firmware=%@ hardware=%@ connectionID=%u protocols=%@",
          accessory.name, accessory.manufacturer, accessory.modelNumber,
          accessory.serialNumber, accessory.firmwareRevision,
          accessory.hardwareRevision, accessory.connectionID,
          accessory.protocolStrings);
  }

  if (_session != nil) {
    EAAccessory *sessionAccessory = [_session accessory];
    NSLog(@"BYB iOS EASession open=YES protocol=%@ accessory=%@ "
          @"connectionID=%u streams input=%@ output=%@",
          _protocol,
          sessionAccessory.name ?: @"(nil)",
          sessionAccessory.connectionID,
          [_session inputStream] ? @"yes" : @"no",
          [_session outputStream] ? @"yes" : @"no");
  } else {
    NSLog(@"BYB iOS EASession open=NO");
  }
}

- (void)flushPendingRxToEventSink {
  if (_rxEventSink == nil || _rxPendingBuffer == nil ||
      _rxPendingBuffer.length == 0) {
    return;
  }
  NSData *payload = [_rxPendingBuffer copy];
  [_rxPendingBuffer setLength:0];
  FlutterStandardTypedData *typedData =
      [FlutterStandardTypedData typedDataWithBytes:payload];
  _rxEventSink(typedData);
  NSLog(@"BYB iOS flushed %lu buffered RX bytes to Flutter listener",
        (unsigned long)payload.length);
}

- (void)tryAttachAlreadyConnectedAccessoryAfterColdLaunch {
  if (!_didReceiveDartInit) {
    NSLog(@"BYB cold-launch: skip auto-attach until Dart initWithProtocol");
    return;
  }
  if (_session != nil) {
    return;
  }
  NSString *protocolToUse = _protocol;
  if (protocolToUse == nil || protocolToUse.length == 0) {
    for (NSString *p in
         [BybAccessoryPlugin readExternalAccessoryProtocolsFromBundlePlist]) {
      if ([self getCurrentAccessoryWithProtocol:p] != nil) {
        [_protocol release];
        _protocol = [p copy];
        protocolToUse = _protocol;
        NSLog(@"BYB cold-launch: protocol from Info.plist %@", p);
        break;
      }
    }
  }
  if (protocolToUse.length == 0) {
    return;
  }
  if ([self getCurrentAccessoryWithProtocol:protocolToUse] != nil) {
    NSLog(@"BYB cold-launch: opening session for already-connected accessory");
    [self openSessionWithProtocolDeferringUntilActive:protocolToUse];
  }
}

- (void)cancelDeferredAccessorySessionOpenIfNeeded {
  [_pendingDeferProtocol release];
  _pendingDeferProtocol = nil;
  if (!_didRegisterDeferActiveObserver) {
    return;
  }
  _didRegisterDeferActiveObserver = NO;
  [[NSNotificationCenter defaultCenter]
      removeObserver:self
                name:UIApplicationDidBecomeActiveNotification
              object:nil];
}

/// Schedules EA session open once the UI app is active, avoiding
/// headless/stream-before-scene races.
- (void)openSessionWithProtocolDeferringUntilActive:(NSString *)protocolString {
  if (protocolString.length == 0) {
    return;
  }
  if (![NSThread isMainThread]) {
    dispatch_async(dispatch_get_main_queue(), ^{
      [self openSessionWithProtocolDeferringUntilActive:protocolString];
    });
    return;
  }
  UIApplication *app = [UIApplication sharedApplication];
  if ([app applicationState] == UIApplicationStateActive) {
    [self openSessionWithProtocol:protocolString];
    return;
  }
  [_pendingDeferProtocol release];
  _pendingDeferProtocol = [protocolString copy];
  if (!_didRegisterDeferActiveObserver) {
    _didRegisterDeferActiveObserver = YES;
    [[NSNotificationCenter defaultCenter]
        addObserver:self
           selector:@selector(flushDeferredAccessorySessionOpenAfterActive:)
               name:UIApplicationDidBecomeActiveNotification
             object:nil];
  }
  NSLog(@"BYB iOS defer EA open until active (UIApplicationState=%ld, "
        @"protocol=%@)",
        (long)[app applicationState], protocolString);
}

- (void)flushDeferredAccessorySessionOpenAfterActive:
    (NSNotification *)notification {
  if (!_didRegisterDeferActiveObserver) {
    return;
  }
  _didRegisterDeferActiveObserver = NO;
  [[NSNotificationCenter defaultCenter]
      removeObserver:self
                name:UIApplicationDidBecomeActiveNotification
              object:nil];

  NSString *pending = [_pendingDeferProtocol retain];
  [_pendingDeferProtocol release];
  _pendingDeferProtocol = nil;

  if (pending.length == 0) {
    [pending release];
    return;
  }
  if (_session != nil) {
    NSLog(@"BYB iOS defer flush: session already open, skipping");
    [pending release];
    return;
  }
  if ([self getCurrentAccessoryWithProtocol:pending] == nil) {
    NSLog(@"BYB iOS defer flush: no matching accessory for %@", pending);
    [pending release];
    return;
  }
  NSLog(@"BYB iOS defer flush: calling openSessionWithProtocol for %@",
        pending);
  [self openSessionWithProtocol:pending];
  [pending release];
}

- (void)handleMethodCall:(FlutterMethodCall *)call
                  result:(FlutterResult)result {
  if ([@"getPlatformVersion" isEqualToString:call.method]) {
    result([@"iOS "
        stringByAppendingString:[[UIDevice currentDevice] systemVersion]]);
  } else if ([@"getConnectedAccessories" isEqualToString:call.method]) {
    [self logConnectedAccessoriesDiagnostics];
    NSArray<EAAccessory *> *accessories =
        [[EAAccessoryManager sharedAccessoryManager] connectedAccessories];
    NSLog(@"BYB iOS getConnectedAccessories count=%lu",
          (unsigned long)accessories.count);
    NSMutableArray *accessoryNames = [NSMutableArray array];
    for (EAAccessory *obj in accessories) {
      // NSLog(@"BYB iOS accessory name=%@ manufacturer=%@ model=%@
      // protocols=%@",
      //       obj.name, obj.manufacturer, obj.modelNumber,
      //       obj.protocolStrings);
      [accessoryNames addObject:obj.name];
    }
    if (accessories.count == 0) {
      NSLog(
          @"BYB iOS no visible accessories. Verify Info.plist "
          @"UISupportedExternalAccessoryProtocols matches accessory protocol.");
    }
    result(accessoryNames);
  } else if ([@"logAccessoryDiagnostics" isEqualToString:call.method]) {
    [self logConnectedAccessoriesDiagnostics];
    result(@YES);
  } else if ([@"initWithProtocol" isEqualToString:call.method]) {
    NSLog(@"BYB iOS Init With Protocol.");
    NSString *protocol = call.arguments[@"protocol"];
    if (![protocol isKindOfClass:[NSString class]] || protocol.length == 0) {
      result([FlutterError errorWithCode:@"missing_protocol"
                                 message:@"protocol argument is required"
                                 details:nil]);
      return;
    }
    [_protocol release];
    _protocol = [protocol copy];
    _didReceiveDartInit = YES;
    [self logConnectedAccessoriesDiagnostics];
    [self openSessionWithProtocolDeferringUntilActive:_protocol];
    [self tryAttachAlreadyConnectedAccessoryAfterColdLaunch];
    result(@YES);
  } else if ([@"connect" isEqualToString:call.method]) {
    NSString *name = call.arguments[@"name"];
    if ([name isKindOfClass:[NSString class]] && name.length > 0) {
      [self connectToAccessory:name];
    } else if (_protocol != nil && _protocol.length > 0) {
      [self openSessionWithProtocolDeferringUntilActive:_protocol];
    } else {
      result([FlutterError errorWithCode:@"missing_target"
                                 message:@"Provide either accessory name or "
                                         @"call initWithProtocol first"
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
    EAAccessory *accessory = [_session accessory];
    if (accessory != nil && [accessory isConnected]) {
      [self gatherAccessoryInfo:accessory];
    } else if (_protocol.length > 0) {
      EAAccessory *found = [self getCurrentAccessoryWithProtocol:_protocol];
      if (found != nil) {
        [self gatherAccessoryInfo:found];
      }
    }
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
      result([FlutterError
          errorWithCode:@"invalid_payload"
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
    [_protocol release];
    _protocol = [protocol copy];
    result(@YES);
  } else {
    result(FlutterMethodNotImplemented);
  }
}

/// External Accessory notifications are delivered through NSNotificationCenter
/// on the system (not the Flutter engine). There is no Flutter-specific
/// registration API for them — the plugin instance is the correct observer
/// because it owns EASession / streams. This must run on the main thread per
/// UIKit / EA guidance.
- (void)registerExternalAccessoryObserversOnMainIfNeeded {
  if (_didRegisterEAObservers) {
    return;
  }
  NSAssert([NSThread isMainThread],
           @"EA observers must be registered on the main queue");
  [[NSNotificationCenter defaultCenter]
      addObserver:self
         selector:@selector(accessoryDidConnect:)
             name:EAAccessoryDidConnectNotification
           object:nil];
  [[NSNotificationCenter defaultCenter]
      addObserver:self
         selector:@selector(accessoryDidDisconnect:)
             name:EAAccessoryDidDisconnectNotification
           object:nil];
  [[EAAccessoryManager sharedAccessoryManager] registerForLocalNotifications];
  _didRegisterEAObservers = YES;
}

- (instancetype)init {
  self = [super init];
  if (self) {
    _debugString =
        [NSMutableString stringWithString:@"BybAccessoryPlugin init\n"];
    _txData = [[NSMutableData alloc] init];
    _rxPendingBuffer = [[NSMutableData alloc] init];
    _accessoryInfoString = @"Accessory Not Connected\n";
    _didReceiveDartInit = NO;
    _samplingRate = 10000;
    _numberOfChannels = 2;
    _halfTheSampleVoltageRange = 512;
    currentAddOnBoard = BOARD_WITH_EVENT_INPUTS;
    _restartDevice = NO;
    _p300IsActive = NO;
    _p300AudioIsActive = NO;
    void (^reg)(void) = ^{
      [self registerExternalAccessoryObserversOnMainIfNeeded];
    };
    if ([NSThread isMainThread]) {
      reg();
    } else {
      dispatch_sync(dispatch_get_main_queue(), reg);
    }
    dispatch_after(
        dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.5 * NSEC_PER_SEC)),
        dispatch_get_main_queue(), ^{
          //            UIWindow *window = [UIApplication
          //            sharedApplication].delegate.window;
          UIWindow *window = [[UIApplication sharedApplication] keyWindow];
          if (window) {
            NSLog(@"BYB iOS dispatch_after.");

            // Force the window to re-layout its subviews
            [window setNeedsLayout];
            [window layoutIfNeeded];

            // Briefly toggling a view property can "wake up" the compositor
            UIView *rootView = window.rootViewController.view;
            rootView.alpha = 0.99;
            dispatch_after(
                dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)),
                dispatch_get_main_queue(), ^{
                  rootView.alpha = 1.0;
                });
          }
        });
  }
  return self;
}

- (void)sendAsciiCommand:(NSString *)command {
  if (command.length == 0) {
    return;
  }
  const char *bytes = [command UTF8String];
  [self queuePacket:(uint8_t *)bytes length:strlen(bytes)];
}

- (void)initProtocol {
  [self initWithProtocol:@"com.backyardbrains.spikerbox"];
  _samplingRate = 10000;
  _numberOfChannels = 2;
  _halfTheSampleVoltageRange = 512;
  currentAddOnBoard = BOARD_WITH_EVENT_INPUTS;
  _restartDevice = NO;
  _p300IsActive = NO;
  _p300AudioIsActive = NO;
}

- (void)setSampleRate:(int)inSampleRate
     numberOfChannels:(int)inNumberOfChannels
        andResolution:(int)resolution {
  _samplingRate = inSampleRate;
  _numberOfChannels = inNumberOfChannels;
  if (resolution > 0) {
    _halfTheSampleVoltageRange = (int)(pow(2, resolution) / 2.0);
  } else {
    _halfTheSampleVoltageRange = 512;
  }
}

- (void)sendCommandGetAdc {
  uint8_t cmd[6] = {5, 0, 0, 0, 0, 0};
  [self queuePacket:cmd length:sizeof(cmd)];
}

- (void)askForBoardType {
  [self sendAsciiCommand:@"board:;\n"];
}

- (void)askForImportantStates {
  [self sendAsciiCommand:@"board:;p300?:;\n"];
}

- (bool)getP300State {
  return _p300IsActive;
}

- (bool)getP300AudioState {
  return _p300AudioIsActive;
}

- (void)askForP300AudioState {
  [self sendAsciiCommand:@"sound?:;\n"];
}

- (void)askForP300State {
  [self sendAsciiCommand:@"p300?:;\n"];
}

- (void)setP300Active:(bool)active {
  [self sendAsciiCommand:(active ? @"stimon:;\n" : @"stimoff:;\n")];
  _p300IsActive = active;
}

- (void)setP300AudioActive:(bool)active {
  [self sendAsciiCommand:(active ? @"sounon:;\n" : @"sounoff:;\n")];
  _p300AudioIsActive = active;
}

- (void)setHardwareHighGainActive:(BOOL)state {
  [self sendAsciiCommand:(state ? @"gainon:1;gainon:2;\n"
                                : @"gainoff:1;gainoff:2;\n")];
}

- (void)setHardwareHPFActive:(BOOL)state {
  [self sendAsciiCommand:(state ? @"hpfon:2;hpfon:1;\n"
                                : @"hpfoff:2;hpfoff:1;\n")];
}

- (int)getCurrentExpansionBoard {
  return currentAddOnBoard;
}

- (int)numberOfChannels {
  return _numberOfChannels;
}

- (int)sampleRate {
  return _samplingRate;
}

- (bool)shouldRestartDevice {
  return _restartDevice;
}

- (void)deviceRestarted {
  _restartDevice = NO;
}

- (void)connectToAccessory:(NSString *)name {
  EAAccessoryManager *manager = [EAAccessoryManager sharedAccessoryManager];
  if (_protocol == nil || _protocol.length == 0) {
    NSLog(@"BYB iOS connectToAccessory: no protocol; call initWithProtocol or "
          @"declare UISupportedExternalAccessoryProtocols");
    return;
  }
  NSLog(@"BYB iOS connectToAccessory name=%@ requestedProtocol=%@", name,
        _protocol);
  for (EAAccessory *accessory in [manager connectedAccessories]) {
    NSLog(@"BYB log  - connectToAccessory - accessory.name : %@",
          accessory.name);
    NSLog(@"BYB iOS connectToAccessory candidate protocols=%@",
          accessory.protocolStrings);
    if ([accessory.name isEqualToString:name]) {
      NSString *selectedProtocol = _protocol;
      if (selectedProtocol.length == 0) {
        selectedProtocol = accessory.protocolStrings.firstObject;
      }
      if (selectedProtocol.length == 0) {
        [self addDebugString:@"No protocol found for accessory\n"];
        return;
      }
      [self openSessionWithProtocolDeferringUntilActive:selectedProtocol];
      return;
    }
  }
}

- (void)tearDownExistingSessionAssumeMainThread {
  if (!_session) {
    return;
  }
  EAAccessory *attached = [_session accessory];
  // [[BBAudioManager bbAudioManager]
  // removeMfiDeviceWithModelNumber:attached.modelNumber
  //                                                        andSerial:attached.serialNumber];
  NSRunLoop *mainLoop = [NSRunLoop mainRunLoop];
  [[_session inputStream] close];
  [[_session inputStream] removeFromRunLoop:mainLoop
                                    forMode:NSDefaultRunLoopMode];
  [[_session inputStream] setDelegate:nil];
  [[_session outputStream] close];
  [[_session outputStream] removeFromRunLoop:mainLoop
                                     forMode:NSDefaultRunLoopMode];
  [[_session outputStream] setDelegate:nil];
  _session = nil;
}

// Adds a string to the end of a debug log.
- (void)addDebugString:(NSString *)string {
#ifdef DEBUG_MFI
  [_debugString appendString:string];
#endif
}

// Dumps a buffer to the debug log.
- (void)addDebugBuffer:(const uint8_t *)buf
                length:(int)len
          prefixString:(NSString *)prefix {
#ifdef DEBUG_MFI
  NSMutableString *hexString = [NSMutableString stringWithString:prefix];
  for (int i = 0; i < len; i++) {
    [hexString appendFormat:@"%02x ", buf[i]];
  }
  // [self addDebugString:[NSString stringWithFormat:@"%@\n", hexString]];
//    NSLog(@"RX (%ld): %@", (long)len, hexString);
#endif
}

// Protocol implementation (subclass) must override this method which is called
// whenever bytes are received from the accessory.
- (void)processRxBytes:(uint8_t *)bytes length:(NSUInteger)len {
  if (len == 0) {
    return;
  }
  if (_rxEventSink == nil) {
    if (_rxPendingBuffer == nil) {
      _rxPendingBuffer = [[NSMutableData alloc] init];
    }
    NSUInteger remaining = RX_PENDING_MAX - _rxPendingBuffer.length;
    if (remaining == 0) {
      NSLog(@"BYB iOS RX pending buffer full (%d bytes); dropping %lu bytes",
            RX_PENDING_MAX, (unsigned long)len);
      return;
    }
    NSUInteger toStore = MIN(len, remaining);
    [_rxPendingBuffer appendBytes:bytes length:toStore];
    return;
  }
  NSData *payload = [NSData dataWithBytes:bytes length:len];
  FlutterStandardTypedData *typedData =
      [FlutterStandardTypedData typedDataWithBytes:payload];
  if ([NSThread isMainThread]) {
    if (_rxEventSink) {
      _rxEventSink(typedData);
    }
  } else {
    dispatch_async(dispatch_get_main_queue(), ^{
      if (self->_rxEventSink) {
        self->_rxEventSink(typedData);
      }
    });
  }
}

// Handles input stream has bytes events. Receives data from the accessory input
// stream.
- (void)rxBytes {
  uint8_t buffer[RX_BUFFER_SIZE];
  while ([[_session inputStream] hasBytesAvailable]) {
    NSInteger bytesRead = [[_session inputStream] read:buffer
                                             maxLength:RX_BUFFER_SIZE];
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
- (void)queueTxData:(NSData *)data {
  // Ignore data if we are not connected to an accessory
  if ([self isConnected]) {
    // _txData = [data mutableCopy];
    [_txData appendData:data];
    [self txBytes];
  }
}

// Handles output stream has space events. Moves data from the transmit queue to
// the accessory output stream.
- (void)txBytes {
  while (([[_session outputStream] hasSpaceAvailable]) &&
         ([_txData length] > 0)) {
    NSInteger bytesSent =
        [[_session outputStream] write:(const unsigned char *)[_txData bytes]
                             maxLength:[_txData length]];
    // NSLog(@"TX (%ld): %@", (long)bytesSent, (const unsigned char *)[_txData
    // bytes]); NSLog(@"TX (%ld): %@", (long)bytesSent, @"OLDDD"); const uint8_t
    // *bytes = (const uint8_t *) _txData.bytes; NSMutableArray<NSNumber *> *arr
    // = [NSMutableArray arrayWithCapacity:_txData.length]; for (NSUInteger i =
    // 0; i < _txData.length; i++) {
    //     [arr addObject:@(bytes[i])];
    // }
    // NSLog(@"QUEUE TX (%ld): %@", (long)_txData.length, arr);

    if (bytesSent > 0) {
      //[self addDebugBuffer:[_txData bytes] length:bytesSent prefixString:@"TX:
      //"];
      [_txData replaceBytesInRange:NSMakeRange(0, bytesSent)
                         withBytes:NULL
                            length:0];
    } else if (bytesSent == -1) {
      [self addDebugString:@"!outputStream error"];
      break;
    }
  }
}

- (void)queuePacket:(uint8_t *)payload length:(NSUInteger)len {
  NSMutableData *packet =
      [NSMutableData dataWithCapacity:(PROTOCOL_HEADER_SIZE + len)];

  [packet appendBytes:kHeaderBytes length:PROTOCOL_HEADER_SIZE];
  [packet appendBytes:payload length:len];
  [self queueTxData:packet];
}

// Stream delegate handles events from both streams.
- (void)stream:(NSStream *)stream handleEvent:(NSStreamEvent)streamEvent {
  //[self addDebugString:[NSString stringWithFormat:@"Stream Event: %d\n",
  //streamEvent]];

  switch (streamEvent) {
  case NSStreamEventHasBytesAvailable:
    [self rxBytes];
    break;

  case NSStreamEventHasSpaceAvailable:
    [self txBytes];
    break;

  case NSStreamEventErrorOccurred:
    [self addDebugString:@"!streamEvent error"];
    NSLog(@"BYB iOS stream error — scheduling session reopen");
    if (self->_protocol.length > 0) {
      NSString *protocol = [self->_protocol copy];
      dispatch_async(dispatch_get_main_queue(), ^{
        [self closeSession];
        [self openSessionWithProtocolDeferringUntilActive:protocol];
        [protocol release];
      });
    }
    break;

  default:
    break;
  }
}

// Create a string with all of the accessory info properties listed.
- (void)gatherAccessoryInfo:(EAAccessory *)accessory {
  NSMutableString *infoString =
      [NSMutableString stringWithString:@"Accessory Info:\n"];
  [infoString appendFormat:@"Name.... %@\n", accessory.name];
  [infoString appendFormat:@"Manufacturer.... %@\n", accessory.manufacturer];
  [infoString appendFormat:@"Model Number.... %@\n", accessory.modelNumber];
  [infoString appendFormat:@"Serial Number.... %@\n", accessory.serialNumber];
  [infoString
      appendFormat:@"Firmware Revision.... %@\n", accessory.firmwareRevision];
  [infoString
      appendFormat:@"Hardware Revision.... %@\n", accessory.hardwareRevision];
  _accessoryInfoString = infoString;
  /*
  flutter: Accessory Info:
  Name.... SpikerBox
  Manufacturer.... Backyard Brains
  Model Number.... SpikerBox
  Serial Number.... 0043004B5533500B20333136
  Firmware Revision.... 1.0.0
  Hardware Revision.... 1.0
  */
}

- (void)reAddExistingAccessory {

  lastAccessory = [self getCurrentAccessoryWithProtocol:_protocol];
  NSLog(@"lastAccessory - before");
  // If the requested protocol was found, open a session and hook up the related
  // streams
  if (lastAccessory) {
    NSLog(@"lastAccessory - OK");
    //_session = [[EASession alloc] initWithAccessory:lastAccessory
    //forProtocol:_protocol];

    if (_session) {
      NSLog(@"_session - OK");
      // change audio manager input to external accessory
      cBufHead = 0;
      cBufTail = 0;
      // [[BBAudioManager bbAudioManager]
      // addMfiDeviceWithModelNumber:lastAccessory.modelNumber
      // andSerial:lastAccessory.serialNumber];
    }
  }
}

// Search connected accessories for the requested protocol. If found, open a
// session and hook up the associated streams.
- (void)openSessionWithProtocol:(NSString *)protocolString {
  NSLog(@"BYB log  - openSessionWithProtocol protocol=%@", protocolString);
  if (protocolString.length == 0) {
    return;
  }
  _accessoryInfoString = @"Accessory Not Connected\n";

  void (^openWork)(void) = ^{
    EAAccessory *accessory =
        [self getCurrentAccessoryWithProtocol:protocolString];
    self->lastAccessory = accessory;

    if (!accessory) {
      NSLog(@"BYB iOS openSessionWithProtocol no accessory for protocol %@",
            protocolString);
      return;
    }

    [self gatherAccessoryInfo:accessory];
    [self addDebugString:@"Opening session...\n"];

    if (self->_session != nil) {
      [self tearDownExistingSessionAssumeMainThread];
    }

    NSRunLoop *mainLoop = [NSRunLoop mainRunLoop];
    self->_session = [[EASession alloc] initWithAccessory:accessory
                                              forProtocol:protocolString];

    if (!self->_session) {
      [self addDebugString:@"Failed opening session\n"];
      NSLog(@"BYB iOS EASession init failed for protocol=%@ accessory=%@ "
            @"connectionID=%u",
            protocolString, accessory.name, accessory.connectionID);
      return;
    }

    NSLog(@"BYB iOS EASession created protocol=%@ accessory=%@ connectionID=%u",
          protocolString, accessory.name, accessory.connectionID);

    self->cBufHead = 0;
    self->cBufTail = 0;
    // [[BBAudioManager bbAudioManager]
    // addMfiDeviceWithModelNumber:accessory.modelNumber
    // andSerial:accessory.serialNumber];

    [self addDebugString:@"Opening streams...\n"];
    NSInputStream *inStream = self->_session.inputStream;
    NSOutputStream *outStream = self->_session.outputStream;
    [inStream setDelegate:self];
    [outStream setDelegate:self];
    // Flutter invokes method-channel handlers off the main thread; NSStream
    // delegates only fire if streams are scheduled on a run loop that is
    // actually running (typically the main run loop).
    [inStream scheduleInRunLoop:mainLoop forMode:NSDefaultRunLoopMode];
    [outStream scheduleInRunLoop:mainLoop forMode:NSDefaultRunLoopMode];
    [inStream open];
    [outStream open];

    [self setupProtocol];
  };

  if ([NSThread isMainThread]) {
    openWork();
  } else {
    dispatch_async(dispatch_get_main_queue(), openWork);
  }
}

// Close an open session and disconnect the associated streams.
- (void)closeSession {
  [self cancelDeferredAccessorySessionOpenIfNeeded];
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
    dispatch_async(dispatch_get_main_queue(), work);
  }
}

// Init instance with the requested accessory protocol. Open a session if the
// accessory is already connected and start listening for connect/disconnect
// events.
- (id)initWithProtocol:(NSString *)protocol {

  if ([[UIApplication sharedApplication] isProtectedDataAvailable]) {
    NSLog(@"Device is unlocked! initWithProtocol");
  } else {
    NSLog(@"Device is locked! initWithProtocol");
  }
  self = [super init];
  if (self) {
    _debugString = [NSMutableString stringWithString:@"initWithProtocol:\n"];
    _txData = [[NSMutableData alloc] init];
    _protocol = [protocol copy];

    // Start session if an accessory is already attached
    [self openSessionWithProtocolDeferringUntilActive:_protocol];

    void (^reg)(void) = ^{
      [self registerExternalAccessoryObserversOnMainIfNeeded];
    };
    if ([NSThread isMainThread]) {
      reg();
    } else {
      dispatch_sync(dispatch_get_main_queue(), reg);
    }
  }
  return self;
}

- (EAAccessory *)getCurrentAccessoryWithProtocol:(NSString *)protocol {
  NSArray *accessories =
      [[EAAccessoryManager sharedAccessoryManager] connectedAccessories];
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

// On instance removal, stop listening for connect/disconnect events and close
// the session if there is one.
- (void)dealloc {
  NSLog(@"DEALLOC BYB iOS accessory plugin");
  [self cancelDeferredAccessorySessionOpenIfNeeded];
  if (_didRegisterEAObservers) {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [[EAAccessoryManager sharedAccessoryManager]
        unregisterForLocalNotifications];
    _didRegisterEAObservers = NO;
  }
  [self closeSession];
  [_protocol release];
  _protocol = nil;
  [_pendingDeferProtocol release];
  _pendingDeferProtocol = nil;
}

// Checks if the accessory is currently connected.
- (bool)isConnected {
  if (_session == nil) {
    return false;
  }
  EAAccessory *accessory = [_session accessory];
  return accessory != nil && [accessory isConnected];
}

#pragma mark - EAAccessory Notifications

// Observer method for accessory connect notifications posted by the
// EAAccessoryManager. Attemps to open a session with the desired protocol if
// one is not already open.
- (void)accessoryDidConnect:(NSNotification *)notification {
  EAAccessory *connected =
      [[notification userInfo] objectForKey:EAAccessoryKey];
  NSLog(@"BYB ACCESSORY - accessoryDidConnect name=%@ protocols=%@ "
        @"connectionID=%u",
        connected.name, connected.protocolStrings, connected.connectionID);
  if ([[UIApplication sharedApplication] isProtectedDataAvailable]) {
    if (_protocol == nil || _protocol.length == 0) {
      NSLog(@"BYB ACCESSORY - accessoryDidConnect (default protocol)");
      [_protocol release];
      _protocol = [@"com.backyardbrains.spikerbox" copy];
    } else {
      NSLog(@"BYB ACCESSORY - accessoryDidConnect %@", _protocol);
    }
  } else {
    NSLog(@"BYB ACCESSORY - Device is locked! accessoryDidConnect");
  }
  [self addDebugString:@"DidConnect:\n"];
  if (_session == nil) {
    [self openSessionWithProtocol:_protocol];
  }
}

// Observer method for accessory disconnect notifications posted by the
// EAAccessoryManager. Closes the session if our accessory disconnected.
- (void)accessoryDidDisconnect:(NSNotification *)notification {
  EAAccessory *disconnectedAccessory =
      [[notification userInfo] objectForKey:EAAccessoryKey];
  NSArray *protocolStrings = [disconnectedAccessory protocolStrings];
  NSLog(@"BYB ACCESSORY - accessoryDidDisconnect name=%@ protocols=%@ "
        @"connectionID=%u",
        disconnectedAccessory.name, protocolStrings,
        disconnectedAccessory.connectionID);

  [self addDebugString:[NSString stringWithFormat:@"DidDisconnect: %@\n",
                                                  protocolStrings]];
  if ([protocolStrings containsObject:_protocol]) {
    [self closeSession];
  }
}

- (void)setupProtocol {
  // init all things that you need
}

- (FlutterError *_Nullable)onListenWithArguments:(id _Nullable)arguments
                                       eventSink:(FlutterEventSink)events {
  _rxEventSink = events;
  [self flushPendingRxToEventSink];
  return nil;
}

- (FlutterError *_Nullable)onCancelWithArguments:(id _Nullable)arguments {
  _rxEventSink = nil;
  return nil;
}

@end
