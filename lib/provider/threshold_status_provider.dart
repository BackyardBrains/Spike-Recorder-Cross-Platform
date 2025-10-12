import 'package:flutter/material.dart';

class ThresholdStatusProvider extends ChangeNotifier {
  bool isThresholding = false;
  int selectedThresholdChannel = 0;
  int selectedThresholdTriggerType = -1;
  List<int> selectedThresholdParam = List<int>.generate(6, (_) => 525);
  void setThresholdStatus(bool isThresholdingParam) {
    isThresholding = isThresholdingParam;
    notifyListeners();
  }  
  void setThresholdChannel(int selectedThresholdChannelIdx) {
    selectedThresholdChannel = selectedThresholdChannelIdx;
    notifyListeners();
  }  
  void setThresholdParams(List<int> selectedThresholdParams) {
    // print("setThresholdParams: $selectedThresholdParams");
    selectedThresholdParam.setAll(0, selectedThresholdParams);
    notifyListeners();
  }  
  void setThresholdTriggerType(int eventThresholdTriggeredType) {
    selectedThresholdTriggerType = eventThresholdTriggeredType;
    notifyListeners();
  }  

}
