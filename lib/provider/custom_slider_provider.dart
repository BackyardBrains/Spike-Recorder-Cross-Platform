import 'package:flutter/material.dart';

class CustomRangeSliderProvider extends ChangeNotifier {
  double _startValue = 0;
  double get startValue => _startValue;
  double _endValue = 0;
  double get endValue => _endValue;
  setStartValue(double startValue) {
    _startValue = startValue;
    notifyListeners();
  }

  setEndValue(double endValue) {
    _endValue = endValue;
    notifyListeners();
  }
}
