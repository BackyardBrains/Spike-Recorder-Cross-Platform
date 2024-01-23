import 'package:flutter/foundation.dart';
import 'package:spikerbox_architecture/provider/provider_export.dart';

class EnvelopConfig extends ChangeNotifier {
  int _sampleLength = 44100 * 120;
  int _skipCount = 44100 * 120 ~/ 2000;
  final int _bufferSize = (44100 ~/ 1000) * 120;

  int get bufferSize => _bufferSize;
  int get sampleLength => _sampleLength;
  int get skipCount => _skipCount;

  void changeSampleLength(SampleRateProvider upComingSampleRate, int duration) {
    int dataLength = upComingSampleRate.sampleRate * duration;
    print("the sample length $_sampleLength");
    _sampleLength = dataLength;
    changeSkipCount();

    notifyListeners();
  }

  // void changeBufferSize(int upComingSampleRate) {
  //   int newBufferLength = (upComingSampleRate ~/ 1000) * 120000;
  //   _bufferSize = newBufferLength;
  // }

  void changeSkipCount() {
    print("the skip count before $skipCount");
    _skipCount = _sampleLength ~/ 2000;
    print("the skip count after $skipCount");
  }
}
