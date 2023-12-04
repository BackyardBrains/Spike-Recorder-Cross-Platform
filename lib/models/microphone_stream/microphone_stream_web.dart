import 'dart:async';
import 'dart:typed_data';
import 'microphone_stream_check.dart';
import 'dart:js' as js;

MicrophoneUtil getMicrophoneStreams() => MicrophoneUtilWeb();

class MicrophoneUtilWeb implements MicrophoneUtil {
  Int16List? _micDataBuffer;

  @override
  StreamController<Uint8List> addListenAudioStreamController =
      StreamController.broadcast();

  @override
  Stream<Uint8List>? micStream;

  @override
  Future<void> init() async {
    micStream = addListenAudioStreamController.stream;
    js.context['onDataBufferAllocated'] = onDataBufferAllocated;
    js.context['onDataReceived'] = onDataReceived;
    Future.delayed(const Duration(seconds: 1), () {
      js.context.callMethod('startListeningToMicrophone', []);
    });
  }

  /// Called only once in the beginning to send address of buffer to dart
  void onDataBufferAllocated(Int16List dataBuffer) {
    _micDataBuffer = dataBuffer;
    print("_micDataBuffer allocated ${_micDataBuffer?.length} ");
  }

  void onDataReceived() {
    if (_micDataBuffer == null) {
      return;
    }
    Uint8List uList = Uint8List.fromList(_micDataBuffer!.buffer.asUint8List());
    addListenAudioStreamController.add(uList);
  }

  @override
  Future<void> checkPointerValue() async {}
}
