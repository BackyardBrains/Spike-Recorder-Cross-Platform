import 'package:flutter/material.dart';

class SampleRateProvider extends ChangeNotifier {
  int _sampleRate = 10000;
  int get sampleRate => _sampleRate;

  setSampleRate(int sampleRate) {
    _sampleRate = sampleRate;
    notifyListeners();
  }
}
