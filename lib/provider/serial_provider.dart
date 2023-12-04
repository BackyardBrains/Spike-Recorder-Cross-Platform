import 'package:flutter/material.dart';

import '../models/models.dart';

class SerialDataProvider extends ChangeNotifier {
  List<SerialPortDataModel> _getAllPortDetail = [];
  List<SerialPortDataModel> get getAllPortDetail => _getAllPortDetail;

  setPortOfDevices(SerialPortDataModel serialPortData) {
    _getAllPortDetail.add(serialPortData);
    notifyListeners();
  }
}
