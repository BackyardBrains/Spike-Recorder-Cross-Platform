import 'package:flutter/material.dart';

class PortScanProvider extends ChangeNotifier {
  List<String> _availablePorts = [];
  List<String> get availablePorts => _availablePorts;

  setPortScanList(List<String> portScanList) {
    _availablePorts = portScanList;
    notifyListeners();
  }
}
