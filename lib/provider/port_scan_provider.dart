import 'package:flutter/material.dart';

class PortScanProvider extends ChangeNotifier {
  List<String> _availablePorts = [];
  List<String> get availablePorts => _availablePorts;

  final List<String> _deviceList = [];
  List<String> get deviceList => _deviceList;

  setPortScanList(List<String> portScanList) {
    _availablePorts = portScanList;
    notifyListeners();
  }

  setDeviceList(String deviceList) {
    _deviceList.add(deviceList);
    notifyListeners();
  }

  removeDeviceList(String deviceList) {
    _deviceList.remove(deviceList);
    notifyListeners();
  }

  resetProvider() {
    _availablePorts = [];
    notifyListeners();
  }
}
