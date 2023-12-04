import 'package:flutter/material.dart';

class GraphResumePlayProvider extends ChangeNotifier {
  bool _graphStatus = true;
  bool get graphStatus => _graphStatus;

  setGraphResumePlay(bool isGraphStatus) {
    _graphStatus = isGraphStatus;
    notifyListeners();
  }
}
