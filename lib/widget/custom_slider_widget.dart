import 'dart:io';
import 'dart:math';
import 'package:another_xlider/another_xlider.dart';
import 'package:another_xlider/models/handler.dart';
import 'package:another_xlider/models/hatch_mark.dart';
import 'package:another_xlider/models/hatch_mark_label.dart';
import 'package:another_xlider/models/slider_step.dart';
import 'package:another_xlider/models/tooltip/tooltip.dart';
import 'package:another_xlider/models/tooltip/tooltip_box.dart';
import 'package:another_xlider/models/trackbar.dart';
import 'package:another_xlider/widgets/sized_box.dart';
import 'package:flutter/foundation.dart';
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
  CustomSliderBarButton({
    required this.sliderValue,
    required this.startValue,
    required this.endValue,
    required this.processingUtil,
    super.key,
    required this.onHighPassFilterSetup,
    required this.onLowPassFilterSetup,
    required this.onSampleChange,
    required this.isMicrophoneEnable,
    required this.channelIdx,
    required this.channelCount,
    this.readOnly = false,
  });

  final int channelIdx;
  final int channelCount;
  final double sliderValue;
  double startValue;
  double endValue;
  bool readOnly;

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
  
  bool isMobileDevice = false;
  @override
  void initState() {
    super.initState();
  }

  // Convert linear frequency to custom log space where 0-1 has step size of 1
  double _linearToCustomLogSpace(double freq, double minLog, double log1) {
    if (freq == 0) {
      return minLog; // 0 maps to minimum log position
    } else if (freq <= 1) {
      // For 0-1 range, snap to integer (0 or 1) and map accordingly
      // Since step size is 1, we map to log1 (which is 0) for any value 0-1
      // This creates a single step position for the entire 0-1 range
      int snapped = freq.round().clamp(0, 1);
      return snapped == 0 ? minLog : log1;
    } else {
      // Values > 1 use normal logarithmic mapping
      return log(freq) / ln10;
    }
  }

  // Convert custom log space back to linear frequency
  double _customLogSpaceToLinear(double logVal, double minLog, double log1) {
    // Use a threshold halfway between minLog and log1 to determine if we're closer to 0 or 1
    double threshold = (minLog + log1) / 2;
    
    if (logVal <= threshold) {
      return 0; // Closer to minLog, return 0
    } else if (logVal <= log1) {
      return 1; // Closer to log1, return 1 (single step for 0-1 range)
    } else {
      // Values > log1 use normal exponential conversion
      return pow(10, logVal).toDouble();
    }
  }

  @override
  Widget build(BuildContext context) {
    sliderValue = widget.sliderValue;

    // print("startValue: ${context.read<CustomRangeSliderProvider>().startValue}");
    // print("endValue: ${context.read<CustomRangeSliderProvider>().endValue}");
    print("BUILD Slider Value: ${sliderValue}");

    sampleRate = context.read<SampleRateProvider>().sampleRate.toDouble();
    maxFreq = sampleRate / 2;
    start = context.read<CustomRangeSliderProvider>().startValue[widget.channelIdx];
    double endValue = context.read<CustomRangeSliderProvider>().endValue[widget.channelIdx];
    if (endValue == 0) {
      end = maxFreq;
    } else {
      end = context.read<CustomRangeSliderProvider>().endValue[widget.channelIdx];
    }

    context.watch<CustomRangeSliderProvider>().addListener(refreshState);

    // print("start: $start, end: $end");
    // print("maxFreq: $maxFreq");

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
    
    // Allow 0 as minimum, but clamp end to maxFreq
    if (start < 0) start = 0;
    if (end < 0) end = 0;
    if (end > maxFreq) end = maxFreq;
    
    // Use 0.1Hz as the minimum for logarithmic calculation (represents 0 in linear space)
    const double minFreqForLog = 0.1;
    double maxLog = log(maxFreq) / ln10;
    double minLog = log(minFreqForLog) / ln10; // Use 0.1Hz for log calculation
    double log1 = log(1.0) / ln10; // log(1) = 0, this is the boundary for 0-1 range
    
    // Convert linear to custom log space (0-1 is a single step)
    double startLog = _linearToCustomLogSpace(start.clamp(0.0, maxFreq), minLog, log1);
    double endLog = _linearToCustomLogSpace(end.clamp(0.0, maxFreq), minLog, log1);
    
    // Clamp log values to valid range
    startLog = startLog.clamp(minLog, maxLog);
    endLog = endLog.clamp(minLog, maxLog);
    if (kIsWeb) {
      isMobileDevice = false;
    } else 
    if (Platform.isIOS || Platform.isAndroid) {
      isMobileDevice = true;
    }
    
            
    return Column(
      children: [
        Container(
          padding: EdgeInsets.all(10),
          decoration: BoxDecoration(
            // color: Color(0xFF2e2e2e),
            borderRadius: BorderRadius.circular(16),
          ),
          // padding: const EdgeInsets.symmetric(horizontal: 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.start,
            mainAxisSize: MainAxisSize.max,
            // crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!widget.readOnly && !isMobileDevice) ... [
                SetFrequencyWidget(
                  frequencyType: "Low",
                  frequencyValue: start.toInt(),
                  maxFrequency: maxFreq,
                  onFrequencyChanged: (value) {
                    start = value.toDouble();
                    Provider.of<CustomRangeSliderProvider>(context, listen: false)
                        .setStartValue(start, widget.channelIdx);
                    double lowFreq = start; // Allow 0 value
                    double highFreq = end >= maxFreq ? -1 : end;
                    // if (widget.channelIdx == -1) {
                    //   for (int i = 0; i < widget.channelCount; i++) {
                    //     widget.processingUtil.setBandFilter(i, lowFreq, highFreq);
                    //   }
                    // } else {
                    //   widget.processingUtil.setBandFilter(widget.channelIdx, lowFreq, highFreq);
                    // }

                    widget.startValue = start;
                    print("START VALUE startValue CUSTOMIZing: ${widget.startValue}");

                    setState(() {});
                  },
                ),
              ],

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Icon(const IconData(0xe90d, fontFamily: "IcomoonIcons"), color: Colors.white),
                        // SizedBox(width: 10),
                        Text("Set band-pass filter cutoff frequencies", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                        // Spacer(),
                        // GestureDetector(
                        //   onTap: () {
                        //     print("Show up setting configuration");
                        //   },
                        //   child: Icon(const IconData(0xe90a, fontFamily: "IcomoonIcons"), color: Colors.white)
                        // ),
                      ],
                    ),
                    IgnorePointer(
                      ignoring: widget.readOnly,
                      child: FlutterSlider(
                        values: [startLog, endLog],
                        rangeSlider: true,
                        min: minLog, // Fixed minimum in log space
                        max: maxLog, // Fixed maximum in log space
                        step: FlutterSliderStep(step: 0.01),                      
                        
                        // Styling to match the "ruler" image
                        trackBar: FlutterSliderTrackBar(
                          activeTrackBar: BoxDecoration(
                            color: SoftwareColors.kButtonBackGroundColor,
                            border: Border.all(color: Colors.grey.shade400, width: 0.5),
                          ),
                          inactiveTrackBar: BoxDecoration(
                            color: Colors.grey.shade700,
                            border: Border.all(color: Colors.grey.shade400, width: 0.5),
                          ),
                          activeTrackBarHeight: 20, // Match the thick bar in the image
                          inactiveTrackBarHeight: 20,
                        ),
                      
                        // Rectangular grey handlers as seen in your reference
                        handler: customThumb(),
                        rightHandler: customThumb(),
                      
                        // The "Ruler" markings
                        hatchMark: FlutterSliderHatchMark(
                          displayLines: false, // We turn off default lines to use our own
                          labels: _generateRulerItems(minLog, maxLog),
                        ),             
                      
                        tooltip: FlutterSliderTooltip(
                          alwaysShowTooltip: false,
                          boxStyle: FlutterSliderTooltipBox(
                            decoration: BoxDecoration(color: Colors.black),
                          ),
                          textStyle: TextStyle(color: Colors.white, fontSize: 12),
                          format: (String value) {
                            // Convert custom log space back to linear frequency for display
                            double logVal = double.tryParse(value) ?? 0;
                            const double minFreqForLog = 0.1;
                            double minLog = log(minFreqForLog) / ln10;
                            double log1 = log(1.0) / ln10;
                            double freq = _customLogSpaceToLinear(logVal, minLog, log1);
                            if (freq == 0) {
                              return "0";
                            }
                            return freq >= 1000 ? "${(freq / 1000).toStringAsFixed(1)}k" : freq.toStringAsFixed(0);
                          },
                        ),
                      
                        onDragging: (handlerIndex, lowerValue, upperValue) {
                          setState(() {
                            // Convert from custom log space back to linear frequency space
                            const double minFreqForLog = 0.1;
                            double minLog = log(minFreqForLog) / ln10;
                            double log1 = log(1.0) / ln10;
                            
                            // Use custom conversion function
                            start = _customLogSpaceToLinear(lowerValue, minLog, log1);
                            end = _customLogSpaceToLinear(upperValue, minLog, log1);
                            
                            // Snap values in 0-1 range to discrete steps (step size = 1)
                            // This ensures 0-1 range has only integer values (0 or 1)
                            if (start >= 0 && start <= 1) {
                              start = start.round().clamp(0, 1).toDouble();
                            }
                            if (end >= 0 && end <= 1) {
                              end = end.round().clamp(0, 1).toDouble();
                            }
                            
                            // Clamp values to valid range (allow 0, max is maxFreq)
                            start = start.clamp(0.0, maxFreq);
                            end = end.clamp(0.0, maxFreq);
                      
                            // 1. Update Provider
                            final provider = Provider.of<CustomRangeSliderProvider>(context, listen: false);
                            provider.setStartValue(start, widget.channelIdx);
                            widget.startValue = start;
                            provider.setEndValue(end, widget.channelIdx);
                            widget.endValue = end;
                      
                            // 2. Logic for processingUtil - allow 0 value
                            double lowFreq = start; // Allow 0 value
                            // double highFreq = end >= maxFreq ? -1 : end;
                            double highFreq = end >= maxFreq ? maxFreq : end;
                            print("widget.channelIdx: ${widget.channelIdx} | end : $end | maxFreq: $maxFreq");
                            if (widget.channelIdx == -1) {
                              for (int i = 0; i < widget.channelCount; i++) {
                                widget.processingUtil.setBandFilter(i, lowFreq, highFreq);
                              }
                            } else {
                              print("setBandFilter: ${widget.channelIdx}, lowFreq: $lowFreq, highFreq: $highFreq");
                              widget.processingUtil.setBandFilter(widget.channelIdx, lowFreq, highFreq);
                            }
                          });
                        },
                      ),
                    )                    
                    // RangeSlider(
                    //   inactiveColor: Colors.grey,
                    //   activeColor: SoftwareColors.kGraphColor,
                    //   values: RangeValues(start, end),
                    //   labels: RangeLabels(start.toString(), end.toString()),
                    //   onChanged: (value) {
                    //     setState(() {
                    //       start = value.start;
                    //       end = value.end;
                          
                    //       // Update the slider values in provider
                    //       Provider.of<CustomRangeSliderProvider>(context, listen: false)
                    //           .setStartValue(start);
                    //       Provider.of<CustomRangeSliderProvider>(context, listen: false)
                    //           .setEndValue(end);
                    
                    //       // Pass -1 if start is 0 or end is at max
                    //       double lowFreq = start == 0 ? -1 : start;
                    //       double highFreq = end >= maxFreq ? -1 : end;
                    //       widget.processingUtil.setBandFilter(lowFreq, highFreq);
                    //     });
                    //   },
                    //   min: 0,
                    //   max: maxFreq,
                    // ),
                  ],
                ),
              ),

              if (!widget.readOnly && !isMobileDevice) ... [
                SetFrequencyWidget(
                  frequencyType: "High",
                  frequencyValue: end.toInt(),
                  maxFrequency: maxFreq,
                  onFrequencyChanged: (value) {
                    end = value.toDouble();
                    Provider.of<CustomRangeSliderProvider>(context, listen: false)
                        .setEndValue(end, widget.channelIdx);
                    double lowFreq = start; // Allow 0 value
                    double highFreq = end >= maxFreq ? -1 : end;
                    // widget.processingUtil.setBandFilter(widget.channelIdx, lowFreq, highFreq);
                    // if (widget.channelIdx == -1) {
                    //   for (int i = 0; i < widget.channelCount; i++) {
                    //     widget.processingUtil.setBandFilter(i, lowFreq, highFreq);
                    //   }
                    // } else {
                    //   widget.processingUtil.setBandFilter(widget.channelIdx, lowFreq, highFreq);
                    // }
                    widget.endValue = end;
                    print("endValue CUSTOMIZing: ${widget.endValue}");

                    setState(() {});
                  },
                ),
              ],
              
            ],
          ),
        ),
        if (isMobileDevice) ... [
          Row(
            children: [
              Container(
                margin: EdgeInsets.only(left:10, bottom: 10),
                child: SetFrequencyWidget(
                  frequencyType: "Low",
                  frequencyValue: start.toInt(),
                  maxFrequency: maxFreq,
                  onFrequencyChanged: (value) {
                    start = value.toDouble();
                    Provider.of<CustomRangeSliderProvider>(context, listen: false)
                        .setStartValue(start, widget.channelIdx);
                    double lowFreq = start; // Allow 0 value
                    double highFreq = end >= maxFreq ? -1 : end;
                    // if (widget.channelIdx == -1) {
                    //   for (int i = 0; i < widget.channelCount; i++) {
                    //     widget.processingUtil.setBandFilter(i, lowFreq, highFreq);
                    //   }
                    // } else {
                    //   widget.processingUtil.setBandFilter(widget.channelIdx, lowFreq, highFreq);
                    // }
                
                    widget.startValue = start;
                    print("START VALUE startValue CUSTOMIZing: ${widget.startValue}");
                
                    setState(() {});
                  },
                ),
              ),
              Spacer(),
              Container(
                margin: EdgeInsets.only(right:10, bottom: 10),
                child: SetFrequencyWidget(
                  frequencyType: "High",
                  frequencyValue: end.toInt(),
                  maxFrequency: maxFreq,
                  onFrequencyChanged: (value) {
                    end = value.toDouble();
                    Provider.of<CustomRangeSliderProvider>(context, listen: false)
                        .setEndValue(end, widget.channelIdx);
                    double lowFreq = start; // Allow 0 value
                    double highFreq = end >= maxFreq ? -1 : end;
                    // widget.processingUtil.setBandFilter(widget.channelIdx, lowFreq, highFreq);
                    // if (widget.channelIdx == -1) {
                    //   for (int i = 0; i < widget.channelCount; i++) {
                    //     widget.processingUtil.setBandFilter(i, lowFreq, highFreq);
                    //   }
                    // } else {
                    //   widget.processingUtil.setBandFilter(widget.channelIdx, lowFreq, highFreq);
                    // }
                    widget.endValue = end;
                    print("endValue CUSTOMIZing: ${widget.endValue}");
                
                    setState(() {});
                  },
                ),
              ),


            ],
          ),
        ]
        
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


  List<FlutterSliderHatchMarkLabel> _generateRulerItems(double minL, double maxL) {
    List<FlutterSliderHatchMarkLabel> items = [];

    // Add 0 label at the leftmost position (minL represents 0 via 0.1Hz mapping)
    const double minFreqForLog = 0.1;
    double minLogForZero = log(minFreqForLog) / ln10;
    if ((minL - minLogForZero).abs() < 0.01) { // Check if minL represents 0
      items.add(
        FlutterSliderHatchMarkLabel(
          percent: 0,
          label: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(height: 42),
              Container(
                width: 1,
                height: 10, // Major tick height
                color: Colors.white,
              ),
              Text(
                "0",
                style: TextStyle(color: Colors.white, fontSize: 10),
              ),
            ],
          ),
        ),
      );
    }

    // Iterate through decades (1, 10, 100, 1000, 10000)
    for (int exp = 0; exp <= 4; exp++) {
      // Major ticks (powers of 10)
      num majorVal = pow(10, exp);
      if (majorVal > maxFreq) break;
      
      double majorLogVal = log(majorVal) / ln10;
      double majorPercent = ((majorLogVal - minL) / (maxL - minL)) * 100;
      
      // Add major tick mark (taller)
      items.add(
        FlutterSliderHatchMarkLabel(
          percent: majorPercent,
          label: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(height: 42),
              Container(
                width: 1,
                height: 10, // Major tick height
                color: Colors.white,
              ),
              Text(
                _formatLabel(majorVal.toDouble()),
                style: TextStyle(color: Colors.white, fontSize: 10),
              ),
            ],
          ),
        ),
      );

      // Minor ticks (2-9 within each decade)
      if (exp < 4) { // Don't add minor ticks after the last major tick
        for (int m = 2; m <= 9; m++) {
          num minorVal = m * pow(10, exp);
          if (minorVal > maxFreq) break;
          
          double minorLogVal = log(minorVal) / ln10;
          double minorPercent = ((minorLogVal - minL) / (maxL - minL)) * 100;
          
          // Add minor tick mark (shorter)
          items.add(
            FlutterSliderHatchMarkLabel(
              percent: minorPercent,
              label: Container(
                margin: EdgeInsets.only(top: 24),
                width: 1,
                height: 6, // Minor tick height
                color: Colors.white,
              ),
            ),
          );
        }
      }
    }
    return items;
  }

  String _formatLabel(double value) {
    int intVal = value.toInt();
    // Format numbers >= 1000 with commas
    if (intVal >= 1000) {
      String str = intVal.toString();
      // Add comma every 3 digits from right
      String result = '';
      for (int i = 0; i < str.length; i++) {
        if (i > 0 && (str.length - i) % 3 == 0) {
          result += ',';
        }
        result += str[i];
      }
      return result;
    }
    return intVal.toString();
  }


  FlutterSliderHandler customThumb() {
    return FlutterSliderHandler(
      // 1. Remove the default white circle and shadow here
      decoration: BoxDecoration(
        color: Colors.transparent, // Removes the white background
      ),
      // 2. Disable the shadow if it's still appearing
      // shadowStep: 0, 
      child: Container(
        width: 24,
        height: 24,
        color: Colors.grey, // Your square box
      ),
    );
  }

  void refreshState() {
    print("REFRESH STATE startValue: ${context.read<CustomRangeSliderProvider>().startValue}");
    setState(() {
      
    });
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
        SizedBox(height: 4),
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