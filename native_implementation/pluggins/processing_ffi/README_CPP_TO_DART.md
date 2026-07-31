# C++ to Dart Messaging Mechanism

This document explains how to send messages from C++ to Dart using the Dart API DL (Dynamically Linked API).

## Overview

The mechanism allows C++ code to send messages to Dart code using `Dart_PostCObject_DL`. This is useful for:
- Sending notifications from C++ to Dart
- Streaming data from C++ processing to Dart
- Error reporting from C++ to Dart
- Any asynchronous communication from native code to Dart

## Setup

### 1. Initialize Dart API DL

Before using any Dart API DL functions, you must initialize them. This is typically done once at application startup:

```dart
import 'dart:ffi';
import 'dart:io';

// Get the dynamic library
final dylib = DynamicLibrary.open('libprocessing_ffi.so'); // Adjust for your platform

// Look up Dart_InitializeApiDL function
final initializeApiDL = dylib.lookupFunction<
    IntPtr Function(Pointer<Void>),
    int Function(Pointer<Void>)>('Dart_InitializeApiDL');

// Initialize with data from Dart VM
final result = initializeApiDL(NativeApi.initializeApiDLData);
if (result != 0) {
  print('Error: Failed to initialize Dart API DL');
}
```

**Important**: Make sure `dart_api_dl.c` is linked into your native library. This file should be compiled and linked with your C++ code.

### 2. Create a ReceivePort in Dart

```dart
import 'dart:isolate';

final receivePort = ReceivePort();
final portId = receivePort.sendPort.nativePort;
```

### 3. Register the Port with C++

```dart
final registerResult = processingBindings.registerDartPort(portId);
if (registerResult != 0) {
  print('Error: Failed to register Dart port');
}
```

### 4. Listen for Messages

```dart
receivePort.listen((message) {
  if (message is String) {
    print('Received from C++: $message');
  } else {
    print('Received message: $message');
  }
});
```

### 5. Send Messages from C++

In your C++ code, you can now send messages:

```cpp
// Example: Send a string message
Dart_CObject dart_message;
dart_message.type = Dart_CObject_kString;
dart_message.value.as_string = "Hello from C++!";
Dart_PostCObject_DL(dart_port, &dart_message);
```

## API Reference

### C++ Functions

#### `processing_register_dart_port(int64_t port)`
Registers a Dart port for receiving messages from C++.

- **Parameters**: `port` - The native port ID from `SendPort.nativePort`
- **Returns**: `0` on success, `-1` on error

#### `processing_unregister_dart_port()`
Unregisters the Dart port. Call this when you're done receiving messages.

#### `processing_send_test_message(const char* message)`
Example function that sends a test string message from C++ to Dart.

- **Parameters**: `message` - The message string to send
- **Returns**: `0` on success, `-1` on error

### Helper Function

The C++ code includes a helper function `send_message_to_dart()` that you can use to send custom messages:

```cpp
static bool send_message_to_dart(Dart_CObject* message) {
    if (dart_port == 0) {
        return false; // Port not registered
    }
    return Dart_PostCObject_DL(dart_port, message);
}
```

## Message Types

You can send various types of messages using `Dart_CObject`:

- **String**: `Dart_CObject_kString`
- **Integer**: `Dart_CObject_kInt32` or `Dart_CObject_kInt64`
- **Double**: `Dart_CObject_kDouble`
- **Bool**: `Dart_CObject_kBool`
- **Array**: `Dart_CObject_kArray`
- **TypedData**: `Dart_CObject_kTypedData`

See `dart_native_api.h` for the complete list of supported types.

## Example Usage

See `example_cpp_to_dart_messaging.dart` for a complete working example.

## Thread Safety

`Dart_PostCObject_DL` can be called from any thread, making it safe to use from background threads in C++.

## Cleanup

Always unregister the port and close the ReceivePort when done:

```dart
processingBindings.unregisterDartPort();
receivePort.close();
```

## Troubleshooting

1. **Messages not received**: Make sure `Dart_InitializeApiDL` was called successfully
2. **Port registration fails**: Check that the port ID is valid (not 0)
3. **Compilation errors**: Ensure `dart_api_dl.h` is included and `dart_api_dl.c` is linked
