import 'package:flutter/material.dart';
import 'package:native_add/model/model.dart';
import 'package:provider/provider.dart';
import 'package:spikerbox_architecture/provider/custom_slider_provider.dart';
import 'package:spikerbox_architecture/provider/provider_export.dart';

import '../constant/const_export.dart';
import '../models/constant.dart';
import '../models/microphone_stream/microphone_stream_check.dart';
import '../screen/graph_template.dart';
import '../models/processing_utils/processing_util.dart';

class CustomSliderBarButton extends StatefulWidget {
  const CustomSliderBarButton({
    required this.sliderValue,
    required this.startValue,
    required this.endValue,
    required this.processingUtil,
    super.key,
    required this.onHighPassFilterSetup,
    required this.onLowPassFilterSetup,
    required this.onSampleChange,
    required this.isMicrophoneEnable,
  });

  final double sliderValue;
  final double startValue;
  final double endValue;
  final ProcessingUtil processingUtil;
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
  @override
  void initState() {
    super.initState();
    sliderValue = widget.sliderValue;

    sampleRate = context.read<SampleRateProvider>().sampleRate.toDouble();
    maxFreq = sampleRate / 2;
    start = context.read<CustomRangeSliderProvider>().startValue;
    double endValue = context.read<CustomRangeSliderProvider>().endValue;
    if (endValue == 0) {
      end = maxFreq;
    } else {
      end = context.read<CustomRangeSliderProvider>().endValue;
    }

    _highPassFilterSettings =
        context.read<DataStatusProvider>().highPassFilterSettings;
    _lowPassFilterSettings =
        context.read<DataStatusProvider>().lowPassFilterSettings;

//  set the starting low pass Filter
    _lowCutOffController.text =
        _lowPassFilterSettings.filterConfiguration.cutOffFrequency.toString();
    _lowSampleRateController.text =
        _lowPassFilterSettings.filterConfiguration.sampleRate.toString();

    _highCutOffController.text =
        _highPassFilterSettings.filterConfiguration.cutOffFrequency.toString();
    _highSampleRateController.text =
        _highPassFilterSettings.filterConfiguration.sampleRate.toString();

    _isMicrophoneEnable = context.read<DataStatusProvider>().isMicrophoneData;
    _isSampleDataOn = context.read<DataStatusProvider>().isSampleDataOn;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              SetFrequencyWidget(
                frequencyType: "Low",
                frequencyValue: start.toInt(),
              ),
              SetFrequencyWidget(
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
                inactiveColor: Colors.grey,
                activeColor: SoftwareColors.kGraphColor,
                values: RangeValues(start, end),
                labels: RangeLabels(start.toString(), end.toString()),
                onChanged: (value) {
                  start = value.start;
                  end = value.end;
                  
                  // Update the slider values in provider
                  Provider.of<CustomRangeSliderProvider>(context, listen: false)
                      .setStartValue(start);
                  Provider.of<CustomRangeSliderProvider>(context, listen: false)
                      .setEndValue(end);

                  // Directly set the band filter using processingUtil
                  widget.processingUtil.setBandFilter(start.toDouble(), end.toDouble());
                  
                  setState(() {});
                },
                min: 0,
                max: maxFreq,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
