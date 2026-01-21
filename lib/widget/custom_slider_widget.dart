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
  }

  @override
  Widget build(BuildContext context) {
    sliderValue = widget.sliderValue;

    print("startValue: ${context.read<CustomRangeSliderProvider>().startValue}");
    print("endValue: ${context.read<CustomRangeSliderProvider>().endValue}");
    print("Slider Value: ${sliderValue}");

    sampleRate = context.read<SampleRateProvider>().sampleRate.toDouble();
    maxFreq = sampleRate / 2;
    start = context.read<CustomRangeSliderProvider>().startValue;
    double endValue = context.read<CustomRangeSliderProvider>().endValue;
    if (endValue == 0) {
      end = maxFreq;
    } else {
      end = context.read<CustomRangeSliderProvider>().endValue;
    }

    print("start: $start, end: $end");
    print("maxFreq: $maxFreq");

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
    
        
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 0),
          child: Row(
            mainAxisSize: MainAxisSize.max,
            // crossAxisAlignment: CrossAxisAlignment.stretch,
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
              Expanded(
                child: Column(
                  children: [
                    Text("Set band-pass filter cutoff frequencies", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                    RangeSlider(
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
                  ],
                ),
              ),
              // LogarithmicFilter(),
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
      //   Row(
      //     children: [
      //       Expanded(
      //         child: RangeSlider(
      //           inactiveColor: Colors.grey,
      //           activeColor: SoftwareColors.kGraphColor,
      //           values: RangeValues(start, end),
      //           labels: RangeLabels(start.toString(), end.toString()),
      //           onChanged: (value) {
      //             setState(() {
      //               start = value.start;
      //               end = value.end;
                    
      //               // Update the slider values in provider
      //               Provider.of<CustomRangeSliderProvider>(context, listen: false)
      //                   .setStartValue(start);
      //               Provider.of<CustomRangeSliderProvider>(context, listen: false)
      //                   .setEndValue(end);

      //               // Pass -1 if start is 0 or end is at max
      //               double lowFreq = start == 0 ? -1 : start;
      //               double highFreq = end >= maxFreq ? -1 : end;
      //               widget.processingUtil.setBandFilter(lowFreq, highFreq);
      //             });
      //           },
      //           min: 0,
      //           max: maxFreq,
      //         ),
      //       ),
      //     ],
      //   ),
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
    // SoftwareTextStyle().kWtMediumTextStyle..color = Color(0xFF707070);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "${widget.frequencyType}",
          style: SoftwareTextStyle().kWtMediumTextStyle.copyWith(color: Color(0xFF707070), fontWeight: FontWeight.w500),
          textAlign: TextAlign.left,
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




// class LogarithmicFilter extends StatefulWidget {
//   @override
//   _LogarithmicFilterState createState() => _LogarithmicFilterState();
// }

// class _LogarithmicFilterState extends State<LogarithmicFilter> {
//   // We use a linear range for the slider (0 to 1) and map it to log values
//   RangeValues _sliderValues = const RangeValues(0.1, 0.5); 
  
//   final double minFreq = 1.0;
//   final double maxFreq = 22050.0;

//   // Convert linear slider position to logarithmic frequency
//   double _lerpLog(double value) {
//     return minFreq * pow(maxFreq / minFreq, value);
//   }

//   // Convert frequency back to linear slider position (for initial setup)
//   double _invLerpLog(double frequency) {
//     return log(frequency / minFreq) / log(maxFreq / minFreq);
//   }

//   @override
//   Widget build(BuildContext context) {
//     double lowFreq = _lerpLog(_sliderValues.start);
//     double highFreq = _lerpLog(_sliderValues.end);

//     return Column(
//       children: [
//         Row(
//           mainAxisAlignment: MainAxisAlignment.spaceAround,
//           children: [
//             _buildValueBox("Low", lowFreq.toInt().toString(), isSelected: true),
//             _buildValueBox("High", highFreq.toInt().toString(), isSelected: false),
//           ],
//         ),
//         SliderTheme(
//           data: SliderThemeData(
//             activeTrackColor: Color(0xFFFF7A5C),
//             inactiveTrackColor: Colors.grey[800],
//             trackHeight: 20,
//             rangeThumbShape: RoundRangeSliderThumbShape(enabledThumbRadius: 0),
//           ),
//           child: RangeSlider(
//             values: _sliderValues,
//             min: 0.0,
//             max: 1.0,
//             onChanged: (values) {
//               setState(() => _sliderValues = values);
//             },
//           ),
//         ),
//         // Frequency labels aligned to the log scale
//         Padding(
//           padding: const EdgeInsets.symmetric(horizontal: 20),
//           child: Row(
//             mainAxisAlignment: MainAxisAlignment.spaceBetween,
//             children: [1, 10, 100, 1000, 10000].map((f) {
//               return Text('$f', style: TextStyle(color: Colors.white, fontSize: 10));
//             }).toList(),
//           ),
//         )
//       ],
//     );
//   }

//   // Helper for the value boxes
//   Widget _buildValueBox(String label, String value, {bool isSelected = false}) {
//     return Column(
//       children: [
//         Text(label, style: TextStyle(color: Colors.grey, fontSize: 12)),
//         Container(
//           margin: EdgeInsets.only(top: 4),
//           padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
//           decoration: BoxDecoration(
//             color: Color(0xFF333333),
//             border: Border.all(color: isSelected ? Colors.purpleAccent : Colors.transparent),
//             borderRadius: BorderRadius.circular(4),
//           ),
//           child: Text(value, style: TextStyle(color: Colors.white)),
//         ),
//       ],
//     );
//   }
// }