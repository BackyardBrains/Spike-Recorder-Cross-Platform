/// Web (HTML/JS) implementation using the Emscripten `NWBPlugin` module.
library nwbfile_plugin_html;

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

@JS('NWBPlugin')
external JSFunction? get _nwbPluginFactory;

extension type _NwbModule(JSObject _) implements JSObject {
  @JS('ccall')
  external JSAny? ccall(
    JSString name,
    JSString returnType,
    JSArray<JSAny?> argTypes,
    JSArray<JSAny?> args,
  );

  @JS('FS')
  external JSObject get fs;

  @JS('_malloc')
  external int malloc(int size);

  @JS('_free')
  external void free(int ptr);

  @JS('HEAPU8')
  external JSUint8Array get heapU8;
}

_NwbModule? _module;
Completer<void>? _initCompleter;

/// Load and instantiate `NWBPlugin` (from `web/nwb/nwbfile_plugin.js`).
Future<void> ensureInitialized() async {
  if (_module != null) return;
  if (_initCompleter != null) return _initCompleter!.future;
  _initCompleter = Completer<void>();
  try {
    final factory = _nwbPluginFactory;
    if (factory == null) {
      throw StateError(
        'NWBPlugin is not defined. Include web/nwb/nwbfile_plugin.js '
        'before Flutter bootstrap (see web/index.html).',
      );
    }
    final JSAny? result = factory.callAsFunction();
    final JSObject raw;
    if (result is JSPromise) {
      raw = (await result.toDart) as JSObject;
    } else {
      raw = result as JSObject;
    }
    _module = _NwbModule(raw);

    try {
      final fs = _module!.fs;
      try {
        fs.callMethod('mkdir'.toJS, '/nwb'.toJS);
      } catch (_) {
        // directory may already exist
      }
    } catch (_) {}

    _initCompleter!.complete();
  } catch (e, st) {
    _initCompleter!.completeError(e, st);
    _initCompleter = null;
    rethrow;
  }
}

_NwbModule get _m {
  final m = _module;
  if (m == null) {
    throw StateError(
      'Call ensureInitialized() before using NWB APIs on web.',
    );
  }
  return m;
}

num _ccallNum(
  String name,
  List<String> argTypes,
  List<JSAny?> args,
) {
  final result = _m.ccall(
    name.toJS,
    'number'.toJS,
    argTypes.map((t) => t.toJS).toList().toJS,
    args.toJS,
  );
  return (result as JSNumber).toDartDouble;
}

void _ccallVoid(String name, List<String> argTypes, List<JSAny?> args) {
  _m.ccall(
    name.toJS,
    'void'.toJS,
    argTypes.map((t) => t.toJS).toList().toJS,
    args.toJS,
  );
}

void _copyBytesToHeap(TypedData data, int ptr) {
  final bytes = Uint8List.view(
    data.buffer,
    data.offsetInBytes,
    data.lengthInBytes,
  );
  (_m.heapU8 as JSObject).callMethod('set'.toJS, bytes.toJS, ptr.toJS);
}

void _copyBytesFromHeap(int ptr, TypedData dest) {
  final slice = (_m.heapU8 as JSObject).callMethod(
    'subarray'.toJS,
    ptr.toJS,
    (ptr + dest.lengthInBytes).toJS,
  ) as JSUint8Array;
  Uint8List.view(dest.buffer, dest.offsetInBytes, dest.lengthInBytes)
      .setAll(0, slice.toDart);
}

int sum(int a, int b) =>
    _ccallNum('sum', ['number', 'number'], [a.toJS, b.toJS]).toInt();

int processingInit(
  String path,
  int sampleRate,
  int channelCount,
  String deviceInfo,
  String deviceManufacturer,
) {
  return _ccallNum(
    'processing_init',
    ['string', 'number', 'number', 'string', 'string'],
    [
      path.toJS,
      sampleRate.toJS,
      channelCount.toJS,
      deviceInfo.toJS,
      deviceManufacturer.toJS,
    ],
  ).toInt();
}

int nwbfileAddElectricalSeries(
  Int16List inSamples,
  Int32List samplesCount,
  int selectedChannel,
  int channelCount,
  int isFinishRecording,
) {
  final samplesPtr = _m.malloc(inSamples.lengthInBytes);
  final countsPtr = _m.malloc(samplesCount.lengthInBytes);
  try {
    _copyBytesToHeap(inSamples, samplesPtr);
    _copyBytesToHeap(samplesCount, countsPtr);
    return _ccallNum(
      'nwbfile_add_electrical_series',
      ['number', 'number', 'number', 'number', 'number'],
      [
        samplesPtr.toJS,
        countsPtr.toJS,
        selectedChannel.toJS,
        channelCount.toJS,
        isFinishRecording.toJS,
      ],
    ).toInt();
  } finally {
    _m.free(samplesPtr);
    _m.free(countsPtr);
  }
}

/// Creates a per-channel SpikeEventSeries before SWMR recording starts.
/// Returns the recording container index, or -1 on failure.
int nwbfileCreateSpikeEventSeries(int channelIndex) => _ccallNum(
      'nwbfile_create_spike_event_series',
      ['number'],
      [channelIndex.toJS],
    ).toInt();

/// Writes one spike waveform snippet in volts. Returns 0 on success, -1 on failure.
int nwbfileWriteSpikeEvent(
  int channelIndex,
  double timestampSeconds,
  Float32List waveform,
) {
  final waveformPtr = _m.malloc(waveform.lengthInBytes);
  try {
    _copyBytesToHeap(waveform, waveformPtr);
    return _ccallNum(
      'nwbfile_write_spike_event',
      ['number', 'number', 'number', 'number'],
      [
        channelIndex.toJS,
        timestampSeconds.toJS,
        waveformPtr.toJS,
        waveform.length.toJS,
      ],
    ).toInt();
  } finally {
    _m.free(waveformPtr);
  }
}

/// Returns the number of spike events written for [channelIndex], or -1 on failure.
int nwbfileGetSpikeEventCount(int channelIndex) => _ccallNum(
      'nwbfile_get_spike_event_count',
      ['number'],
      [channelIndex.toJS],
    ).toInt();

/// Appends one EventsTable row. Returns the new row index, or -1 on failure.
int nwbfileAddEvent(double timestampSeconds, int eventLabel) => _ccallNum(
      'nwbfile_add_event',
      ['number', 'number'],
      [timestampSeconds.toJS, eventLabel.toJS],
    ).toInt();

/// Updates an existing EventsTable row. Returns 0 on success, -1 on failure.
int nwbfileUpdateEvent(int rowIndex, double timestampSeconds, int eventLabel) =>
    _ccallNum(
      'nwbfile_update_event',
      ['number', 'number', 'number'],
      [rowIndex.toJS, timestampSeconds.toJS, eventLabel.toJS],
    ).toInt();

/// Soft-deletes an EventsTable row. Returns 0 on success, -1 on failure.
int nwbfileDeleteEvent(int rowIndex) => _ccallNum(
      'nwbfile_delete_event',
      ['number'],
      [rowIndex.toJS],
    ).toInt();

/// Reads one EventsTable row by index. Returns null if the row does not
/// exist or the read failed.
({double timestampSeconds, int eventLabel, bool deleted})? nwbfileReadEvent(
  int rowIndex,
) {
  final tsPtr = _m.malloc(4); // float32
  final labelPtr = _m.malloc(4); // int32
  final deletedPtr = _m.malloc(1); // uint8
  try {
    final status = _ccallNum(
      'nwbfile_read_event',
      ['number', 'number', 'number', 'number'],
      [rowIndex.toJS, tsPtr.toJS, labelPtr.toJS, deletedPtr.toJS],
    ).toInt();
    if (status != 0) return null;

    final tsBytes = Float32List(1);
    _copyBytesFromHeap(tsPtr, tsBytes);
    final labelBytes = Int32List(1);
    _copyBytesFromHeap(labelPtr, labelBytes);
    final deletedBytes = Uint8List(1);
    _copyBytesFromHeap(deletedPtr, deletedBytes);

    return (
      timestampSeconds: tsBytes[0].toDouble(),
      eventLabel: labelBytes[0],
      deleted: deletedBytes[0] != 0,
    );
  } finally {
    _m.free(tsPtr);
    _m.free(labelPtr);
    _m.free(deletedPtr);
  }
}

/// Returns the total number of EventsTable rows added so far (including
/// soft-deleted rows).
int nwbfileGetEventCount() =>
    _ccallNum('nwbfile_get_event_count', [], []).toInt();

/// Upsert a MeaningsTable label for an event_type [value].
/// Returns the meanings row index, or -1 on failure.
int nwbfileSetMeaning(int value, String meaning) => _ccallNum(
      'nwbfile_set_meaning',
      ['number', 'string'],
      [value.toJS, meaning.toJS],
    ).toInt();

/// Number of MeaningsTable rows currently registered.
int nwbfileGetMeaningCount() =>
    _ccallNum('nwbfile_get_meaning_count', [], []).toInt();

/// Reads one MeaningsTable row by index. Returns null on failure.
({int value, String meaning})? nwbfileReadMeaning(int rowIndex) {
  final outValue = _m.malloc(4);
  final outMeaning = _m.malloc(256);
  try {
    final status = _ccallNum(
      'nwbfile_read_meaning',
      ['number', 'number', 'number', 'number'],
      [rowIndex.toJS, outValue.toJS, outMeaning.toJS, 256.toJS],
    ).toInt();
    if (status != 0) return null;
    final valueBytes = Int32List(1);
    _copyBytesFromHeap(outValue, valueBytes);
    final meaning = _readCString(outMeaning);
    return (value: valueBytes[0], meaning: meaning);
  } finally {
    _m.free(outValue);
    _m.free(outMeaning);
  }
}

/// Looks up the meaning label for an event_type [value].
/// Returns null if the value is not registered.
String? nwbfileFindMeaning(int value) {
  final outMeaning = _m.malloc(256);
  try {
    final status = _ccallNum(
      'nwbfile_find_meaning',
      ['number', 'number', 'number'],
      [value.toJS, outMeaning.toJS, 256.toJS],
    ).toInt();
    if (status != 0) return null;
    return _readCString(outMeaning);
  } finally {
    _m.free(outMeaning);
  }
}

String _readCString(int ptr) {
  final bytes = <int>[];
  for (var i = 0; i < 255; i++) {
    final b = ((_m.heapU8 as JSObject).getProperty((ptr + i).toJS) as JSNumber)
        .toDartInt;
    if (b == 0) break;
    bytes.add(b);
  }
  return String.fromCharCodes(bytes);
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
  final samplesPtr = _m.malloc(outSamples.lengthInBytes);
  final countsPtr = _m.malloc(outSampleCounts.lengthInBytes);
  final configPtr = _m.malloc(outConfig.lengthInBytes);
  try {
    final status = _ccallNum(
      'nwbfile_seek_electrical_series',
      [
        'string',
        'number',
        'number',
        'number',
        'number',
        'number',
        'number',
        'number',
      ],
      [
        path.toJS,
        samplesPtr.toJS,
        countsPtr.toJS,
        configPtr.toJS,
        startTimeStamp.toJS,
        endTimeStamp.toJS,
        startChannel.toJS,
        endChannel.toJS,
      ],
    ).toInt();

    _copyBytesFromHeap(countsPtr, outSampleCounts);
    _copyBytesFromHeap(configPtr, outConfig);
    final count = outSampleCounts.isNotEmpty ? outSampleCounts[0] : 0;
    final channels = endChannel - startChannel + 1;
    final total = (count * channels).clamp(0, outSamples.length);
    if (total > 0) {
      final partial = Int16List(total);
      _copyBytesFromHeap(samplesPtr, partial);
      outSamples.setRange(0, total, partial);
    }
    return status;
  } finally {
    _m.free(samplesPtr);
    _m.free(countsPtr);
    _m.free(configPtr);
  }
}

int getNwbFileSize() => _ccallNum('get_nwb_file_size', [], []).toInt();

void cleanupNwbData() => _ccallVoid('cleanup_nwb_data', [], []);

Future<int> sumAsync(int a, int b) async {
  return _ccallNum(
    'sum_long_running',
    ['number', 'number'],
    [a.toJS, b.toJS],
  ).toInt();
}
