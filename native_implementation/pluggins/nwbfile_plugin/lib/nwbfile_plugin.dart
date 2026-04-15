
import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'nwbfile_plugin_bindings_generated.dart';

/// A very short-lived native function.
///
/// For very short-lived functions, it is fine to call them on the main isolate.
/// They will block the Dart execution while running the native function, so
/// only do this for native functions which are guaranteed to be short-lived.
int sum(int a, int b) => _bindings.sum(a, b);
int processingInit(Pointer<Char> path, int sampleRate, int channelCount, Pointer<Char> deviceInfo, Pointer<Char> deviceManufacturer) => _bindings.processing_init(path, sampleRate, channelCount, deviceInfo, deviceManufacturer);
int nwbfile_add_electrical_series(Pointer<Int16> inSamples, Pointer<Int32> numSamples, int selectedChannel, int channelCount, int isFinishRecording) => _bindings.nwbfile_add_electrical_series(inSamples, numSamples,selectedChannel, channelCount, isFinishRecording);
int nwbfile_read_electrical_series(Pointer<Int16> outSamples, Pointer<Int32> outSampleCounts, int selectedChannel, int channelCount) => _bindings.nwbfile_read_electrical_series(outSamples, outSampleCounts,selectedChannel, channelCount);

/// Seek and read a specific time range from electrical series data (multi-channel support)
int nwbfile_seek_electrical_series(Pointer<Char> path, Pointer<Int16> outSamples, Pointer<Int32> outSampleCounts, Pointer<Int32> outConfig, int startTimeStamp, int endTimeStamp, int startChannel, int endChannel) => _bindings.nwbfile_seek_electrical_series(path, outSamples, outSampleCounts, outConfig, startTimeStamp, endTimeStamp, startChannel, endChannel);

/// NWB file data functions for iOS
int getNwbFileSize() => _bindings.get_nwb_file_size();
int getNwbFileData(Pointer<Char> buffer, int bufferSize) => _bindings.get_nwb_file_data(buffer, bufferSize);
void cleanupNwbData() => _bindings.cleanup_nwb_data();

/// Debug function to inspect NWB file structure
// int debugNwbFileStructure(Pointer<Char> filePath) => _bindings.debug_nwb_file_structure(filePath);

/// NWB File Append Functions
// int appendTimeSeriesData(Pointer<Char> filePath, 
//                         Pointer<Char> seriesName,
//                         Pointer<Double> timestamps, 
//                         int numTimestamps,
//                         Pointer<Void> data, 
//                         int dataType,
//                         int numSamples,
//                         int numChannels) => _bindings.append_timeseries_data(filePath, seriesName, timestamps, numTimestamps, data, dataType, numSamples, numChannels);

// int appendElectricalSeriesData(Pointer<Char> filePath,
//                               Pointer<Char> seriesName,
//                               Pointer<Double> timestamps,
//                               int numTimestamps,
//                               Pointer<Void> data,
//                               int dataType,
//                               int numSamples,
//                               int numChannels) => _bindings.append_electrical_series_data(filePath, seriesName, timestamps, numTimestamps, data, dataType, numSamples, numChannels);

// int appendIntervalData(Pointer<Char> filePath,
//                       Pointer<Char> intervalName,
//                       Pointer<Double> startTimes,
//                       Pointer<Double> stopTimes,
//                       int numIntervals,
//                       Pointer<Pointer<Char>> tags,
//                       int numTags) => _bindings.append_interval_data(filePath, intervalName, startTimes, stopTimes, numIntervals, tags, numTags);

// int appendAcquisitionData(Pointer<Char> filePath,
//                          Pointer<Char> acquisitionName,
//                          Pointer<Double> timestamps,
//                          int numTimestamps,
//                          Pointer<Void> data,
//                          int dataType,
//                          int numSamples,
//                          int numChannels) => _bindings.append_acquisition_data(filePath, acquisitionName, timestamps, numTimestamps, data, dataType, numSamples, numChannels);

// int createNewTimeSeries(Pointer<Char> filePath,
//                        Pointer<Char> seriesName,
//                        int dataType,
//                        int numChannels,
//                        Pointer<Pointer<Char>> channelNames,
//                        double samplingRate) => _bindings.create_new_timeseries(filePath, seriesName, dataType, numChannels, channelNames, samplingRate);

// int createNewInterval(Pointer<Char> filePath,
//                      Pointer<Char> intervalName,
//                      Pointer<Pointer<Char>> columnNames,
//                      int numColumns) => _bindings.create_new_interval(filePath, intervalName, columnNames, numColumns);

/// A longer lived native function, which occupies the thread calling it.
///
/// Do not call these kind of native functions in the main isolate. They will
/// block Dart execution. This will cause dropped frames in Flutter applications.
/// Instead, call these native functions on a separate isolate.
///
/// Modify this to suit your own use case. Example use cases:
///
/// 1. Reuse a single isolate for various different kinds of requests.
/// 2. Use multiple helper isolates for parallel execution.
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

/// The dynamic library in which the symbols for [NwbfilePluginBindings] can be found.
final DynamicLibrary _dylib = () {
  if (Platform.isIOS) {
    print("Dynamic Library init process()");
    try{
      return DynamicLibrary.process();
    }catch(err) {
      print("Dynamic Library process error: $err");
      return DynamicLibrary.open('$_libName.framework/$_libName');
    }
  }
  if (Platform.isMacOS) {
    print("Dynamic Library init $_libName.framework/$_libName");
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

/// The bindings to the native functions in [_dylib].
final NwbfilePluginBindings _bindings = NwbfilePluginBindings(_dylib);


/// A request to compute `sum`.
///
/// Typically sent from one isolate to another.
class _SumRequest {
  final int id;
  final int a;
  final int b;

  const _SumRequest(this.id, this.a, this.b);
}

/// A response with the result of `sum`.
///
/// Typically sent from one isolate to another.
class _SumResponse {
  final int id;
  final int result;

  const _SumResponse(this.id, this.result);
}

/// Counter to identify [_SumRequest]s and [_SumResponse]s.
int _nextSumRequestId = 0;

/// Mapping from [_SumRequest] `id`s to the completers corresponding to the correct future of the pending request.
final Map<int, Completer<int>> _sumRequests = <int, Completer<int>>{};

/// The SendPort belonging to the helper isolate.
Future<SendPort> _helperIsolateSendPort = () async {
  // The helper isolate is going to send us back a SendPort, which we want to
  // wait for.
  final Completer<SendPort> completer = Completer<SendPort>();

  // Receive port on the main isolate to receive messages from the helper.
  // We receive two types of messages:
  // 1. A port to send messages on.
  // 2. Responses to requests we sent.
  final ReceivePort receivePort = ReceivePort()
    ..listen((dynamic data) {
      if (data is SendPort) {
        // The helper isolate sent us the port on which we can sent it requests.
        completer.complete(data);
        return;
      }
      if (data is _SumResponse) {
        // The helper isolate sent us a response to a request we sent.
        final Completer<int> completer = _sumRequests[data.id]!;
        _sumRequests.remove(data.id);
        completer.complete(data.result);
        return;
      }
      throw UnsupportedError('Unsupported message type: ${data.runtimeType}');
    });

  // Start the helper isolate.
  await Isolate.spawn((SendPort sendPort) async {
    final ReceivePort helperReceivePort = ReceivePort()
      ..listen((dynamic data) {
        // On the helper isolate listen to requests and respond to them.
        if (data is _SumRequest) {
          final int result = _bindings.sum_long_running(data.a, data.b);
          final _SumResponse response = _SumResponse(data.id, result);
          sendPort.send(response);
          return;
        }
        throw UnsupportedError('Unsupported message type: ${data.runtimeType}');
      });

    // Send the port to the main isolate on which we can receive requests.
    sendPort.send(helperReceivePort.sendPort);
  }, receivePort.sendPort);

  // Wait until the helper isolate has sent us back the SendPort on which we
  // can start sending requests.
  return completer.future;
}();
