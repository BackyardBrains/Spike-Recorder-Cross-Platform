import 'package:flutter/material.dart';

class GraphGainProvider extends ChangeNotifier {
  double gain = 1;

  setGain(double newGain) {
    gain = newGain;
    notifyListeners();
  }
}
