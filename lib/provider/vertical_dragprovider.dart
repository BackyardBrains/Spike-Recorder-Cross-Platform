import 'package:flutter/material.dart';

class VerticalDragProvider extends ChangeNotifier {
  double initialOffset = 0;
  double topPosition = 0;

  setDragPosition(double newTopPosition) {
    topPosition = newTopPosition;
    notifyListeners();
  }
}
