import 'package:flutter/foundation.dart';
import 'package:native_add/model/model.dart';

import '../models/constant.dart';

class DataStatusProvider extends ChangeNotifier {
  bool _isMicrophoneData = true;
  bool _isSampleDataOn = false;
  bool _isDeviceDataOn = false;
  bool _is50Hertz = false;
  bool _is60Hertz = false;
  bool _isDebugging = false;

  //

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
      filterType: FilterType.notchFilter,
      filterConfiguration:
          FilterConfiguration(cutOffFrequency: 500, sampleRate: 10000),
      channelCount: channelCountBuffer);

  bool get isDeviceDataOn => _isDeviceDataOn;
  bool get is60Hertz => _is60Hertz;
  bool get is50Hertz => _is50Hertz;
  bool get isSampleDataOn => _isSampleDataOn;
  bool get isMicrophoneData => _isMicrophoneData;
  FilterSetup get lowPassFilterSettings => _lowPassFilterSettings;
  FilterSetup get highPassFilterSettings => _highPassFilterSettings;

  FilterSetup get notchPassFilterSettings => _notchPassFilterSettings;
  bool get isDebugging => _isDebugging;

  setSampleDataStatus(bool sampleDataStatus) {
    _isSampleDataOn = sampleDataStatus;
    notifyListeners();
  }

  setDebuggingDataStatus(bool newStatus) {
    _isDebugging = newStatus;
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
    _isMicrophoneData = microphoneDataStatus;
    notifyListeners();
  }

  setDeviceDataStatus(bool isDeviceDataOn) {
    _isDeviceDataOn = isDeviceDataOn;
    notifyListeners();
  }

  setLowPassFilterSetting(FilterSetup filterConfiguration) {
    _lowPassFilterSettings = filterConfiguration;
    notifyListeners();
  }

  setHighPassFilterSetting(FilterSetup filterConfiguration) {
    _highPassFilterSettings = filterConfiguration;
    notifyListeners();
  }

  setNotchPassFilterSetting(FilterSetup filterConfiguration) {
    _notchPassFilterSettings = filterConfiguration;
    notifyListeners();
  }
}
