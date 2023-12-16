import 'dart:async';

import 'package:flutter/material.dart';

class GraphResumePlayProvider extends ChangeNotifier {
  bool _graphStatus = true;
  bool get graphStatus => _graphStatus;

  final StreamController<bool> _graphStatusStreamController =
      StreamController.broadcast();
  Stream<bool>? _graphStatusStream;

  Stream<bool> getStream() {
    _graphStatusStream ??= _graphStatusStreamController.stream;
    return _graphStatusStream!;
  }

  setGraphResumePlay(bool isGraphStatus) {
    _graphStatus = isGraphStatus;
    _graphStatusStreamController.add(isGraphStatus);
  }
}
