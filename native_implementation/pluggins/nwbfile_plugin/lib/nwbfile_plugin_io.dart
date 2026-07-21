/// Native (IO) implementation via dart:ffi.
// ignore_for_file: non_constant_identifier_names
library nwbfile_plugin_io;

import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';

import 'nwbfile_plugin_bindings_generated.dart';

/// No-op on native platforms (dynamic library loads eagerly).
Future<void> ensureInitialized() async {}

int sum(int a, int b) => _bindings.sum(a, b);

/// Direct pass-through to the native `processing_init`. Callers own the
/// `Pointer<Char>` buffers (e.g. via `toNativeUtf8().cast<Char>()`) and are
/// responsible for freeing them once this call returns.
int processingInit(
  Pointer<Char> path,
  int sampleRate,
  int channelCount,
  Pointer<Char> deviceInfo,
  Pointer<Char> deviceManufacturer,
) =>
    _bindings.processing_init(
      path,
      sampleRate,
      channelCount,
      deviceInfo,
      deviceManufacturer,
    );

/// Direct pass-through to the native `nwbfile_add_electrical_series`.
/// Callers own the `Pointer<Int16>`/`Pointer<Int32>` buffers and are
/// responsible for allocating and freeing them.
int nwbfile_add_electrical_series(
  Pointer<Int16> inSamples,
  Pointer<Int32> samplesCount,
  int selectedChannel,
  int channelCount,
  int isFinishRecording,
) =>
    _bindings.nwbfile_add_electrical_series(
      inSamples,
      samplesCount,
      selectedChannel,
      channelCount,
      isFinishRecording,
    );

/// Creates a per-channel SpikeEventSeries before SWMR recording starts.
/// Returns the recording container index, or -1 on failure.
int nwbfileCreateSpikeEventSeries(int channelIndex) =>
    _bindings.nwbfile_create_spike_event_series(channelIndex);

/// Writes one spike waveform snippet in volts. Returns 0 on success, -1 on failure.
int nwbfileWriteSpikeEvent(
  int channelIndex,
  double timestampSeconds,
  Pointer<Float> waveform,
  int numSamples,
) =>
    _bindings.nwbfile_write_spike_event(
      channelIndex,
      timestampSeconds,
      waveform,
      numSamples,
    );

/// Returns the number of spike events written for [channelIndex], or -1 on failure.
int nwbfileGetSpikeEventCount(int channelIndex) =>
    _bindings.nwbfile_get_spike_event_count(channelIndex);

/// Appends one EventsTable row. Returns the new row index, or -1 on failure.
int nwbfileAddEvent(double timestampSeconds, int eventLabel) =>
    _bindings.nwbfile_add_event(timestampSeconds, eventLabel);

/// Updates an existing EventsTable row. Returns 0 on success, -1 on failure.
int nwbfileUpdateEvent(int rowIndex, double timestampSeconds, int eventLabel) =>
    _bindings.nwbfile_update_event(rowIndex, timestampSeconds, eventLabel);

/// Soft-deletes an EventsTable row. Returns 0 on success, -1 on failure.
int nwbfileDeleteEvent(int rowIndex) =>
    _bindings.nwbfile_delete_event(rowIndex);

/// Reads one EventsTable row by index into the provided output pointers.
/// Callers own the `Pointer<Float>`/`Pointer<Int32>`/`Pointer<Uint8>`
/// buffers and are responsible for allocating and freeing them.
/// Returns 0 on success, -1 on failure (e.g. invalid rowIndex).
int nwbfileReadEvent(
  int rowIndex,
  Pointer<Float> outTimestampSeconds,
  Pointer<Int32> outEventLabel,
  Pointer<Uint8> outDeleted,
) =>
    _bindings.nwbfile_read_event(
      rowIndex,
      outTimestampSeconds,
      outEventLabel,
      outDeleted,
    );

/// Returns the total number of EventsTable rows added so far (including
/// soft-deleted rows).
int nwbfileGetEventCount() => _bindings.nwbfile_get_event_count();

/// Upsert a MeaningsTable label for an event_type [value].
/// Returns the meanings row index, or -1 on failure.
int nwbfileSetMeaning(int value, String meaning) {
  final meaningPtr = meaning.toNativeUtf8().cast<Char>();
  try {
    return _bindings.nwbfile_set_meaning(value, meaningPtr);
  } finally {
    malloc.free(meaningPtr);
  }
}

/// Number of MeaningsTable rows currently registered.
int nwbfileGetMeaningCount() => _bindings.nwbfile_get_meaning_count();

/// Reads one MeaningsTable row by index. Returns null on failure.
({int value, String meaning})? nwbfileReadMeaning(int rowIndex) {
  final outValue = calloc<Int32>();
  final outMeaning = calloc<Char>(256);
  try {
    final status = _bindings.nwbfile_read_meaning(
      rowIndex,
      outValue,
      outMeaning,
      256,
    );
    if (status != 0) return null;
    return (
      value: outValue.value,
      meaning: outMeaning.cast<Utf8>().toDartString(),
    );
  } finally {
    calloc.free(outValue);
    calloc.free(outMeaning);
  }
}

/// Looks up the meaning label for an event_type [value].
/// Returns null if the value is not registered.
String? nwbfileFindMeaning(int value) {
  final outMeaning = calloc<Char>(256);
  try {
    final status = _bindings.nwbfile_find_meaning(value, outMeaning, 256);
    if (status != 0) return null;
    return outMeaning.cast<Utf8>().toDartString();
  } finally {
    calloc.free(outMeaning);
  }
}

/// Direct pass-through to the native `nwbfile_read_electrical_series`.
/// Callers own the `Pointer<Int16>`/`Pointer<Int32>` buffers.
int nwbfile_read_electrical_series(
  Pointer<Int16> outSamples,
  Pointer<Int32> outSampleCounts,
  int selectedChannel,
  int channelCount,
) =>
    _bindings.nwbfile_read_electrical_series(
      outSamples,
      outSampleCounts,
      selectedChannel,
      channelCount,
    );

/// Direct pass-through to the native `nwbfile_seek_electrical_series`.
/// Callers own the `Pointer<Char>`/`Pointer<Int16>`/`Pointer<Int32>` buffers
/// and are responsible for allocating and freeing them.
int nwbfile_seek_electrical_series(
  Pointer<Char> path,
  Pointer<Int16> outSamples,
  Pointer<Int32> outSampleCounts,
  Pointer<Int32> outConfig,
  int startTimeStamp,
  int endTimeStamp,
  int startChannel,
  int endChannel,
) =>
    _bindings.nwbfile_seek_electrical_series(
      path,
      outSamples,
      outSampleCounts,
      outConfig,
      startTimeStamp,
      endTimeStamp,
      startChannel,
      endChannel,
    );

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
