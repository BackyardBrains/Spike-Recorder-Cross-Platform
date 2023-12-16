import 'package:flutter/material.dart';

import '../models/models.dart';

class SerialDataProvider extends ChangeNotifier {
  final List<SerialPortDataModel> _getAllPortDetail = [];
  List<SerialPortDataModel> get getAllPortDetail => _getAllPortDetail;
  List<ComDataWithBoard> _deviceWithComData = [];

  List<ComDataWithBoard> get deviceWithComData => _deviceWithComData;

  setPortOfDevices(SerialPortDataModel serialPortData) {
    bool containsDuplicate = _getAllPortDetail
        .any((element) => element.deviceDetect == serialPortData.deviceDetect);

    if (!containsDuplicate) {
      _getAllPortDetail.add(serialPortData);
      notifyListeners();
    }
  }

  setDeviceWithComData(List<ComDataWithBoard> newDeviceList) {
    _deviceWithComData.clear();
    _deviceWithComData = newDeviceList;
    notifyListeners();
  }

  removeDeviceWithComData(ComDataWithBoard serialPortData) {
    _deviceWithComData.remove(serialPortData);
    notifyListeners();
  }
}
