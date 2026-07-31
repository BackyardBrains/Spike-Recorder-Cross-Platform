import 'package:flutter/material.dart';

class CustomRangeSliderProvider extends ChangeNotifier {
  List<double> _startValue = List<double>.filled(10, 0);
  List<double> get startValue => _startValue;
  List<double> _endValue = List<double>.filled(10, 0);
  List<double> get endValue => _endValue;
  setStartValue(double startValue, int channelIdx) {
    _startValue[channelIdx] = startValue;
    notifyListeners();
  }

  setEndValue(double endValue, int channelIdx) {
    _endValue[channelIdx] = endValue;
    notifyListeners();
  }
}
