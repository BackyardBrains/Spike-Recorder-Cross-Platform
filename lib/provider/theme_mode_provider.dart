import 'package:flutter/foundation.dart';
import 'package:spikerbox_architecture/constant/app_theme.dart';

class ThemeModeProvider extends ChangeNotifier {
  bool _isDarkMode = true;

  bool get isDarkMode => _isDarkMode;

  ThemeModeProvider() {
    AppThemeColors.applyToSoftwareColors(_isDarkMode);
  }

  void setDarkMode(bool value) {
    if (_isDarkMode == value) return;
    _isDarkMode = value;
    AppThemeColors.applyToSoftwareColors(_isDarkMode);
    notifyListeners();
  }
}
