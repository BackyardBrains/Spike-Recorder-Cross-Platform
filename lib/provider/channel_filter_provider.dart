import 'package:flutter/material.dart';

class ChannelFilterProvider extends ChangeNotifier {
  List<bool> audioFilters = [];
  List<bool> serialFilters = [];

  void setAudioChannelCount(int count) {
    audioFilters = List<bool>.filled(count, false);
    notifyListeners();
  }

  void setSerialChannelCount(int count) {
    print("setSerialChannelCount: $count");
    serialFilters = List<bool>.filled(count, false);
    notifyListeners();
  }

  void setAudioFilter(int index, bool value) {
    if (index >= 0 && index < audioFilters.length) {
      audioFilters[index] = value;
      notifyListeners();
    }
  }

  bool getAudioFilter(int index) {
    if (index >= 0 && index < audioFilters.length) {
      return audioFilters[index];
    }
    return false;
  }

  void setSerialFilter(int index, bool value) {
    if (index >= 0 && index < serialFilters.length) {
      serialFilters[index] = value;
      notifyListeners();
    }
  }

  bool getSerialFilter(int index) {
    if (index >= 0 && index < serialFilters.length) {
      return serialFilters[index];
    }
    return false;
  }
}
