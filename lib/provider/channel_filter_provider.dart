import 'package:flutter/material.dart';

class ChannelFilterProvider extends ChangeNotifier {
  List<bool> audioFilters = [];
  List<bool> serialFilters = [];

  void setAudioChannelCount(int count) {
    audioFilters = List<bool>.filled(count, true);
    notifyListeners();
  }

  void setSerialChannelCount(int count) {
    serialFilters = List<bool>.filled(count, true);
    notifyListeners();
  }

  void setAudioFilter(int index, bool value) {
    if (index >= 0 && index < audioFilters.length) {
      audioFilters[index] = value;
      notifyListeners();
    }
  }

  void setSerialFilter(int index, bool value) {
    if (index >= 0 && index < serialFilters.length) {
      serialFilters[index] = value;
      notifyListeners();
    }
  }
}
