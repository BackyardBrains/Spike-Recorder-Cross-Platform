import 'package:flutter/material.dart';

class ThemeColors {
  static const Map<int, Color> myColor = {
    50: Color.fromARGB(255, 182, 228, 233),
    100: Color.fromARGB(255, 155, 217, 224),
    200: Color.fromARGB(255, 128, 199, 207),
    300: Color.fromARGB(255, 111, 194, 203),
    400: Color.fromARGB(255, 95, 184, 194),
    500: Color.fromARGB(255, 64, 160, 171),
    600: Color.fromARGB(255, 44, 145, 156),
    700: Color.fromARGB(255, 30, 143, 155),
    800: Color(0xff108E9B),
    900: Color.fromARGB(255, 7, 107, 118),
  };

  final MaterialColor themeColorCustom =
      const MaterialColor(0xff108E9B, myColor);
  static const Color negativeActionColor = Color.fromRGBO(175, 0, 0, 1);
  static const Color customZincColor = Color.fromARGB(255, 137, 137, 137);
  static const Color customSteelColor = Color.fromARGB(255, 91, 91, 91);
  static const Color customNavyBlueColor = Color.fromARGB(255, 67, 67, 91);
  static const Color customYellowColor = Color.fromARGB(255, 247, 167, 7);
  static const Color customLightGreyColor = Color.fromARGB(255, 235, 236, 236);
  static const Color customGreyColor = Color.fromARGB(255, 197, 198, 198);
  static const Color customDarkGreyColor = Color.fromARGB(255, 157, 158, 158);
}
