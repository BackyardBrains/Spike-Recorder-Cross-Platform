import 'package:flutter/material.dart';
import '../constant/colors_constant.dart';

class ChannelColorProvider extends ChangeNotifier {
  List<Color> audioColors = [];
  List<Color> serialColors = [];

  void setAudioChannelCount(int count) {
    if (audioColors.length < count) {
      audioColors.addAll(
          List<Color>.filled(count - audioColors.length, SoftwareColors.kGraphColor));
    } else if (audioColors.length > count) {
      audioColors = audioColors.sublist(0, count);
    }
    notifyListeners();
  }

  void setSerialChannelCount(int count) {
    if (serialColors.length < count) {
      serialColors.addAll(
          List<Color>.filled(count - serialColors.length, SoftwareColors.kGraphColor));
    } else if (serialColors.length > count) {
      serialColors = serialColors.sublist(0, count);
    }
    notifyListeners();
  }

  void setAudioColor(int index, Color color) {
    if (index >= 0 && index < audioColors.length) {
      audioColors[index] = color;
      notifyListeners();
    }
  }

  void setSerialColor(int index, Color color) {
    if (index >= 0 && index < serialColors.length) {
      serialColors[index] = color;
      notifyListeners();
    }
  }
}
