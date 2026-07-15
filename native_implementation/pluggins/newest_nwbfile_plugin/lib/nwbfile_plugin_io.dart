/// Native (IO) implementation via dart:ffi.
library nwbfile_plugin_io;

import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'nwbfile_plugin_bindings_generated.dart';

/// No-op on native platforms (dynamic library loads eagerly).
Future<void> ensureInitialized() async {}

int sum(int a, int b) => _bindings.sum(a, b);

int processingInit(
  String path,
  int sampleRate,
  int channelCount,
  String deviceInfo,
  String deviceManufacturer,
) {
  final pathPtr = path.toNativeUtf8().cast<Char>();
  final infoPtr = deviceInfo.toNativeUtf8().cast<Char>();
  final mfrPtr = deviceManufacturer.toNativeUtf8().cast<Char>();
  try {
    return _bindings.processing_init(
      pathPtr,
      sampleRate,
      channelCount,
      infoPtr,
      mfrPtr,
    );
  } finally {
    malloc.free(pathPtr);
    malloc.free(infoPtr);
    malloc.free(mfrPtr);
  }
}

int nwbfileAddElectricalSeries(
  Int16List inSamples,
  Int32List samplesCount,
  int selectedChannel,
  int channelCount,
  int isFinishRecording,
) {
  final samplesPtr = malloc<Int16>(inSamples.length);
  final countsPtr = malloc<Int32>(samplesCount.length);
  try {
    samplesPtr.asTypedList(inSamples.length).setAll(0, inSamples);
    countsPtr.asTypedList(samplesCount.length).setAll(0, samplesCount);
    return _bindings.nwbfile_add_electrical_series(
      samplesPtr,
      countsPtr,
      selectedChannel,
      channelCount,
      isFinishRecording,
    );
  } finally {
    malloc.free(samplesPtr);
    malloc.free(countsPtr);
  }
}

/// Appends one EventsTable row. Returns the new row index, or -1 on failure.
int nwbfileAddEvent(double timestampSeconds, int eventLabel) =>
    _bindings.nwbfile_add_event(timestampSeconds, eventLabel);

/// Updates an existing EventsTable row. Returns 0 on success, -1 on failure.
int nwbfileUpdateEvent(int rowIndex, double timestampSeconds, int eventLabel) =>
    _bindings.nwbfile_update_event(rowIndex, timestampSeconds, eventLabel);

/// Soft-deletes an EventsTable row. Returns 0 on success, -1 on failure.
int nwbfileDeleteEvent(int rowIndex) =>
    _bindings.nwbfile_delete_event(rowIndex);

int nwbfileReadElectricalSeries(
  Int16List outSamples,
  Int32List outSampleCounts,
  int selectedChannel,
  int channelCount,
) {
  final samplesPtr = malloc<Int16>(outSamples.length);
  final countsPtr = malloc<Int32>(outSampleCounts.length);
  try {
    final status = _bindings.nwbfile_read_electrical_series(
      samplesPtr,
      countsPtr,
      selectedChannel,
      channelCount,
    );
    final count = countsPtr.value.clamp(0, outSamples.length);
    outSamples.setRange(0, count, samplesPtr.asTypedList(count));
    outSampleCounts.setAll(
      0,
      countsPtr.asTypedList(outSampleCounts.length),
    );
    return status;
  } finally {
    malloc.free(samplesPtr);
    malloc.free(countsPtr);
  }
}

int nwbfileSeekElectricalSeries(
  String path,
  Int16List outSamples,
  Int32List outSampleCounts,
  Int32List outConfig,
  int startTimeStamp,
  int endTimeStamp,
  int startChannel,
  int endChannel,
) {
  final pathPtr = path.toNativeUtf8().cast<Char>();
  final samplesPtr = malloc<Int16>(outSamples.length);
  final countsPtr = malloc<Int32>(outSampleCounts.length);
  final configPtr = malloc<Int32>(outConfig.length);
  try {
    final status = _bindings.nwbfile_seek_electrical_series(
      pathPtr,
      samplesPtr,
      countsPtr,
      configPtr,
      startTimeStamp,
      endTimeStamp,
      startChannel,
      endChannel,
    );
    final count = countsPtr.value;
    final channels = endChannel - startChannel + 1;
    final total = (count * channels).clamp(0, outSamples.length);
    outSamples.setRange(0, total, samplesPtr.asTypedList(total));
    outSampleCounts.setAll(
      0,
      countsPtr.asTypedList(outSampleCounts.length),
    );
    outConfig.setAll(0, configPtr.asTypedList(outConfig.length));
    return status;
  } finally {
    malloc.free(pathPtr);
    malloc.free(samplesPtr);
    malloc.free(countsPtr);
    malloc.free(configPtr);
  }
}

int getNwbFileSize() => _bindings.get_nwb_file_size();

void cleanupNwbData() => _bindings.cleanup_nwb_data();

Future<int> sumAsync(int a, int b) async {
  final SendPort helperIsolateSendPort = await _helperIsolateSendPort;
  final int requestId = _nextSumRequestId++;
  final _SumRequest request = _SumRequest(requestId, a, b);
  final Completer<int> completer = Completer<int>();
  _sumRequests[requestId] = completer;
  helperIsolateSendPort.send(request);
  return completer.future;
}

const String _libName = 'nwbfile_plugin';

final DynamicLibrary _dylib = () {
  if (Platform.isIOS) {
    try {
      return DynamicLibrary.process();
    } catch (_) {
      return DynamicLibrary.open('$_libName.framework/$_libName');
    }
  }
  if (Platform.isMacOS) {
    return DynamicLibrary.open('$_libName.framework/$_libName');
  }
  if (Platform.isAndroid || Platform.isLinux) {
    return DynamicLibrary.open('lib$_libName.so');
  }
  if (Platform.isWindows) {
    return DynamicLibrary.open('$_libName.dll');
  }
  throw UnsupportedError('Unknown platform: ${Platform.operatingSystem}');
}();

final NwbfilePluginBindings _bindings = NwbfilePluginBindings(_dylib);

class _SumRequest {
  final int id;
  final int a;
  final int b;

  const _SumRequest(this.id, this.a, this.b);
}

class _SumResponse {
  final int id;
  final int result;

  const _SumResponse(this.id, this.result);
}

int _nextSumRequestId = 0;
final Map<int, Completer<int>> _sumRequests = <int, Completer<int>>{};

Future<SendPort> _helperIsolateSendPort = () async {
  final Completer<SendPort> completer = Completer<SendPort>();
  final ReceivePort receivePort = ReceivePort()
    ..listen((dynamic data) {
      if (data is SendPort) {
        completer.complete(data);
        return;
      }
      if (data is _SumResponse) {
        final Completer<int> requestCompleter = _sumRequests[data.id]!;
        _sumRequests.remove(data.id);
        requestCompleter.complete(data.result);
        return;
      }
      throw UnsupportedError('Unsupported message type: ${data.runtimeType}');
    });

  await Isolate.spawn((SendPort sendPort) async {
    final ReceivePort helperReceivePort = ReceivePort()
      ..listen((dynamic data) {
        if (data is _SumRequest) {
          final int result = _bindings.sum_long_running(data.a, data.b);
          sendPort.send(_SumResponse(data.id, result));
          return;
        }
        throw UnsupportedError('Unsupported message type: ${data.runtimeType}');
      });
    sendPort.send(helperReceivePort.sendPort);
  }, receivePort.sendPort);

  return completer.future;
}();
