import 'package:flutter/material.dart';
import '../constant/colors_constant.dart';
import '../constant/channel_color_defaults.dart';

class ChannelColorProvider extends ChangeNotifier {
  List<Color> audioColors = [];
  List<Color> serialColors = [];
  List<int> visibleChannels = [];
  int visibleChannelsCount = 1;
  int isRecording = 0;

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
    _syncVisibleChannelsLength(count);
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
    _syncVisibleChannelsLength(count);
    notifyListeners();
  }

  void _syncVisibleChannelsLength(int count) {
    while (visibleChannels.length < count) {
      visibleChannels.add(1);
    }
    if (visibleChannels.length > count) {
      visibleChannels.removeRange(count, visibleChannels.length);
    }
    visibleChannelsCount =
        visibleChannels.where((visibility) => visibility == 1).length;
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

  void setIsRecording(int recordingStatus) {
    isRecording = recordingStatus;
  }

  int getIsRecording() {
    return isRecording;
  }

  void setVisibleChannel(int idx) {
    if (visibleChannels[idx] == 1) {
      visibleChannels[idx] = 0;
      visibleChannelsCount--;
    } else {
      visibleChannels[idx] = 1;
      visibleChannelsCount++;
    }
  }

  List<int> getVisibleChannel() {
    return visibleChannels;
  }
  int getVisibleChannelCount() {
    return visibleChannelsCount;
  }
  void setVisibleChannelCount(int count) {
    visibleChannelsCount = count;
  }

}
