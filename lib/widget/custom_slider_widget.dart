import 'dart:math';

import 'package:flutter/material.dart';
import 'package:native_add/model/model.dart';
import 'package:provider/provider.dart';
import 'package:spikerbox_architecture/provider/custom_slider_provider.dart';
import 'package:spikerbox_architecture/provider/provider_export.dart';

import '../constant/const_export.dart';
import '../models/constant.dart';
import '../models/microphone_stream/microphone_stream_check.dart';
import '../screen/graph_template.dart';

class CustomSliderBarButton extends StatefulWidget {
  const CustomSliderBarButton({
    super.key,
    required this.onHighPassFilterSetup,
    required this.onLowPassFilterSetup,
    required this.onSampleChange,
    required this.isMicrophoneEnable,
  });

  final Function(bool) isMicrophoneEnable;
  final Function(bool) onSampleChange;
  final Function(FilterSetup) onHighPassFilterSetup;
  final Function(FilterSetup) onLowPassFilterSetup;

  @override
  State<CustomSliderBarButton> createState() => _CustomSliderState();
}

class _CustomSliderState extends State<CustomSliderBarButton> {
  MicrophoneUtil microphoneUtil = MicrophoneUtil();

  bool _isSampleDataOn = false;
  bool _isMicrophoneEnable = false;
  late FilterSetup _highPassFilterSettings;
  late FilterSetup _lowPassFilterSettings;

  final TextEditingController _lowSampleRateController =
      TextEditingController();
  final TextEditingController _lowCutOffController = TextEditingController();
  final TextEditingController _highSampleRateController =
      TextEditingController();
  final TextEditingController _highCutOffController = TextEditingController();

  double sliderValue = 0;
  double sampleRate = 0;
  double start = 0;
  double end = 0;

  double maxFreq = 0;

  double logMin = 0;
  double logMax = 0;

  @override
  void initState() {
    super.initState();

    DataStatusProvider dataStatusProvider = context.read<DataStatusProvider>();
//     sliderValue = widget.sliderValue;

    sampleRate = context.read<SampleRateProvider>().sampleRate.toDouble();
    maxFreq = sampleRate / 2;
    logMax = logToLinear(maxFreq);
    CustomRangeSliderProvider customRangeSliderProvider =
        context.read<CustomRangeSliderProvider>();
    start = customRangeSliderProvider.startValue;
    if (start != 0) {
      logMin = logToLinear(start);
    }
    _highCutOffController.text = start.toString();
    double endValue = customRangeSliderProvider.endValue;
    if (endValue == 0) {
      end = maxFreq;
      _lowCutOffController.text = end.toString();
      //  logMax = (log(end).toInt()).toDouble();
    } else {
      end = customRangeSliderProvider.endValue;
      _lowCutOffController.text = end.toString();
      logMax = logToLinear(end);
    }

    _highPassFilterSettings = dataStatusProvider.highPassFilterSettings;
    _lowPassFilterSettings = dataStatusProvider.lowPassFilterSettings;

//  set the starting low pass Filter
    _lowCutOffController.text =
        _lowPassFilterSettings.filterConfiguration.cutOffFrequency.toString();
    _lowSampleRateController.text =
        _lowPassFilterSettings.filterConfiguration.sampleRate.toString();

    _highCutOffController.text =
        _highPassFilterSettings.filterConfiguration.cutOffFrequency.toString();
    _highSampleRateController.text =
        _highPassFilterSettings.filterConfiguration.sampleRate.toString();

    _lowCutOffController.text = start.toInt().toString();
    _highCutOffController.text = end.toInt().toString();
    _isMicrophoneEnable = context.read<DataStatusProvider>().isMicrophoneData;
    _isSampleDataOn = context.read<DataStatusProvider>().isSampleDataOn;
  }

  double logToLinear(double x) {
    return (log(x) / log(10));
  }

  double linearToLog(double x) {
    return pow(10, x).toDouble();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<SampleRateProvider>(
        builder: (context, sampleRateProvider, snapshot) {
      sampleRate = sampleRateProvider.sampleRate.toDouble();
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                SetFrequencyWidget(
                  onStringChanged: (String lowFrequency) {
                    if (lowFrequency.isNotEmpty) {
                      int filterPass = int.parse(lowFrequency);

                      if (filterPass < end && filterPass < maxFreq) {
                        if (filterPass == 0) {
                          setupFilter(
                            cutoffFrequency: filterPass.toDouble(),
                            sampleRate: sampleRate,
                            channelCountBuffer: channelCountBuffer,
                            isFilterOn: false,
                            filterType: FilterType.highPassFilter,
                            onFilterSetup: widget.onHighPassFilterSetup,
                            dataStatusProvider:
                                context.read<DataStatusProvider>(),
                          );
                        } else {
                          setupFilter(
                            cutoffFrequency: filterPass.toDouble(),
                            sampleRate: sampleRate,
                            channelCountBuffer: channelCountBuffer,
                            isFilterOn: true,
                            filterType: FilterType.highPassFilter,
                            onFilterSetup: widget.onHighPassFilterSetup,
                            dataStatusProvider:
                                context.read<DataStatusProvider>(),
                          );
                          logMin = logToLinear(filterPass.toDouble());
                        }
                        _lowCutOffController.text =
                            filterPass.toInt().toString();
                        start = filterPass.toDouble();
                        setState(() {});
                      }
                    }
                  },
                  frequencyEditController: _lowCutOffController,
                  frequencyType: "Low",
                  frequencyValue: start.toInt(),
                ),
                SetFrequencyWidget(
                  onStringChanged: (String highFrequency) {
                    sampleRate = context
                        .read<SampleRateProvider>()
                        .sampleRate
                        .toDouble();

                    if (highFrequency.isNotEmpty) {
                      int filterPass = int.parse(highFrequency);
                      if (filterPass > start && filterPass < maxFreq) {
                        if (end == sampleRate) {
                          setupFilter(
                            cutoffFrequency: filterPass.toDouble(),
                            sampleRate: sampleRate,
                            channelCountBuffer: channelCountBuffer,
                            isFilterOn: false,
                            filterType: FilterType.lowPassFilter,
                            onFilterSetup: widget.onLowPassFilterSetup,
                            dataStatusProvider:
                                context.read<DataStatusProvider>(),
                          );
                        } else {
                          setupFilter(
                            cutoffFrequency: filterPass.toDouble(),
                            sampleRate: sampleRate,
                            channelCountBuffer: channelCountBuffer,
                            isFilterOn: true,
                            filterType: FilterType.lowPassFilter,
                            onFilterSetup: widget.onLowPassFilterSetup,
                            dataStatusProvider:
                                context.read<DataStatusProvider>(),
                          );

                          logMax = logToLinear(filterPass.toDouble());
                        }
                        _highCutOffController.text =
                            filterPass.toInt().toString();
                        end = filterPass.toDouble();
                        setState(() {});
                      }
                    }
                  },
                  frequencyEditController: _highCutOffController,
                  frequencyType: "High",
                  frequencyValue: end.toInt(),
                ),
              ],
            ),
          ),
          Row(
            children: [
              Expanded(
                child: RangeSlider(
                  overlayColor: MaterialStateProperty.resolveWith<Color?>(
                    (Set<MaterialState> states) {
                      if (states.contains(MaterialState.pressed)) {
                        // Color when the thumbs are pressed
                        return Colors.blue.withOpacity(0.5);
                      } else {
                        // Default color
                        return Colors.blue.withOpacity(0.2);
                      }
                    },
                  ),
                  divisions: 50,
                  inactiveColor: Colors.grey,
                  activeColor: SoftwareColors.kGraphColor,
                  values: RangeValues(logMin, logMax),

                  labels: RangeLabels(linearToLog(logMin).toInt().toString(),
                      linearToLog(logMax).toInt().toString()),
                  onChanged: (RangeValues value) {
                    sampleRate = context
                        .read<SampleRateProvider>()
                        .sampleRate
                        .toDouble();
                    setState(() {
                      logMin = value.start;
                      logMax = value.end;
                      start = (linearToLog(logMin).toInt()).toDouble();
                      end = (linearToLog(logMax).toInt()).toDouble();
                    });

                    Provider.of<CustomRangeSliderProvider>(context,
                            listen: false)
                        .setStartValue(start);

                    Provider.of<CustomRangeSliderProvider>(context,
                            listen: false)
                        .setEndValue(end);
                    if (start == 0) {
                      setupFilter(
                        cutoffFrequency: start,
                        sampleRate: sampleRate,
                        channelCountBuffer: channelCountBuffer,
                        isFilterOn: false,
                        filterType: FilterType.highPassFilter,
                        onFilterSetup: widget.onHighPassFilterSetup,
                        dataStatusProvider: context.read<DataStatusProvider>(),
                      );
                    } else {
                      setupFilter(
                        cutoffFrequency: start,
                        sampleRate: sampleRate,
                        channelCountBuffer: channelCountBuffer,
                        isFilterOn: true,
                        filterType: FilterType.highPassFilter,
                        onFilterSetup: widget.onHighPassFilterSetup,
                        dataStatusProvider: context.read<DataStatusProvider>(),
                      );
                    }

                    if (end == sampleRate) {
                      setupFilter(
                        cutoffFrequency: end,
                        sampleRate: sampleRate,
                        channelCountBuffer: channelCountBuffer,
                        isFilterOn: false,
                        filterType: FilterType.lowPassFilter,
                        onFilterSetup: widget.onLowPassFilterSetup,
                        dataStatusProvider: context.read<DataStatusProvider>(),
                      );
                    } else {
                      setupFilter(
                        cutoffFrequency: end,
                        sampleRate: sampleRate,
                        channelCountBuffer: channelCountBuffer,
                        isFilterOn: true,
                        filterType: FilterType.lowPassFilter,
                        onFilterSetup: widget.onLowPassFilterSetup,
                        dataStatusProvider: context.read<DataStatusProvider>(),
                      );
                    }

                    _lowCutOffController.text = start.toInt().toString();
                    _highCutOffController.text = end.toInt().toString();
                    // setState(() {});
                  },
                  min: 0,
                  max: logToLinear(maxFreq),
                  // min: 0,
                  // max: maxFreq,
                ),
              ),
            ],
          ),
        ],
      );
    });
  }

  void setupFilter({
    required double cutoffFrequency,
    required double sampleRate,
    required int channelCountBuffer,
    required bool isFilterOn,
    required FilterType filterType,
    required Function(FilterSetup) onFilterSetup,
    required DataStatusProvider dataStatusProvider,
  }) {
    Provider.of<CustomRangeSliderProvider>(context, listen: false)
        .setEndValue(cutoffFrequency);

    final filterSettings = FilterSetup(
      filterConfiguration: FilterConfiguration(
        cutOffFrequency: cutoffFrequency.toInt(),
        sampleRate: sampleRate.toInt(),
      ),
      filterType: filterType,
      channelCount: channelCountBuffer,
      isFilterOn: isFilterOn,
    );

    if (filterType == FilterType.highPassFilter) {
      dataStatusProvider.setHighPassFilterSetting(filterSettings);
      onFilterSetup(filterSettings);
    } else if (filterType == FilterType.lowPassFilter) {
      dataStatusProvider.setLowPassFilterSetting(filterSettings);
      onFilterSetup(filterSettings);
    } else if (filterType == FilterType.notchFilter) {
      dataStatusProvider.setNotchPassFilterSetting(filterSettings);
    }
  }
}
