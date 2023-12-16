import 'package:flutter/foundation.dart';

class ConstantProvider extends ChangeNotifier {
  int _bitData = 10;
  int _channelCount = 1;
  int _baudRate = 222222;
  bool _isDeviceConnected = false;
  bool get isDeviceConnected => _isDeviceConnected;

  int getBitData() {
    return _bitData;
  }

  int getChannelCount() {
    return _channelCount;
  }

  int getBaudRate() {
    return _baudRate;
  }

  setBitData(int bitData) {
    _bitData = bitData;
    notifyListeners();
  }

  setChannelCount(int channelCount) {
    _channelCount = channelCount;
    notifyListeners();
  }

  setBaudRate(int baudRate) {
    _baudRate = baudRate;
    notifyListeners();
  }

  //it check any port is devices in inserted

  setDeviceInsertInPort(bool isDeviceInserted) {
    _isDeviceConnected = isDeviceInserted;
    notifyListeners();
  }
}
