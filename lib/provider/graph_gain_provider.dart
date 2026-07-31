import 'package:flutter/material.dart';

class GraphGainProvider extends ChangeNotifier {
  double gain = 1;
  int curChannelIdx = -1;
  int stepGain = 0;

  setGain(double newGain) {
    gain = newGain;
    notifyListeners();
  }
  increaseGainChannel(int channelIndex) {
    stepGain++;
    curChannelIdx = channelIndex;
    notifyListeners();
  }

  decreaseGainChannel(int channelIndex) {
    stepGain--;
    curChannelIdx = channelIndex;
    notifyListeners();
  }

}
