import 'package:flutter/material.dart';
import 'package:spikerbox_architecture/constant/app_theme.dart';

class SoftwareTextStyle {
  static Color _primaryTextColor = Colors.white;

  static void applyTheme(bool isDarkMode) {
    _primaryTextColor = AppThemeColors.of(isDarkMode).textPrimary;
  }

  TextStyle get kWtMediumTextStyle =>
      TextStyle(fontSize: 16, color: _primaryTextColor);
  TextStyle kBkMediumTextStyle =
      const TextStyle(fontSize: 16, color: Colors.black87);
  TextStyle kBBkMediumTextStyle = const TextStyle(
      fontSize: 16, color: Colors.black87, fontWeight: FontWeight.w500);
}
