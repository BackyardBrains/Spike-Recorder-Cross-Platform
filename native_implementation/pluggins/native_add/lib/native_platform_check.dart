// import 'dart:async';
//
// import 'dart:io';
// import 'dart:isolate';
// import 'dart:typed_data';
// import 'package:ffi/ffi.dart';
// import 'package:native_add/main.dart';
//
// const String _libName = 'native_add';
//
// Isolate? _helperIsolate;
// SendPort? _helperIsolateSendPort;
//
// Future<void> spawnHelperIsolate() async {
//   if (_helperIsolate == null) {
//     // _helperIsolateSendPort = await _mHelperIsolateSendPort;
//     print("Helper isolate spawned");
//   }
// }