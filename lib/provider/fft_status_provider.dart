import 'package:flutter/material.dart';

class FftStatusProvider extends ChangeNotifier {
  // int _sampleRate = 10000;
  // int get sampleRate => _sampleRate;
  bool _isFftShowing = false;
  bool get isFftShowing => _isFftShowing;

  setFftVisibility(bool isFftShowing) {
    _isFftShowing = isFftShowing;
    notifyListeners();
  }
}
