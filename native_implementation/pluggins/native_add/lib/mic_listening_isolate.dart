import 'dart:async';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:native_add/allocation.dart';
import 'package:native_add/main.dart';

import 'model/sending_data.dart';

Isolate? _helperIsolateMic;
SendPort? _helperIsolateSendPortMic;

StreamController<Uint8List>? micDataController;
const String _libName = 'native_add';

//  main isolate for window mic

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

final NativeAddBindings _bindingsMic = NativeAddBindings(_dylib);

// Unit - samples of int16
// i.e. bytes 4096
const int _bufferLength = 2048;

final ffi.Pointer<ffi.Int16> _micPointer = allocate<ffi.Int16>(
  count: _bufferLength,
  sizeOfType: ffi.sizeOf<ffi.Int16>(),
);

class _IsolateRequestForMic {
  final int id;
  final dynamic message;

  const _IsolateRequestForMic(this.id, this.message);
}

int _nextRequestId = 0;

/// Typically sent from one isolate to another.
class _IsolateResponseForMic {
  final int id;
  final dynamic result;

  const _IsolateResponseForMic(this.id, this.result);
}

final Map<int, Completer<MicAck>> _isolateResultsOfMic =
    <int, Completer<MicAck>>{};

Future<void> mainIsolateForMic(
    StreamController<SendingDataToDart> micDataController) async {
  if (_helperIsolateMic == null) {
    _helperIsolateSendPortMic =
        await mainIsolateForMicHelperStart(micDataController);
  }
}

Future<SendPort> mainIsolateForMicHelperStart(
    StreamController<SendingDataToDart> micDataController) async {
  final Completer<SendPort> completerSendPortForMic = Completer<SendPort>();

  final ReceivePort response = ReceivePort();
  response.listen((dynamic message) {
    if (message is SendPort) {
      // The helper isolate sent us the port on which we can sent it requests.
      completerSendPortForMic.complete(message);
      return;
    }

    if (message is _IsolateResponseForMic) {
      if (message.result is MicAck) {
        switch (message.result) {
          case MicAck.micStarted:
            final Completer<MicAck> completer =
                _isolateResultsOfMic[message.id]!;

            completer.complete(message.result);

            // Remove the completer from the Map and free up memory
            _isolateResultsOfMic.remove(message.id);

            break;

          case MicAck.micStopped:
            break;
        }
      }

      return;
    }

    //
    //
    //
    if (message is SendingDataToDart) {
      micDataController.add(message);
    } else {
      throw UnsupportedError(
          'Unsupported message type: ${message.runtimeType}');
    }
  });

  _helperIsolateMic = await Isolate.spawn((SendPort sendPort) async {
    final ReceivePort helperReceivePortMic = ReceivePort();

    helperReceivePortMic.listen((dynamic data) async {
      // Todo pass the address:
      // final pointer = ffi.Pointer<ffi.Int16>.fromAddress(micData.offsetInBytes);

      // Future.delayed(const Duration(milliseconds: 1));
      if (data is _IsolateRequestForMic) {
        if (data.message is MicCommands) {
          switch (data.message) {
            case MicCommands.startMic:
              // Future.delayed(Duration(milliseconds: 100)).then((value) {
              initializeMic();
              _IsolateResponseForMic response;
              response = _IsolateResponseForMic(data.id, MicAck.micStarted);

              sendPort.send(response);

              continuouslyCheckMicData(sendPort);
              break;

            case MicCommands.stopMic:
              break;

            default:
              throw UnsupportedError(
                  'Unsupported message type: ${data.message}}');
          }
        }
      }
    });

    sendPort.send(helperReceivePortMic.sendPort);
  }, response.sendPort);

  return completerSendPortForMic.future;
}

/// Called only once
Future<MicAck> listenMicOfAudio() async {
  final int requestId = _nextRequestId++;
  final _IsolateRequestForMic request =
      _IsolateRequestForMic(requestId, MicCommands.startMic);
  final Completer<MicAck> completer = Completer<MicAck>();
  _isolateResultsOfMic[requestId] = completer;
  _helperIsolateSendPortMic?.send(request);
  return completer.future;
}

Future<void> continuouslyCheckMicData(SendPort isolateToMainMic) async {
  // int counter = 0;
  final Duration pollDuration = Platform.isWindows
      ? const Duration(milliseconds: 10)
      : const Duration(microseconds: 100);
  bool isFetchingData = false;
  Stopwatch stopwatch = Stopwatch();

  stopwatch.start();
  Timer.periodic(pollDuration, (timer) {
    // counter++;
    if (isFetchingData) return;
    isFetchingData = true;
    double isCheck = _bindingsMic.isAudioCaptureData(_micPointer);

    if (isCheck == 1.0) {
      print("stopwatch.elapsedMilliseconds: ${stopwatch.elapsedMilliseconds}, _bufferLength: ${_bufferLength/2}");
      stopwatch.elapsedMilliseconds;
      stopwatch.reset();
      Int16List int16list = _micPointer.asTypedList(_bufferLength);
      // counter++;
      // isolateToMainMic.send(int16list);
      // MicDataWithDetail micDataWithDetail = MicDataWithDetail(
      //     micData: int16list,
      //     upComingDataTiming: stopwatch.elapsedMilliseconds);
//  sending data to worker
      int elapse = _bindingsMic.getElapseAudio();
      int minTime = _bindingsMic.getMinAudio();
      int maxTime = _bindingsMic.getMaxAudio();
      SendingDataToDart sendingDataToDart = SendingDataToDart(
          int16list: int16list,
          elapseTime: elapse,
          maxTime: maxTime,
          minTime: minTime);
      isolateToMainMic.send(sendingDataToDart);

      print("the stop watch ${stopwatch.elapsedMilliseconds} and ");
    }
    isFetchingData = false;
  });
}

class MicDataWithDetail {
  final Int16List micData;
  final int upComingDataTiming;
  MicDataWithDetail({required this.micData, required this.upComingDataTiming});
}

Future<void> initializeMic() async {
  double result1 = _bindingsMic.listenMic();
  print("From dart : mic listnening started in CPP - result $result1");
}

enum MicCommands {
  startMic,
  stopMic,
}

enum MicAck {
  micStarted,
  micStopped,
  micFailure,
}
