import 'package:flutter/foundation.dart';
import 'package:native_add/model/model.dart';

import '../models/constant.dart';

class DataStatusProvider extends ChangeNotifier {
  bool _isEnableAudio = true;
  bool _isSampleDataOn = false;
  bool _isDeviceDataOn = false;
  bool _is50Hertz = false;
  bool _is60Hertz = false;

  FilterSetup _highPassFilterSettings = const FilterSetup(
      isFilterOn: false,
      filterType: FilterType.highPassFilter,
      filterConfiguration:
          FilterConfiguration(cutOffFrequency: 500, sampleRate: 10000),
      channelCount: channelCountBuffer);

  FilterSetup _lowPassFilterSettings = const FilterSetup(
      isFilterOn: false,
      filterType: FilterType.lowPassFilter,
      filterConfiguration:
          FilterConfiguration(cutOffFrequency: 500, sampleRate: 10000),
      channelCount: channelCountBuffer);

  FilterSetup _notchPassFilterSettings = const FilterSetup(
      isFilterOn: false,
      filterType: FilterType.lowPassFilter,
      filterConfiguration:
          FilterConfiguration(cutOffFrequency: 500, sampleRate: 10000),
      channelCount: channelCountBuffer);

  bool get isDeviceDataOn => _isDeviceDataOn;
  bool get is60Hertz => _is60Hertz;
  bool get is50Hertz => _is50Hertz;
  bool get isSampleDataOn => _isSampleDataOn;
  bool get isMicrophoneData => _isEnableAudio;
  FilterSetup get lowPassFilterSettings => _lowPassFilterSettings;
  FilterSetup get highPassFilterSettings => _highPassFilterSettings;

  setSampleDataStatus(bool sampleDataStatus) {
    _isSampleDataOn = sampleDataStatus;
    notifyListeners();
  }

  set50HertzStatus(bool is50Hertz) {
    _is50Hertz = is50Hertz;
    notifyListeners();
  }

  set60HertzStatus(bool is60Hertz) {
    _is60Hertz = is60Hertz;
    notifyListeners();
  }

  setMicrophoneDataStatus(bool microphoneDataStatus) {
    _isEnableAudio = microphoneDataStatus;
    notifyListeners();
  }

  setDeviceDataStatus(bool isDeviceDataOn) {
    _isDeviceDataOn = isDeviceDataOn;
    notifyListeners();
  }

  setLowPassFilterSetting(FilterSetup filterConfiguration) {
    _lowPassFilterSettings = filterConfiguration;
  }

  setHighPassFilterSetting(FilterSetup filterConfiguration) {
    _highPassFilterSettings = filterConfiguration;
  }

  setNotchPassFilterSetting(FilterSetup filterConfiguration) {
    _notchPassFilterSettings = filterConfiguration;
  }
}
