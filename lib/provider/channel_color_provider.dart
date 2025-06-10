import 'package:flutter/material.dart';
import '../constant/colors_constant.dart';
import '../constant/channel_color_defaults.dart';

class ChannelColorProvider extends ChangeNotifier {
  List<Color> audioColors = [];
  List<Color> serialColors = [];

  void setAudioChannelCount(int count) {
    if (audioColors.length < count) {
      for (int i = audioColors.length; i < count; i++) {
        if (i < ChannelColorDefaults.audioChannelColors.length) {
          audioColors.add(ChannelColorDefaults.audioChannelColors[i]);
        } else {
          audioColors.add(SoftwareColors.kGraphColor);
        }
      }
    } else if (audioColors.length > count) {
      audioColors = audioColors.sublist(0, count);
    }
    notifyListeners();
  }

  void setSerialChannelCount(int count) {
    if (serialColors.length < count) {
      for (int i = serialColors.length; i < count; i++) {
        if (i < ChannelColorDefaults.serialChannelColors.length) {
          serialColors.add(ChannelColorDefaults.serialChannelColors[i]);
        } else {
          serialColors.add(SoftwareColors.kGraphColor);
        }
      }
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
