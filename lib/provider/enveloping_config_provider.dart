import 'package:flutter/foundation.dart';

class EnvelopConfig extends ChangeNotifier {
  int _sampleLength = 0;
  int _skipCount = 0;
  final int _bufferSize = (44100 ~/ 1000) * 120;

  int get bufferSize => _bufferSize;
  int get sampleLength => _sampleLength;
  int get skipCount => _skipCount;
  int _sampleRate = 44100;

  void firstTimeSet(int upComingSampleRate, int duration) {
    _sampleRate = upComingSampleRate;
    changeSampleLengthOnScroll(duration);
    changeSkipCountOnScroll(duration);
  }

  void changeSampleLengthOnScroll(int duration) {
    int sampleLength = (_sampleRate ~/ 1000) * duration;
    _sampleLength = sampleLength;
    notifyListeners();
  }

  void changeSkipCountOnScroll(int duration) {
    int setSkipCount = _sampleLength ~/ 2000;
    _skipCount = setSkipCount;
    notifyListeners();
  }

  void changeSampleLengthAndSkipCount(int duration) {
    changeSampleLengthOnScroll(duration);
    changeSkipCountOnScroll(duration);
  }
}
