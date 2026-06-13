import 'package:flutter/material.dart';
import 'package:spikerbox_architecture/constant/colors_constant.dart';
import 'package:spikerbox_architecture/constant/softwaretextstyle.dart';

class AppThemeColors {
  final Color scaffoldBackground;
  final Color panelBackground;
  final Color cardBackground;
  final Color buttonBackground;
  final Color tabSelectedBackground;
  final Color tabNormalBackground;
  final Color tabBorderColor;
  final Color surfaceTint;
  final Color textPrimary;
  final Color textSecondary;
  final Color divider;
  final Color iconPrimary;
  final Color graphBackground;
  final Color selectionHighlight;
  final Color sliderInactiveTrack;
  final Color sliderTick;
  final Color inputBackground;
  final Color overlayScrim;
  final Color graphControlLine;
  final Color dropdownBorder;
  final Color dropdownHint;

  const AppThemeColors({
    required this.scaffoldBackground,
    required this.panelBackground,
    required this.cardBackground,
    required this.buttonBackground,
    required this.tabSelectedBackground,
    required this.tabNormalBackground,
    required this.tabBorderColor,
    required this.surfaceTint,
    required this.textPrimary,
    required this.textSecondary,
    required this.divider,
    required this.iconPrimary,
    required this.graphBackground,
    required this.selectionHighlight,
    required this.sliderInactiveTrack,
    required this.sliderTick,
    required this.inputBackground,
    required this.overlayScrim,
    required this.graphControlLine,
    required this.dropdownBorder,
    required this.dropdownHint,
  });

  static const AppThemeColors dark = AppThemeColors(
    scaffoldBackground: Colors.black,
    panelBackground: Color(0xFF222222),
    cardBackground: Color(0xFF2e2e2e),
    buttonBackground: Color(0xFF2C2C2C),
    tabSelectedBackground: Color(0xFF2e2e2e),
    tabNormalBackground: Color(0xFF181818),
    tabBorderColor: Color(0xFF222222),
    surfaceTint: Color(0x14D9D9D9),
    textPrimary: Colors.white,
    textSecondary: Color(0xFF707070),
    divider: Color(0x70707070),
    iconPrimary: Colors.white,
    graphBackground: Color(0xFF222222),
    selectionHighlight: Color(0xFF464646),
    sliderInactiveTrack: Color(0xFF616161),
    sliderTick: Colors.white,
    inputBackground: Color(0xFF424242),
    overlayScrim: Color(0xE6000000),
    graphControlLine: Colors.white,
    dropdownBorder: Color(0x1AFFFFFF),
    dropdownHint: Color(0x61FFFFFF),
  );

  static const AppThemeColors light = AppThemeColors(
    scaffoldBackground: Color(0xFFF5F5F5),
    panelBackground: Colors.white,
    cardBackground: Color(0xFFF0F0F0),
    buttonBackground: Color(0xFFE8E8E8),
    tabSelectedBackground: Color(0xFFE0E0E0),
    tabNormalBackground: Color(0xFFD5D5D5),
    tabBorderColor: Color(0xFFE0E0E0),
    surfaceTint: Color(0x1A000000),
    textPrimary: Color(0xFF1A1A1A),
    textSecondary: Color(0xFF666666),
    divider: Color(0xFFD0D0D0),
    iconPrimary: Color(0xFF1A1A1A),
    graphBackground: Color(0xFFF5F5F5),
    selectionHighlight: Color(0xFFE8E8E8),
    sliderInactiveTrack: Color(0xFFBDBDBD),
    sliderTick: Color(0xFF424242),
    inputBackground: Color(0xFFFFFFFF),
    overlayScrim: Color(0xCCF5F5F5),
    graphControlLine: Color(0xFF424242),
    dropdownBorder: Color(0x1A000000),
    dropdownHint: Color(0x99000000),
  );

  static AppThemeColors of(bool isDarkMode) => isDarkMode ? dark : light;

  static void applyToSoftwareColors(bool isDarkMode) {
    final colors = of(isDarkMode);
    SoftwareColors.kBackGroundColor = colors.scaffoldBackground;
    SoftwareColors.kButtonColor = colors.textPrimary;
    SoftwareColors.kDropDownBackGroundColor = colors.buttonBackground;
    SoftwareTextStyle.applyTheme(isDarkMode);
  }
}

ThemeData buildAppTheme({required bool isDark}) {
  final colors = AppThemeColors.of(isDark);
  return ThemeData(
    brightness: isDark ? Brightness.dark : Brightness.light,
    primarySwatch: Colors.blue,
    scaffoldBackgroundColor: colors.scaffoldBackground,
    canvasColor: colors.scaffoldBackground,
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFFFF7A5C),
      brightness: isDark ? Brightness.dark : Brightness.light,
      surface: colors.panelBackground,
    ),
    textTheme: TextTheme(
      bodyMedium: TextStyle(color: colors.textPrimary),
      titleLarge: TextStyle(color: colors.textPrimary),
    ),
    dividerColor: colors.divider,
  );
}
