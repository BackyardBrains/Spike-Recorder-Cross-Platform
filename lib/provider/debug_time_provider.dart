import 'package:flutter/foundation.dart';
import 'package:spikerbox_architecture/models/audio_detail_model.dart';

class DebugTimeProvider extends ChangeNotifier {
  int _totalTime = 0;
  int _counter = 0;
  int _averageTime = 0;
  static final int maxIntValue =
      kIsWeb ? int.parse('9007199254740991') : int.parse('9223372036854775807');
  int _minTime = maxIntValue;
  int _maxTime = 0;

  int get averageTime => _averageTime;
  int get minTime => _minTime;
  int get maxTime => _maxTime;

//* audioDetail constant

  // int _audioAvgTime = 0;
  // int _audioMaxTime = 0;
  // int _audioMinTime = 0;

  AudioDetail? _audioDetail;

  AudioDetail get audioDetail => _audioDetail!;

  setAudioDetail(AudioDetail audioDetail) {
    _audioDetail = audioDetail;
    notifyListeners();
  }
  // int get audioAvgTime => _audioAvgTime;
  // int get audioMaxTime => _audioMaxTime;
  // int get audioMinTIme => _audioMinTime;

// *   provider for  render data in calculation  on the graph
  addGraphTime(
    int time,
  ) {
    if (_totalTime + time > maxIntValue) {
      resetCounter();
    }
    _averageTimeTaken(time);
    _minMaxTimeTaken(time);
  }

  _averageTimeTaken(int time) {
    _counter++;
    _totalTime += time;
    _averageTime = (_totalTime ~/ _counter);
    notifyListeners();
  }

  _minMaxTimeTaken(int time) {
    if (time < minTime) {
      int min = time;
      setMin(min);
    }
    if (time > maxTime) {
      int max = time;
      setMax(max);
    }
  }

  resetCounter() {
    _counter = 0;
    _totalTime = 0;
    _averageTime = 0;
    _maxTime = 0;
    _minTime = 0;
  }

  setMax(int max) {
    _maxTime = max;
    notifyListeners();
  }

  setMin(int min) {
    _minTime = min;
    notifyListeners();
  }

  //*

  addMicrophoneTiming() {}
}
