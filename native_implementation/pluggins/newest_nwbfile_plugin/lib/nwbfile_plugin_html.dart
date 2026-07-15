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
