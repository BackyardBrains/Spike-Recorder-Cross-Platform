import 'dart:ffi';
import 'dart:isolate';
import 'package:ffi/ffi.dart';
import 'package:processing_ffi/processing_bindings.dart';

/// Example demonstrating how to send messages from C++ to Dart
/// 
/// This example shows:
/// 1. How to create a ReceivePort to receive messages from C++
/// 2. How to register the port with C++
/// 3. How to listen for messages sent from C++
/// 4. How to send a test message from C++ to Dart
/// 
/// NOTE: Before using this, you must initialize Dart_InitializeApiDL.
/// This is typically done once when your app starts. You need to link
/// dart_api_dl.c into your native library and call:
///   Dart_InitializeApiDL(NativeApi.initializeApiDLData)
void main() async {
  print('=== C++ to Dart Messaging Example ===\n');
  
  // IMPORTANT: Dart_InitializeApiDL must be called before using any Dart API DL functions
  // This should be done once at app startup. If not already done, uncomment and adapt:
  /*
  final dylib = DynamicLibrary.open('libprocessing_ffi.so'); // Adjust for your platform
  final initializeApiDL = dylib.lookupFunction<
      IntPtr Function(Pointer<Void>),
      int Function(Pointer<Void>)>('Dart_InitializeApiDL');
  final initResult = initializeApiDL(NativeApi.initializeApiDLData);
  if (initResult != 0) {
    print('Error: Failed to initialize Dart API DL: $initResult');
    return;
  }
  */
  print('Assuming Dart API DL is already initialized...\n');

  // Step 2: Create a ReceivePort to receive messages from C++
  final receivePort = ReceivePort();
  
  // Step 3: Register the port with C++
  // The port ID is used by C++ to send messages back to Dart
  final portId = receivePort.sendPort.nativePort;
  final registerResult = processingBindings.registerDartPort(portId);
  
  if (registerResult != 0) {
    print('Error: Failed to register Dart port: $registerResult');
    receivePort.close();
    return;
  }
  print('✓ Dart port registered: $portId');

  // Step 4: Listen for messages from C++
  receivePort.listen((message) {
    if (message is String) {
      print('📨 Received message from C++: $message');
    } else {
      print('📨 Received message from C++ (type: ${message.runtimeType}): $message');
    }
  });

  print('\n--- Listening for messages from C++ ---\n');

  // Step 5: Send a test message from C++ to Dart
  // This demonstrates calling a C++ function that sends a message back to Dart
  print('Sending test message from C++...');
  
  final testMessage = 'Hello from C++! This is a test message.'.toNativeUtf8();
  final sendResult = processingBindings.sendTestMessage(testMessage);
  
  if (sendResult != 0) {
    print('Error: Failed to send test message: $sendResult');
  } else {
    print('✓ Test message sent successfully');
  }
  
  // Clean up the native string
  malloc.free(testMessage);

  // Wait a bit to receive the message
  await Future.delayed(Duration(seconds: 1));

  // Cleanup: Unregister the port
  processingBindings.unregisterDartPort();
  receivePort.close();
  print('\n✓ Port unregistered and closed');
  print('\n=== Example completed ===');
}
