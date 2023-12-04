import 'package:flutter/foundation.dart';

class SoftwareConfigProvider extends ChangeNotifier {
  bool _isSettingEnable = false;

  bool get isSettingEnable => _isSettingEnable;

  settingStatus(bool status) {
    _isSettingEnable = status;
    notifyListeners();
  }
}
