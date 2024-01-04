/*
For Mac:
Pods->native_add->Frameworks and libraries
AudioToolbox.framework
AudioUnit.framework
CoreAudio.framework
CoreFoundation.framework
*/

import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ffi' as ffi;
import 'package:native_add/main.dart';
import 'package:native_add/model/enveloping_data/enveloping_config.dart';
import 'package:native_add/model/model.dart';

import 'allocation.dart';

const String _libName = 'native_add';

Isolate? _helperIsolate;
SendPort? _helperIsolateSendPort;

int maxValue = 0;
int minValue = 0;
int offset = 0;

// TODO: Remove, for testing only
// int channelIndex = 0;

const int _channelCount = 6;

// TODO: Increase the buffer size to accomodate larger packets coming from main isolate
/// Number of Int16 values to be held in buffer for each channel
const int _bufferLength = 2000;
// EnvelopingConfig? envelopingConfig;
int positionSinceBeginning = 0;

/// Buffer shared between Dart, JS and WASM
///
/// Memory not freed as it will used throughout the life of the program
final List<ffi.Pointer<ffi.Int16>> _mPointer = List.generate(
  _channelCount,
  (index) => allocate<ffi.Int16>(
    count: _bufferLength,
    sizeOfType: ffi.sizeOf<ffi.Int16>(),
  ),
);

final List<EnvelopingConfig> _envelopingConfig = List.generate(
  _channelCount,
  (index) => EnvelopingConfig(),
);

int is50Hertz = 0;

Future<void> spawnHelperIsolate() async {
  if (_helperIsolate == null) {
    _helperIsolateSendPort = await _mHelperIsolateSendPort;
    print("Helper isolate spawned");
  }
}

/// [duration] in milliseconds

// Future<double> initHighValueFilter(int){}
/// The dynamic library in which the symbols for [NativeAddBindings] can be found.
final ffi.DynamicLibrary _dylib = () {
  if (Platform.isMacOS || Platform.isIOS) {
    return ffi.DynamicLibrary.open('$_libName.framework/$_libName');
  }
  if (Platform.isAndroid || Platform.isLinux) {
    return ffi.DynamicLibrary.open('lib$_libName.so');
  }
  if (Platform.isWindows) {
    return ffi.DynamicLibrary.open('$_libName.dll');
  }

  throw UnsupportedError('Unknown platform: ${Platform.operatingSystem}');
}();

/// The bindings to the native functions in [_dylib].
final NativeAddBindings _bindings = NativeAddBindings(_dylib);

/// Typically sent from one isolate to another.
class _IsolateRequest {
  final int id;
  final List<int> dataArray;
  final int dataLength;
  final int sampleLength;
  final int channelIndex;
  final int skipCount;

  const _IsolateRequest(
    this.id,
    this.skipCount,
    this.sampleLength,
    this.dataArray,
    this.dataLength,
    this.channelIndex,
  );
}

/// Typically sent from one isolate to another.
class _IsolateResponse {
  final int id;
  final Uint8List result;

  const _IsolateResponse(this.id, this.result);
}

/// Counter to identify [_IsolateRequest]s and [_IsolateResponse]s.
int _nextRequestId = 0;

/// Mapping from [_IsolateRequest] `id`s to the completers corresponding to the correct future of the pending request.
final Map<int, Completer<Uint8List>> _isolateResults =
    <int, Completer<Uint8List>>{};

/// The SendPort belonging to the helper isolate.
Future<SendPort> _mHelperIsolateSendPort = () async {
  // The helper isolate is going to send us back a SendPort, which we want to wait for.
  final Completer<SendPort> sendPortCompleter = Completer<SendPort>();

  // Receive port on the main isolate to receive messages from the helper.
  // We receive two types of messages:
  // 1. A port to send messages on.
  // 2. Responses to requests we sent.
  final ReceivePort receivePort = ReceivePort()
    ..listen((dynamic data) {
      if (data is SendPort) {
        // The helper isolate sent us the port on which we can sent it requests.
        sendPortCompleter.complete(data);
        return;
      }
      if (data is _IsolateResponse) {
        // print("the mpointer ${data.result.map((e) => e)}");
        // print("Response is ${data.result.length}");
        // The helper isolate sent us a response to a request we sent.
        // print("the length of  ${data.result.length}");
        if (!_isolateResults.containsKey(data.id)) {
          print("Response id mismatch");
          return;
        }
        // Extract the completer from the Map
        final Completer<Uint8List> completer = _isolateResults[data.id]!;

        // Complete the completer with its result
        // print("the result index ");
        completer.complete(data.result);

        // Remove the completer from the Map and free up memory
        _isolateResults.remove(data.id);
        return;
      }
      throw UnsupportedError('Unsupported message type: ${data.runtimeType}');
    });

  _helperIsolate = await Isolate.spawn((SendPort sendPort) async {
    bool isLowPassFilter = false;
    bool isHighPassFilter = false;
    bool isNotchPassFilter = false;

    final ReceivePort helperReceivePort = ReceivePort()
      ..listen((dynamic data) async {
        if (data is FilterSetup) {
          switch (data.filterType) {
            case FilterType.notchFilter:
              isNotchPassFilter = data.isFilterOn;
              initNotchPassFilter(data);
              break;
            case FilterType.highPassFilter:
              isHighPassFilter = data.isFilterOn;
              initHighPassFilter(data);
              break;
            case FilterType.lowPassFilter:
              isLowPassFilter = data.isFilterOn;
              initLowPassFilter(data);
              break;
          }
        } else if (data is _IsolateRequest) {
          _setValuesInSharedBuffer(
              data.dataArray, data.dataLength, data.channelIndex);
          if (isHighPassFilter) {
            _bindings.applyHighPassFilter(data.channelIndex,
                _mPointer[data.channelIndex], data.dataLength);
          }
          if (isLowPassFilter) {
            _bindings.applyLowPassFilter(data.channelIndex,
                _mPointer[data.channelIndex], data.dataLength);
          }
          if (isNotchPassFilter) {
            _bindings.applyNotchPassFilter(is50Hertz, data.channelIndex,
                _mPointer[data.channelIndex], data.dataLength);
          }

          _bindings.addDataToSampleBuffer(
              _mPointer[data.channelIndex], data.dataLength);

          positionSinceBeginning += data.dataLength;

          // printTheValue(sampleLength, skipCount);
          // print(
          //     "the sampleLength ${_envelopingConfig[data.channelIndex].sampleLength}");
          // print(
          //     "the skip Count ${_envelopingConfig[data.channelIndex].skipCount}");
          _bindings.getEnvelopFromSampleBuffer(
              positionSinceBeginning - data.sampleLength,
              data.sampleLength,
              data.skipCount,
              _envelopingConfig[data.channelIndex].envelopingBuffer);

          final _IsolateResponse response = _IsolateResponse(
              data.id,
              _envelopingConfig[data.channelIndex]
                  .envelopingBuffer
                  .asTypedList(
                      _envelopingConfig[data.channelIndex].envelopBufferLength)
                  .buffer
                  .asUint8List());

          // print(
          //     "envelopBufferLength: ${_envelopingConfig[data.channelIndex].envelopBufferLength}");

          // final _IsolateResponse response = _IsolateResponse(
          //     data.id,
          //     _mPointer[data.channelIndex]
          //         .asTypedList(data.dataLength)
          //         .buffer
          //         .asUint8List());
          sendPort.send(response);
          return;
        }
      });

    // Send the port to the main isolate on which we can receive requests.
    sendPort.send(helperReceivePort.sendPort);
  }, receivePort.sendPort);

  // Wait until the helper isolate has sent us back the SendPort on which we
  // can start sending requests.
  return sendPortCompleter.future;
}();
int tempBufferSize = 0;
int tempSkipCount = 0;

/// Set values int the native buffer
void _setValuesInSharedBuffer(
    List<int> data, int valueCount, int channelIndex) {
  Int16List bytes = _mPointer[channelIndex].asTypedList(valueCount);
  bytes.setAll(0, data);
  return;
}

/// Called for every packet
Future<Uint8List> filterArrayElements({
  required List<int> array,
  required int length,
  required int channelIndex,
  required int sampleLength,
  required int skipCount,
}) async {
  final int requestId = _nextRequestId++;

  final _IsolateRequest request = _IsolateRequest(
      requestId, skipCount, sampleLength, array, length, channelIndex);
  final Completer<Uint8List> completer = Completer<Uint8List>();
  _isolateResults[requestId] = completer;

  _helperIsolateSendPort?.send(request);
  return completer.future;
}

bool initHighPassFilter(FilterSetup filterBaseSettingsModel) {
  _helperIsolateSendPort?.send(filterBaseSettingsModel);
  _bindings.initHighPassFilter(
    filterBaseSettingsModel.channelCount,
    double.parse(
        filterBaseSettingsModel.filterConfiguration.sampleRate.toString()),
    double.parse(
        filterBaseSettingsModel.filterConfiguration.cutOffFrequency.toString()),
    0.5,
  );
  return true;
}

bool initLowPassFilter(FilterSetup filterBaseSettingsModel) {
  _helperIsolateSendPort?.send(filterBaseSettingsModel);
  _bindings.initLowPassFilter(
    filterBaseSettingsModel.channelCount,
    double.parse(
        filterBaseSettingsModel.filterConfiguration.sampleRate.toString()),
    double.parse(
        filterBaseSettingsModel.filterConfiguration.cutOffFrequency.toString()),
    0.5,
  );
  return true;
}

bool initNotchPassFilter(FilterSetup filterBaseSettingsModel) {
  _helperIsolateSendPort?.send(filterBaseSettingsModel);
  is50Hertz =
      filterBaseSettingsModel.filterConfiguration.cutOffFrequency == 50 ? 1 : 0;

  _bindings.initNotchPassFilter(
    is50Hertz,
    filterBaseSettingsModel.channelCount,
    double.parse(
        filterBaseSettingsModel.filterConfiguration.sampleRate.toString()),
    double.parse(
        filterBaseSettingsModel.filterConfiguration.cutOffFrequency.toString()),
    0.5,
  );

  return true;
}
