import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';

import 'microphone_stream_check.dart';
import 'dart:html' as html;
import 'dart:js' as js;

MicrophoneUtil getMicrophoneStreams() => MicrophoneUtilWeb();

class MicrophoneUtilWeb implements MicrophoneUtil {
  Int16List? _micDataBuffer;

  @override
  // StreamController<Uint8List> addListenAudioStreamController =
  //     StreamController<Uint8List>();
  ValueNotifier<Uint8List> addListenAudioStreamController = ValueNotifier(Uint8List(0));

  @override
  ValueNotifier<Uint8List> micStream = ValueNotifier(Uint8List(0));

  @override
  double sampleRate = 44100;
  
  var mediaStream;

  @override
  Future<void> init() async {
    try {
      if (mediaStream == null) {
        mediaStream = await html.window.navigator.mediaDevices?.getUserMedia({
          'audio': true,
        });
        if (mediaStream != null) {
          html.MediaStreamTrack audioTrack = mediaStream.getAudioTracks()[0];
          Map<dynamic, dynamic> trackSettings = audioTrack.getSettings();
          sampleRate = trackSettings["sampleRate"];
        }
      } else {

      }

      // print("sampleRate: $sampleRate");
      // micStream = ValueNotifier(Uint8List(0));
    } catch(err) {
      print("err mic");
      print(err);
    }
    
    // micStream = addListenAudioStreamController;
    js.context['onDataBufferAllocated'] = onDataBufferAllocated;
    // Wrap in closure to preserve 'this' context when called from JavaScript
    js.context['onDataReceived'] = () => onDataReceived();
    await Future.delayed(const Duration(seconds: 1));
    print("startListeningToMicrophone | sampleRate: $sampleRate");    
    js.context.callMethod('startListeningToMicrophone', [sampleRate]);
  }

  /// Called only once in the beginning to send address of buffer to dart
  void onDataBufferAllocated(Int16List dataBuffer, int channelIdx, pSampleRate) {
    print("ON DATA BUFFER ALLOCATED MICROPHONE UTILS");
    _micDataBuffer = dataBuffer;
    // if (pSampleRate != null) {
    //   sampleRate = pSampleRate.toDouble();
    // }
    print("_micDataBuffer allocated ${_micDataBuffer?.length} $sampleRate");
  }

  void onDataReceived() {
    // var time = DateTime.now().millisecondsSinceEpoch;
    if (_micDataBuffer == null) {
      return;
    }

    Uint8List uList = Uint8List.fromList(_micDataBuffer!.buffer.asUint8List());
    // Uint8List uList = Uint8List.fromList(micBuffer.buffer.asUint8List());
    micStream.value = (uList);
  }

  @override
  Future<void> checkPointerValue() async {}

  @override
  StreamSubscription? micStatus;
}
