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
                maxFrequency: maxFreq,
                onFrequencyChanged: (value) {
                  start = value.toDouble();
                  Provider.of<CustomRangeSliderProvider>(context, listen: false)
                      .setStartValue(start);
                  double lowFreq = start == 0 ? -1 : start;
                  double highFreq = end >= maxFreq ? -1 : end;
                  widget.processingUtil.setBandFilter(lowFreq, highFreq);
                  setState(() {});
                },
              ),
              SetFrequencyWidget(
                frequencyType: "High",
                frequencyValue: end.toInt(),
                maxFrequency: maxFreq,
                onFrequencyChanged: (value) {
                  end = value.toDouble();
                  Provider.of<CustomRangeSliderProvider>(context, listen: false)
                      .setEndValue(end);
                  double lowFreq = start == 0 ? -1 : start;
                  double highFreq = end >= maxFreq ? -1 : end;
                  widget.processingUtil.setBandFilter(lowFreq, highFreq);
                  setState(() {});
                },
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
                  setState(() {
                    start = value.start;
                    end = value.end;
                    
                    // Update the slider values in provider
                    Provider.of<CustomRangeSliderProvider>(context, listen: false)
                        .setStartValue(start);
                    Provider.of<CustomRangeSliderProvider>(context, listen: false)
                        .setEndValue(end);

                    // Pass -1 if start is 0 or end is at max
                    double lowFreq = start == 0 ? -1 : start;
                    double highFreq = end >= maxFreq ? -1 : end;
                    widget.processingUtil.setBandFilter(lowFreq, highFreq);
                  });
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

class SetFrequencyWidget extends StatefulWidget {
  const SetFrequencyWidget({
    super.key,
    required this.frequencyType,
    required this.frequencyValue,
    required this.onFrequencyChanged,
    required this.maxFrequency,
  });

  final String frequencyType;
  final int frequencyValue;
  final Function(int) onFrequencyChanged;
  final double maxFrequency;

  @override
  State<SetFrequencyWidget> createState() => _SetFrequencyWidgetState();
}

class _SetFrequencyWidgetState extends State<SetFrequencyWidget> {
  late TextEditingController _controller;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.frequencyValue.toString());
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(SetFrequencyWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Update text field when slider changes the value
    if (oldWidget.frequencyValue != widget.frequencyValue) {
      _controller.text = widget.frequencyValue.toString();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    if (!_focusNode.hasFocus) {
      _validateAndUpdate();
    }
  }

  void _validateAndUpdate() {
    // Parse the input, defaulting to 0 if invalid
    int? value = int.tryParse(_controller.text);
    if (value == null) {
      value = 0;
    }

    // Clamp the value between 0 and maxFrequency
    value = value.clamp(0, widget.maxFrequency.toInt());

    // Update the controller text to show the clamped value
    _controller.text = value.toString();
    
    // Notify parent about the change
    widget.onFrequencyChanged(value);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          "${widget.frequencyType} Frequency",
          style: SoftwareTextStyle().kWtMediumTextStyle,
        ),
        SizedBox(
          width: 100,
          child: TextField(
            controller: _controller,
            focusNode: _focusNode,
            style: SoftwareTextStyle().kWtMediumTextStyle,
            textAlign: TextAlign.center,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              filled: true,
              fillColor: Colors.grey[800],
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            ),
            onTap: () {
              // Select all text when tapped
              _controller.selection = TextSelection(
                baseOffset: 0,
                extentOffset: _controller.text.length,
              );
            },
            onSubmitted: (value) {
              _validateAndUpdate();
            },
          ),
        ),
      ],
    );
  }
}
