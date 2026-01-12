import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:another_xlider/another_xlider.dart';
import 'package:another_xlider/models/handler.dart';
import 'package:another_xlider/models/tooltip/tooltip.dart';
import 'package:another_xlider/models/trackbar.dart';
import 'package:dotted_line/dotted_line.dart';
import 'package:dropdown_button2/dropdown_button2.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_audio_waveforms/flutter_audio_waveforms.dart'
    as WavForm;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:spikerbox_architecture/functionality/debouncer.dart';
import 'package:spikerbox_architecture/models/processing_utils/processing_util.dart';
import 'package:spikerbox_architecture/provider/devices_provider.dart';
import 'package:spikerbox_architecture/provider/fft_status_provider.dart';
import 'package:spikerbox_architecture/provider/graph_gain_provider.dart';
import 'package:spikerbox_architecture/provider/graph_stream_data.dart';
import 'package:spikerbox_architecture/provider/isgraphplay_provider.dart';
import 'package:spikerbox_architecture/provider/sample_rate_provider.dart';
import 'package:spikerbox_architecture/provider/threshold_status_provider.dart';
import 'package:spikerbox_architecture/provider/vertical_dragprovider.dart';
import 'package:spikerbox_architecture/provider/data_type_status.dart';
import 'package:spikerbox_architecture/provider/channel_color_provider.dart';
import 'package:spikerbox_architecture/screen/graph_template.dart';
import 'package:spikerbox_architecture/widget/fft_painter.dart';

import '../constant/const_export.dart';
import '../widget/widget_export.dart';

class SpikerBoxUi extends StatefulWidget {
  const SpikerBoxUi({
    super.key,
  });

  @override
  State<SpikerBoxUi> createState() => _SpikerBoxUiState();
}

class _SpikerBoxUiState extends State<SpikerBoxUi> {
  List<double> eventMarkersPosition = [];
  List<int> eventMarkersNumber = [];
  double position = 0;

  List<Widget> listUIElements = [];

  @override
  Widget build(BuildContext context) {
    listUIElements.clear();
    listUIElements.addAll([
      DraggableSection(),
      TimeCalculateWidget(),
      // DraggableRectangle(),
      Positioned(
        left:0,
        top: MediaQuery.of(context).size.height * 0.2,
        child: FftSection()
      ),
    ]);
    return Stack(
      children: listUIElements,
    );
  }
}

class TimeCalculateWidget extends StatefulWidget {
  static double widthOfScale = 0;
  static double displayTimeMsLabel = 0.0;
  static double prevWidthOfScale = 0;
  static double prevDisplayTimeMsLabel = 0.0;

  const TimeCalculateWidget({
    super.key,
  });

  @override
  State<TimeCalculateWidget> createState() => _TimeCalculateWidgetState();
}

class _TimeCalculateWidgetState extends State<TimeCalculateWidget> {
  ValueNotifier<double> lineWidthScaleNotifier = ValueNotifier(100.0);
  // Class-level constants
  final List<double> scales = [
    1,
    2,
    5,
    10,
    20,
    50,
    100,
    200,
    500,
    1000,
    2000,
    5000,
    10000,
    20000
  ];
  final List<String> scalesStr = [
    "1ms",
    "2ms",
    "5ms",
    "10ms",
    "20ms",
    "50ms",
    "100ms",
    "200ms",
    "500ms",
    "1s",
    "2s",
    "5s",
    "10s",
    "20s"
  ];
  double widthOfScreen = -1;
  double widthOfScale = 100;
  @override
  void initState() {
    super.initState();
  }

  Map<String, dynamic> calculateScaleFromWaveform(
      double displayTimeMs, double drawSurfaceWidth, int sampleRate) {
      
    // Get the actual sample range being displayed
    int fromSample = DraggableGraph.startPositionIdx;
    int toSample = DraggableGraph.endPositionIdx;
    
    // If sample range is invalid, fall back to displayTimeMs calculation
    if (toSample <= fromSample || sampleRate <= 0) {
      calculateDisplayTime(displayTimeMs, sampleRate, drawSurfaceWidth);
      return {};
    }

    // Calculate actual time range being displayed (in milliseconds)
    // This matches how DrawingUtils::prepareSignalForDrawing maps samples to pixels
    int sampleRange = toSample - fromSample;
    double timeRangeMs = (sampleRange / sampleRate) * 1000.0;

    // Find appropriate scale that fits within the time range
    // We want a scale that's roughly 1/5 to 1/2 of the total time range
    double targetScaleTime = timeRangeMs / 5.0;
    String finalString = '';
    double selectedScaleTime = 0;

    // Find the appropriate scale
    for (int i = 1; i < scales.length; i++) {
      if (targetScaleTime < scales[i]) {
        selectedScaleTime = scales[i - 1];
        finalString = scalesStr[i - 1];

        // STEVANUS
        TimeCalculateWidget.prevWidthOfScale = TimeCalculateWidget.widthOfScale;
        TimeCalculateWidget.prevDisplayTimeMsLabel = TimeCalculateWidget.displayTimeMsLabel;
        double scaleWidth = (selectedScaleTime / timeRangeMs) * drawSurfaceWidth;
        widthOfScale = scaleWidth;
        TimeCalculateWidget.widthOfScale = widthOfScale;
        TimeCalculateWidget.displayTimeMsLabel = selectedScaleTime;
        if (TimeCalculateWidget.prevWidthOfScale == 0) {
          TimeCalculateWidget.prevWidthOfScale = widthOfScale;
          TimeCalculateWidget.prevDisplayTimeMsLabel = scales[i - 1];
        }
        break;
      }
    }

    // If no scale was found (value is larger than all scales), use the last scale
    if (finalString.isEmpty) {
      selectedScaleTime = scales.last;
      finalString = scalesStr.last;
    }

    // Calculate the pixel width of the scale bar
    // This matches the xStep calculation: pixels = (scaleTime / timeRange) * drawSurfaceWidth
    double scaleWidth = (selectedScaleTime / timeRangeMs) * drawSurfaceWidth;

    // Ensure minimum and maximum widths for visibility
    if (scaleWidth < 20) scaleWidth = 20;
    if (scaleWidth > drawSurfaceWidth * 0.8) scaleWidth = drawSurfaceWidth * 0.8;
    if (finalString.isEmpty) {
      double value = displayTimeMs / 5;
      finalString = scalesStr.last;
      widthOfScale = (scales.last / value) * widthOfScreen;
      scaleWidth = widthOfScale;
      TimeCalculateWidget.widthOfScale = widthOfScale;
    }


    return {
      'label': finalString,
      'width': scaleWidth,
      'scaleTime': selectedScaleTime,
      'timeRange': timeRangeMs,
    };
  }

  String finalString = '';
  String calculateDisplayTime(double? rawTime, int sampleRate, double drawSurfaceWidth) {
    if (rawTime == null) return '10s';

    double value = rawTime / 5; // timeline width - 10s -> 2s default
    // double value = rawTime;
    print("VALUE: $value");
    // await Future.delayed(Duration(milliseconds: 70));
    if (ProcessingUtil.fromDrawingIdx == 0 && ProcessingUtil.toDrawingIdx == 0) {
      return finalString;
    }
    finalString = '';

    int fromDrawingIdx = ProcessingUtil.fromDrawingIdx;
    int toDrawingIdx = ProcessingUtil.toDrawingIdx;
    int sampleRange = toDrawingIdx - fromDrawingIdx;

    double samplesPerMs = sampleRange / rawTime;
    double samplesPerEnvelopePixel = sampleRange / drawSurfaceWidth;
    print("FROM DRAWING IDX: $fromDrawingIdx, TO DRAWING IDX: $toDrawingIdx");
    print("samplesPerMs: $samplesPerMs, samplesPerEnvelopePixel: $samplesPerEnvelopePixel, sampleRange: $sampleRange, rawTime: $rawTime, drawSurfaceWidth: $drawSurfaceWidth");
    // double lineWidthInSecond = rawTime / 1000;


    // print("sampleRange: $sampleRange, envelopeSkipSize: $envelopeSkipSize, RANGE: ${sampleRange/envelopeSkipSize}, fromDrawingIdx: $fromDrawingIdx, toDrawingIdx: $toDrawingIdx");
    // Find the appropriate scale
    for (int i = 1; i < scales.length; i++) {
      if (value < scales[i]) {
        TimeCalculateWidget.prevWidthOfScale = TimeCalculateWidget.widthOfScale;
        TimeCalculateWidget.prevDisplayTimeMsLabel =
            TimeCalculateWidget.displayTimeMsLabel;
        finalString = scalesStr[i];
        // widthOfScale = (scales[i - 1] / rawTime) * widthOfScreen;

        // print("sampleRange: $sampleRange, envelopeSkipSize: $envelopeSkipSize, drawSurfaceWidth: $drawSurfaceWidth | RawTime: ${rawTime} | scales: ${scales[i-1]}");
        double pixelsPerLineMs = samplesPerMs / samplesPerEnvelopePixel; // 800/ 5 = 160
        widthOfScale = ((pixelsPerLineMs) * scales[i]).ceilToDouble();
        print("cales[i]: ${scales[i]}, pixelsPerLineMs: $pixelsPerLineMs, samplesPerMs: $samplesPerMs, samplesPerEnvelopePixel: $samplesPerEnvelopePixel, widthOfScale: $widthOfScale");
        // 1 pixel = x ms
        // (pcs/pixel)/ms
        print(
            "(${scales[i - 1]} / $rawTime) * $widthOfScreen ==== ${(scales[i - 1] / rawTime) * widthOfScreen} === WidthOfScale: $widthOfScale");
        TimeCalculateWidget.widthOfScale = widthOfScale;
        TimeCalculateWidget.displayTimeMsLabel = scales[i];
        if (TimeCalculateWidget.prevWidthOfScale == 0) {
          TimeCalculateWidget.prevWidthOfScale = widthOfScale;
          TimeCalculateWidget.prevDisplayTimeMsLabel = scales[i];
        }

        Future.delayed(Duration(milliseconds: 100), () {
          lineWidthScaleNotifier.value = widthOfScale;
          print("pixelsPerLineMs: $pixelsPerLineMs");
        });
        // static double prevWidthOfScale = 0;
        // static double prevDisplayTimeMsLabel = 0.0;

        break;
      }
    }

    // If no scale was found (value is larger than all scales), use the last scale
    if (finalString.isEmpty) {
      finalString = scalesStr.last;
      widthOfScale = (scales.last / value) * widthOfScreen;
      TimeCalculateWidget.widthOfScale = widthOfScale;
    }

    return finalString;
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<GraphDataProvider>(
        builder: (context, graphDataProvider, _) {
      final myDataProvider = Provider.of<SampleRateProvider>(context, listen: false);
      final sampleRate = myDataProvider.sampleRate;
      final drawSurfaceWidth = MediaQuery.of(context).size.width;

      widthOfScreen = MediaQuery.of(context).size.width;
      
      return Align(
        alignment: const Alignment(0.8, 0.6),
        child: SizedBox(
          height: 40,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              ValueListenableBuilder<double>(
                valueListenable: lineWidthScaleNotifier, 
                builder: (context, value, child) {
                  print("Value: $value");
                  return Container(
                    height: 3,
                    width: value,
                    color: Colors.white,
                  );
                }
              ),
              StreamBuilder<double>(
                stream: graphDataProvider.displayTimeStream,
                initialData: 10000.0,
                builder: (context, snapshot) {
                  print("Stream builder: Display Time: ${snapshot.data}");
                  if (snapshot.data != null && snapshot.data!.toDouble() == 10000.0) {
                    TimeCalculateWidget.displayTimeMsLabel = 2000;
                    double samplesPerMs = sampleRate / 1000;
                    double samplesPerEnvelopePixel = ProcessingUtil.MAX_DISPLAY_SECONDS * sampleRate / drawSurfaceWidth;
                    double lineWidthInSecond = ProcessingUtil.MAX_DISPLAY_SECONDS / 5;
                    double samplesPerLineWidth = lineWidthInSecond * 1000 * samplesPerMs;
                    double pixelsPerLineWidth = samplesPerLineWidth / samplesPerEnvelopePixel; // 800/ 5 = 160

                    widthOfScale = pixelsPerLineWidth;
                    TimeCalculateWidget.widthOfScale = pixelsPerLineWidth;
                    Future.delayed(Duration(milliseconds: 100), () {
                      lineWidthScaleNotifier.value = widthOfScale;
                    });
                    TimeCalculateWidget.prevDisplayTimeMsLabel = TimeCalculateWidget.displayTimeMsLabel;
                    TimeCalculateWidget.prevWidthOfScale = TimeCalculateWidget.widthOfScale;

                    return Text(
                      "2s",
                      style: SoftwareTextStyle().kWtMediumTextStyle,
                    );
                  } else {
                    String textLabel = calculateDisplayTime(snapshot.data, sampleRate, drawSurfaceWidth);
                    return Text(
                      textLabel,
                      style: SoftwareTextStyle().kWtMediumTextStyle,
                    );
                    // return FutureBuilder(
                    //   future: calculateDisplayTime(snapshot.data, sampleRate, drawSurfaceWidth), 
                    //   builder: (context, futureSnapshot) {
                    //     if (futureSnapshot.data == null) {
                    //       return Text(
                    //         "2s",
                    //         style: SoftwareTextStyle().kWtMediumTextStyle,
                    //       );
                    //     }
                        
                    //     return Text(
                    //       futureSnapshot.data as String,
                    //       style: SoftwareTextStyle().kWtMediumTextStyle,
                    //     );
                    //   }
                    // );
                  }
                },
              ),
            ],
          ),
        ),
      );
    });
  }
}

class DraggableSection extends StatelessWidget {
  const DraggableSection({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
        width: MediaQuery.of(context).size.width,
        height: MediaQuery.of(context).size.height,
        child: DraggableGraph());
    // return LayoutBuilder(builder: (context, constraints) {
    //   Provider.of<VerticalDragProvider>(context, listen: false).initialOffset =
    //       constraints.maxHeight / 2;
    //   return Consumer<VerticalDragProvider>(
    //     builder: (context, verticalDrag, snapshot) {
    //       return Stack(
    //         clipBehavior: Clip.hardEdge,
    //         children: [
    //           Positioned(
    //             top: verticalDrag.topPosition,
    //             left: 0,
    //             child: SizedBox(
    //               width: constraints.maxWidth,
    //               height: constraints.maxHeight,
    //               child: const Row(
    //                 mainAxisAlignment: MainAxisAlignment.center,
    //                 children: [
    //                   SizedBox(child: DraggableButton()),
    //                   Expanded(
    //                     child: DraggableGraph(),
    //                   ),
    //                 ],
    //               ),
    //             ),
    //           ),
    //         ],
    //       );
    //     },
    //   );
    // });
  }
}

class DraggableGraph extends StatefulWidget {
  const DraggableGraph({super.key});
  static int startPositionIdx = 0;
  static int endPositionIdx = 0;
  static List<double> eventMarkersPosition = [];
  static List<int> eventMarkersLabels = [];

  @override
  State<DraggableGraph> createState() => _DraggableGraphState();
}

class _DraggableGraphState extends State<DraggableGraph> {
  int channelCount = 1;
  List<double> gainChannel = [];
  List<double> topChartY = [];
  List<double> midChartY = [];
  List<bool> showWaveform = [];
  double widthChart = 800;
  double heightChart = 600;
  double defaultGain = 0.25 * 0.25;
  // double defaultGain = 0.125;
  
  FocusNode keyboardFocusNode = FocusNode();
  Debouncer debouncerKeyboard = Debouncer(milliseconds: 77);
  
  @override
  void initState() {
    super.initState();
    Stream<List<double>> dataStream =
        Provider.of<GraphDataProvider>(context, listen: false)
                .outputGraphStream ??
            const Stream.empty();
    dataStream.listen((data) {
      isLoading = false;
      setState(() {});
    });
    Future.delayed(Duration(seconds: 1), () {
      initializeGraph();
      keyboardFocusNode.requestFocus();
      // init Threshold Value
    });

    Timer.periodic(Duration(seconds: 1), (_){
      keyboardFocusNode.requestFocus();
    });
    
    ProcessingUtil.initializeDevice.removeListener(initializeDeviceListener);
    ProcessingUtil.initializeDevice.addListener(initializeDeviceListener);
    selectedThresholdIdx = context.read<ThresholdStatusProvider>().selectedThresholdChannel;
    // if (thresholdMarkerTop[selectedThresholdIdx] == -10000) {
    //   initLevelMedian(1);
    // }
  }

  void initializeGraph() {
    widthChart = MediaQuery.of(context).size.width;

    // channelCount = ProcessingUtil.drawingBuffers.length == 0 ? 1 : ProcessingUtil.drawingBuffers.length;
    channelCount = context.read<ConstantProvider>().getChannelCount();

    heightChart = MediaQuery.of(context).size.height /
        (channelCount == 0 ? 1 : channelCount);
    topChartY.clear();
    midChartY.clear();
    gainChannel.clear();
    showWaveform.clear();
    for (int i = 0; i < channelCount; i++) {
      double top = (heightChart * i);
      topChartY.add(top);
      midChartY.add((top + heightChart / 2 - thresholdIconTopDifference));
      gainChannel.add(defaultGain);
      topDroplet = midChartY.last;
      showWaveform.add(true);
    }

    isInitializedGraph = true;
    // double topChartY = heightChart * idx;
  }

  // void addThresholdInteractionControls(List<Widget> thresholdAdditionalControls) {
  //   thresholdAdditionalControls.add(
  //     SizedBox(
  //       child: Transform.rotate(
  //         angle: -90 * pi / 180,
  //         child: Icon(
  //           Icons.water_drop,
  //           color: Colors.green,
  //           size: 36,
  //         ),
  //       ),
  //     )
  //   );
  // }


  void addThresholdControls(List<Widget> thresholdControls) {
    thresholdControls.addAll(
      [                      
        Center(
        ),
        SizedBox(
          width: 20,
        ),
        Container(
          margin: EdgeInsets.fromLTRB(0, 10, 0, 0),
          width:200,
          height:30,
          child: FlutterSlider(
            tooltip: FlutterSliderTooltip(
              disabled: true,
            ),
            min: 0,
            max: 1000,
            handler: FlutterSliderHandler(
              child: Material(
                type: MaterialType.canvas,
                color: Colors.grey.shade500,
                elevation: 3,
                child: Container(
                    padding: EdgeInsets.all(5),
                    // child: Icon(Icons.adjust, size: 25,)
                  ),
              ),                                                          
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(0),
                color: Colors.grey,
                border: Border.all(width: 3, color: Colors.white),
              )
            ),
            trackBar: FlutterSliderTrackBar(
              inactiveTrackBarHeight: 70,
              activeTrackBarHeight: 70,
              inactiveTrackBar: BoxDecoration(
                borderRadius: BorderRadius.circular(0),
                color: Colors.grey,
                border: Border.all(width: 3, color: Colors.black45),
              ),
              activeTrackBar: BoxDecoration(
                borderRadius: BorderRadius.circular(0),
                color: Colors.grey.withOpacity(0.5)
              ),
            ), values: [100],
          )
        ),
        const SizedBox(
          width: 10,
        ),
      ]

    );

  }

  void addChartControls(
      List<Widget> charts, int idx, int channelCount, BuildContext context) {
    // print("addChartControls : $idx, $channelCount --- ${DateTime.now().microsecondsSinceEpoch}");
    double leftDroplet = 5;
    final colorProvider = Provider.of<ChannelColorProvider>(context, listen: false);


    selectedThresholdIdx = context.read<ThresholdStatusProvider>().selectedThresholdChannel;
    bool isThresholding = context.read<ThresholdStatusProvider>().isThresholding;
    if (!isThresholding) {
      keyboardCharacter = "";
    }
    final isAudio = Provider.of<DataStatusProvider>(context, listen: false)
        .isMicrophoneData;

    Color channelColor = isAudio
        ? (idx < colorProvider.audioColors.length
            ? colorProvider.audioColors[idx]
            : SoftwareColors.kGraphColor)
        : (idx < colorProvider.serialColors.length
            ? colorProvider.serialColors[idx]
            : SoftwareColors.kGraphColor);

    Color selectedChannelColor = isAudio
        ? (idx < colorProvider.audioColors.length
            ? colorProvider.audioColors[selectedThresholdIdx]
            : SoftwareColors.kGraphColor)
        : (idx < colorProvider.serialColors.length
            ? colorProvider.serialColors[selectedThresholdIdx]
            : SoftwareColors.kGraphColor);       
    // if (selectedThresholdIdx != 0) {
    //   print("colorProvider.serialColors[selectedThresholdIdx] :  ${selectedThresholdIdx}");
    // }
    charts.add(Positioned(
      top: midChartY[idx].toDouble() - 15,
      left: leftDroplet,
      child: GestureDetector(
        onTap: () {
          increaseGain(idx);
          // GraphGainProvider graphGainProvider =
          //     Provider.of<GraphGainProvider>(context, listen: false);
          // graphGainProvider.setGain(graphGainProvider.gain * 3);
        },
        child: Container(
          decoration: BoxDecoration(
            color: SoftwareColors.kButtonBackGroundColor,
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.add, color: Colors.black, size: 15),
        ),
      ),
    ));

    charts.add(Positioned(
      top: midChartY[idx],
      child: GestureDetector(
        onDoubleTap: () {
          int isRecording = context.read<ChannelColorProvider>().getIsRecording();
          if (isRecording == 0) {
            showWaveform[idx] = !showWaveform[idx];
            context.read<ChannelColorProvider>().setVisibleChannel(idx);
            setState(() {
            });
          } else {
            return;
          }
        },
        onTap: () {
          if (selectedThresholdIdx != idx) {
            Future.delayed(Duration(seconds: 1), (){
              changeActiveThresholdIdx(idx);
            });
          }
          selectedThresholdIdx = idx;
          context.read<ThresholdStatusProvider>().setThresholdChannel(idx);
          // print("selectedThresholdIdx: $selectedThresholdIdx --- ${context.read<ThresholdStatusProvider>().selectedThresholdChannel}");
          setState(() {
          });
        },
        onVerticalDragUpdate: (details) {
          if (selectedThresholdIdx != idx) {
            Future.delayed(Duration(seconds: 1), (){
              changeActiveThresholdIdx(idx);
            });
          }
          selectedThresholdIdx = idx;
          context.read<ThresholdStatusProvider>().setThresholdChannel(idx);
          
          midChartY[idx] = details.globalPosition.dy;
          topChartY[idx] = midChartY[idx] + thresholdIconTopDifference - heightChart / 2;
          
          levelMedian[idx] = midChartY[idx] + thresholdIconTopDifference;
          double currentY = thresholdPositionY[idx];
          double median =
              levelMedian[idx] == -1 ? initialLevelMedian[idx] : levelMedian[idx];
          int tempMedianDistance =
              ((currentY + thresholdIconTopDifference - median).floor()).floor();
          double tempValue = (signalMultiplierChannel[idx] * tempMedianDistance);
          thresholdValue[idx] = (tempValue.floor()).abs();
          // print("Current Y: $currentY, $median, $tempMedianDistance ${thresholdValue[idx]}");
          context.read<ThresholdStatusProvider>().setThresholdParams(thresholdValue);

        },
        child: Container(
          child: Transform.rotate(
            angle: 90 * pi / 180,
            child: Icon(
              showWaveform[idx] ? Icons.water_drop : Icons.water_drop_outlined,
              color: channelColor,
              size: 36,
            ),
          ),
        ),

        // child: Container(
        //   color: Colors.red,
        //   padding: const EdgeInsets.symmetric(vertical: 8.0),
        //   child: Center(
        //     child: SizedBox(
        //       height: 20,
        //       width: 30,
        //       child: CustomPaint(
        //         foregroundPainter: DropletPainter(),
        //       ),
        //     ),
        //   ),
        // ),
      ),
    ));
    final thresholdTriggerType = context.read<ThresholdStatusProvider>().selectedThresholdTriggerType;
    if (isThresholding && thresholdTriggerType == -1) {
      charts.add(Positioned(
        right: 5,
        // top: midChartY[idx],
        top: markerOutOfRange == 1
            ? 50
            : markerOutOfRange == 2
                ? MediaQuery.of(context).size.height * 0.95
                : thresholdMarkerTop[selectedThresholdIdx],        
        child: GestureDetector(
            onVerticalDragUpdate: (dragUpdateVerticalDetails) {
              forceThreshold = 1;
              int c = selectedThresholdIdx;

              double currentY =
                  dragUpdateVerticalDetails.globalPosition.dy - thresholdIconTopDifference;
              thresholdPositionY[c] = currentY;


              print('MOVING Threshold Marker: $currentY ${initialLevelMedian} ${levelMedian}');
              print(levelMedian[c] == -1
                  ? initialLevelMedian[c]
                  : levelMedian[c]);
              // double heightFactor = 32767 / (MediaQuery.of(context).size.height/2);

              // double heightFactor = (gainChannel[c] / signalMultiplier);
              double median =
                  levelMedian[c] == -1 ? initialLevelMedian[c] : levelMedian[c];


              int tempMedianDistance =
                  ((currentY + thresholdIconTopDifference - median).floor()).floor();
              print("tempThresholdValue: $tempMedianDistance - $signalMultiplierChannel[c] ${(currentY + thresholdIconTopDifference - median).floor()} ${levelMedian[c]}");
              if (currentY > 50 &&
                  currentY < MediaQuery.of(context).size.height * 0.95) {
                markerOutOfRange = 0;
              }
              if (markerOutOfRange == 0) {
                if (currentY < 50) {
                  markerOutOfRange = 1;
                } else if (currentY >
                    MediaQuery.of(context).size.height * 0.95) {
                  markerOutOfRange = 2;
                } else {
                  markerOutOfRange = 0;
                  // old calculation
                  // thresholdValue[c] = tempThresholdValue;
                  double scaleRatio = 1;
                  if (!kIsWeb) {
                  } else
                  if (Platform.isAndroid) {
                    // print("MediaQuery.of(context).devicePixelRatio : ${MediaQuery.of(context).devicePixelRatio} || ${MediaQuery.of(context).size.aspectRatio}");
                    scaleRatio = MediaQuery.of(context).devicePixelRatio;
                  }

                  thresholdValue[c] = ((signalMultiplierChannel[c] * tempMedianDistance * scaleRatio).floor()).abs();
                  print("tempThresholdValue: ${thresholdValue[c]} - $signalMultiplierChannel[c] $tempMedianDistance --- scaleRatio : $scaleRatio");

                  // List<int> thresholdParam = context.read<ThresholdStatusProvider>().selectedThresholdParam;
                  // thresholdParam[c] 
                  context.read<ThresholdStatusProvider>().setThresholdParams(thresholdValue);
                  thresholdMarkerTop[c] = currentY;
                }
              }

              double scaleRatio = 1;
              if (isAudio) {
                // scaleRatio = listChannelAudio[listIndexAudio[c].floor()] /
                //     listChannelAudio[defaultListIndexAudio];
              } else {
                // scaleRatio = listChannelSerial[listIndexSerial[c].floor()] /
                //     listChannelSerial[defaultListIndexSerial];
              }
              double curDistance = thresholdMarkerTop[c] + thresholdIconTopDifference - median;
              listMedianDistance[c] = curDistance * scaleRatio;
              print('thresholdMarkerTop[c] - thresholdValue : ${thresholdValue[c]} - ${listMedianDistance[c]} @@@ ${signalMultiplierChannel[c]}');

              setState(() {});
            },
            
            child: Transform.rotate(
              angle: -90 * pi / 180,
              child: Icon(
                showWaveform[idx] ? Icons.water_drop_outlined : Icons.water_drop_outlined,
                color: selectedChannelColor,
                size: 36,
              ),
            ),
          ),

        ),
      );
      // print("thresholdMarkerTop : $thresholdMarkerTop");
      if (markerOutOfRange == 0) {
        charts.add(Positioned(
            top: thresholdMarkerTop[selectedThresholdIdx] + thresholdIconTopDifference,
            right: 20,
            child: Container(
              width: MediaQuery.of(context).size.width,
              child: DottedLine(
                direction: Axis.horizontal,
                lineLength: double.infinity,
                lineThickness: 1.0,
                dashLength: 4.0,
                dashColor: selectedChannelColor,
                dashRadius: 0.0,
                dashGapLength: 4.0,
                dashGapColor: Colors.transparent,
                dashGapRadius: 0.0,
              ),
            )));
      }      
      
    } else 
    if (isThresholding && thresholdTriggerType >= 0 && thresholdTriggerType < 10){
      double width = (MediaQuery.of(context).size.width / 2);
      double height = (MediaQuery.of(context).size.height);
      charts.add(
        Positioned(
        top: height * 0.25,
        left: width,
        child: SizedBox(
          width:1,
          height: height * 0.5,
          child: DottedLine(
            direction: Axis.vertical,
            alignment: WrapAlignment.center,
            lineLength: double.infinity,
            lineThickness: 1.0,
            dashLength: 4.0,
            dashColor: Colors.white,
            dashRadius: 0.0,
            dashGapLength: 4.0,
            dashGapColor: Colors.transparent,
            dashGapRadius: 0.0,
          ),
        ),
      ));
      if (thresholdTriggerType == 0) {
        charts.add(
          Positioned(
            top: height * 0.25 - 30,
            left: width - 20,
            child: SizedBox(
              height:20,
              width:40,
              child: Center(
                child: Text(keyboardCharacter?? "", style: TextStyle(color: Colors.white, backgroundColor: Colors.red),),
              ),
            )
          )
        );
      }

    }
    
    charts.add(Positioned(
      top: midChartY[idx].toDouble() + 35,
      left: leftDroplet,
      child: GestureDetector(
        onTap: () {
          decreaseGain(idx);
        },
        child: Container(
          decoration: BoxDecoration(
            color: SoftwareColors.kButtonBackGroundColor,
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.remove, color: Colors.black, size: 15),
        ),
      ),
    ));
  }

  bool isLoading = true;

  double topDroplet = 0;
  
  int selectedThresholdMarker = 0;
  
  bool isThresholdingButton = false;  
  bool isChoosingThresholdType = false;
  
  // int  signalMultiplier = (150).floor();
  double signalMultiplier = 525 / 75;
  List<double> signalMultiplierChannel = List.generate(50, (index) => 0);
  
  static List<double> thresholdMarkerTop = List.generate(50, (index) => -10000);
  // static List<double> thresholdMarkerTop = [
  //   -10000,
  //   -10000,
  //   -10000,
  //   -10000,
  //   -10000,
  //   -10000
  // ];
  List<double> snapshotAveragedSamples = [1];
  List<double> thresholdPositionY = List.generate(50, (index) => 0);
  List<int> thresholdValue = List.generate(50, (index) => index == 0 ? 10 : 25);
  List<double> listMedianDistance = List.generate(50, (index) => 0);
  
  int thresholdType = -1;
  int selectedThresholdIdx = 0;
  int forceThreshold = 1;
  int markerOutOfRange = 0;
  int excessiveTopGain = 0;
  int excessiveBottomGain = 0;


  List<double> levelMedian = List.generate(50, (index) => -1);
  List<double> initialLevelMedian = List.generate(50, (index) => 0);
  
  bool isInitializedGraph = false;
  
  int thresholdIconTopDifference = 18;
  
  double initialThresholdScale = 0.25;

  bool _isNumeric(String s) {
    // A simple regular expression to validate if the string is a single digit.
    return s.isNotEmpty && s.length == 1 && RegExp(r'^[0-9]$').hasMatch(s);
  }

  String? keyboardCharacter;
  
  bool isThresholding = false;
  void _handleKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent) {
      // debouncerKeyboard.run(() {
        final String? character = event.character;

        // Check if the character is a digit (0-9)
        if (character != null && _isNumeric(character)) {
          keyboardCharacter = character;
          print("CHARACTER : $character");
          ProcessingUtil.eventMarkerNotifier.value = [int.parse(character), -1];
          // ProcessingUtil.eventMarkerNotifier.value = [-1, -1];
        } else if (event.logicalKey == LogicalKeyboardKey.backspace) {
          // Handle backspace key: remove the last character from the text field.
        }
      // });
    }
  }

  @override
  Widget build(BuildContext context) {
    // return LayoutBuilder(builder: (context, constraints) {
    //   return Consumer<GraphGainProvider>(
    //       builder: (context, graphGainProvider, _) {
    final colorProvider = context.watch<ChannelColorProvider>();
    final dataStatus = context.watch<DataStatusProvider>();
    
    // final thresholdStatus = context.watch<ThresholdStatusProvider>();
    if (isThresholding != context.read<ThresholdStatusProvider>().isThresholding) {
      thresholdMenuListener();
    } 
    isThresholding = context.read<ThresholdStatusProvider>().isThresholding;

    // if (isInitializedGraph && thresholdMarkerTop[selectedThresholdIdx] == -10000) {
    //   initLevelMedian(1, 0);
    // }      

    bool isAudio = dataStatus.isMicrophoneData;
    List<Widget> charts = [];
    // List<Widget> thresholdControls = [];
    if (!isLoading) {
      // if (ProcessingUtil.drawingBuffers.isNotEmpty &&
      //     channelCount != ProcessingUtil.drawingBuffers.length) {
      //   channelCount = ProcessingUtil.drawingBuffers.length;
      //   initializeGraph();
      // }
      // print("SHOW WAVEFORM: ${showWaveform.length} --- ${ProcessingUtil.drawingBuffers[0].length}");

      // Ensure waveform visibility list matches the current channel count
      if (showWaveform.length != ProcessingUtil.drawingBuffers.length) {
        if (showWaveform.length < ProcessingUtil.drawingBuffers.length) {
          showWaveform.addAll(List<bool>.filled(
              ProcessingUtil.drawingBuffers.length - showWaveform.length,
              true));
        } else {
          showWaveform =
              showWaveform.sublist(0, ProcessingUtil.drawingBuffers.length);
        }
      }

      // if (GraphTemplate.isPlayerPaused) {
      //   return Container();
      // }

      // List<double>? streamDouble = ProcessingUtil.drawingBuffers[0].toList();
      // eventMarkersNumber = snapshot.data;
      // eventMarkersPosition = snapshot.data!;
// /*
      List<Int16List> temp = [];
      List<int> sampleCounts = [];
      int idx = 0;
      // channelCount = context.read<ConstantProvider>().getChannelCount();      
      // int tempChannelCount = context.read<ConstantProvider>().getChannelCount();      
      try{
        for (idx = 0; idx < channelCount; idx++) {
          Int16List curBuffer =
              Int16List.fromList(ProcessingUtil.drawingBuffers[idx]);
          temp.add(curBuffer);
          sampleCounts.add(ProcessingUtil.drawingBufferCounts[idx]);
          // sampleCounts.add(curBuffer.length);
        }
      }catch(err){
        return SizedBox();
      }


      for (idx = 0; idx < channelCount; idx++) {
        Int16List curBuffer = temp[idx];
        Color channelColor = isAudio
            ? (idx < colorProvider.audioColors.length
                ? colorProvider.audioColors[idx]
                : SoftwareColors.kGraphColor)
            : (idx < colorProvider.serialColors.length
                ? colorProvider.serialColors[idx]
                : SoftwareColors.kGraphColor);
        // int outSampleCount = ProcessingUtil.drawingBufferCounts[idx];
        // int outSampleCount = ProcessingUtil.drawingBufferCounts[idx];
        int outSampleCount = sampleCounts[idx];
        // print("sampleCount $outSampleCount vs ${curBuffer.length}");
        // print(sampleCount);
        // print(curBuffer);

        var buffer;
        if (kIsWeb) {
          // buffer = Int16List(outSampleCount);
          // buffer = Int16List.sublistView(curBuffer, 0, outSampleCount).toList();
          // buffer = List<int>.generate(outSampleCount, (idx) => curBuffer[idx]);
          // subArray(curBuffer, buffer, 0, outSampleCount);
          // buffer.fillRange(0, 100, 300);
          // if (outSampleCount > curBuffer.length) {
          //   continue;
          // }
          // print("$idx OUT SAMPLE COUNT VS CURBUFFER: ${curBuffer.length} - ${outSampleCount}");
          int minSampleCount = min(outSampleCount, curBuffer.length);
          minSampleCount = minSampleCount > 0 ? minSampleCount : 0;
          buffer =
              (curBuffer).sublist(0, minSampleCount);
        } else {
          // 410
          // print("$idx OUT SAMPLE COUNT VS CURBUFFER: ${curBuffer.length} - ${outSampleCount}");
          buffer = (curBuffer).sublist(0, outSampleCount);
          // print("buffer ${buffer.toList().sublist(0, 10)}");
        }

        // print("buffer $outSampleCount vs ${buffer.length} $channelCount");
        if (showWaveform[idx]) {
          widthChart = MediaQuery.of(context).size.width;
          heightChart = MediaQuery.of(context).size.height / channelCount;

          charts.add(
            Positioned(
              top: topChartY[idx].toDouble(),
              left: 0,
              child: Container(
                // color: idx ==0? Colors.red : Colors.blue,
                width: MediaQuery.of(context).size.width,
                height: MediaQuery.of(context).size.height,
                child: WavForm.PolygonWaveform(
                  showActiveWaveform: true,
                  inactiveColor: channelColor,
                  activeColor: Colors.transparent,
                  maxDuration: const Duration(days: 1),
                  elapsedDuration: const Duration(hours: 0),
                  // samples: buffer.toList(),
                  samples: buffer.toList(),
                  height: heightChart,
                  width: widthChart,
                  channelIdx: idx,
                  channelActive: 0,
                  gain: gainChannel[idx],
                  levelMedian: heightChart / 2,
                  strokeWidth: 1,
                  eventMarkersNumber:
                      (DraggableGraph.eventMarkersLabels),
                  eventMarkersPosition: DraggableGraph
                          .eventMarkersPosition.isEmpty || isThresholding
                      ? []
                      : (DraggableGraph.eventMarkersPosition),
                  // eventMarkersNumber: List.generate(100, (idx) => (idx + 1) % 7),
                  // eventMarkersPosition: List.generate(100, (idx) => idx * 4),
                ),
              ),
            ),
          );
        }
      }
      charts.add(Positioned(
        top: 0,
        left: 0,
        child: Container(
          color: Colors.black,
          width: 34,
          height: MediaQuery.of(context).size.height,
        ),
      ));
      
      // print("CHANNEL COUNT: $channelCount ${DateTime.now().microsecondsSinceEpoch}");
      for (idx = 0; idx < channelCount; idx++) {
        addChartControls(charts, idx, channelCount, context);
      }
      // addThresholdControls(thresholdControls);

      // charts.addAll(thresholdControls);
// */
// */
      return KeyboardListener(
          onKeyEvent: _handleKeyEvent,
          focusNode: keyboardFocusNode,
          child: Stack(
            children: charts.isEmpty ? [Container()] : charts,
            // children: [
            //   Positioned(
            //     top: topDroplet,
            //     left: 100,
            //     child: GestureDetector(
            //       onVerticalDragUpdate: (details){
            //         topDroplet = details.globalPosition.dy;
            //         print("topDroplet");
            //         print(topDroplet);
            //       },
            //       child: Icon(Icons.water_drop, color: Colors.green, size:50)
            //     ),
            //   ),

            // ],
          ));
    } else {
      // Handle loading state here
      return const Center(
          child: SizedBox(
              height: 50,
              width: 50,
              child: CircularProgressIndicator(color: Colors.green)));
    }
    // return StreamBuilder<List<double>>(
    //   stream: dataStream,
    //   builder: (context, snapshot) {

    //   },
    // );
    //   });
    // });
  }

  void subArray(
      Int16List curBuffer, Int16List buffer, int start, int sampleCount) {
    int len = sampleCount;
    // Int16List buffer = Int16List(sampleCount);
    // print("subArray ${buffer.length} ${curBuffer.length} ${curBuffer.sublist(0,100)}");
    int arrayIdx = 0;
    for (arrayIdx = 0; arrayIdx < len; arrayIdx++) {
      buffer[arrayIdx] = curBuffer[arrayIdx];
      // print(arrayIdx);
    }
    // return buffer;
  }


  setThresholdMarker(int c, List<double> thresholdMarkerTop, List<int> thresholdValue, double prevVal, double curVal) {
    List<int> thresholdParams = [thresholdValue[c]];

    double heightFactor = curVal / (prevVal);
    double heightScale = 1 / heightFactor;

    double median = levelMedian[c] == -1 ? initialLevelMedian[c] : levelMedian[c];
    print("MEDIAN: $median" );

    double medianDistance = listMedianDistance[c];
    
    double tempMarkerTop = median + medianDistance * heightFactor - thresholdIconTopDifference;
    thresholdMarkerTop[c] = tempMarkerTop;
    print("TEMP MARKER TOP : $tempMarkerTop $median + $medianDistance * $heightFactor ($prevVal / ${gainChannel[c]}) --- ($signalMultiplier * ${gainChannel[c]}) - $thresholdIconTopDifference");
    
    signalMultiplierChannel[c] = signalMultiplierChannel[c] * heightScale;
    listMedianDistance[c] = thresholdMarkerTop[c] + thresholdIconTopDifference - median;
    thresholdValue[c] = ((signalMultiplierChannel[c] * listMedianDistance[c]).floor()).abs();
    print("thresholdValue[c]: ${thresholdValue[c]} === ${signalMultiplierChannel[c]} ${listMedianDistance[c]} * $heightScale}");
    
    // print("TEMP MARKER TOP: $tempMarkerTop = $median + $listMedianDistance ( $signalMultiplier * ${gainChannel[c]})");
    // thresholdMarkerTop[c] = calculatedMedian - halfMaxIntValue - thresholdIconTopDifference;
    // thresholdValue[c] = ((thresholdMarkerTop[c] +
    //                 thresholdIconTopDifference -
    //                 calculatedMedian)
    //             .floor() *
    //         heightFactor)
    //     .floor();
    // // print("halfMaxIntValue: ${thresholdMarkerTop[c]} $calculatedMedian $halfMaxIntValue - $thresholdIconTopDifference ---- ${thresholdValue[c]}");
    // // print("Threshold Value : ${thresholdValue[c]} = ${thresholdMarkerTop[c] + thresholdIconTopDifference - calculatedMedian }");
    // // -75 position = 1000 threshold == gain 0.125
    // // 1000 = -75 * a * 0.125 = > a = 8000 /-75 => a=106
    // listMedianDistance[c] = thresholdMarkerTop[c] + thresholdIconTopDifference - calculatedMedian;
    // // print("thresholdValue: $thresholdValue");
    // // print("Threshold Value : ${thresholdValue[c]} = ${thresholdMarkerTop[c] + thresholdIconTopDifference - calculatedMedian }");    
    // context.read<ThresholdStatusProvider>().setThresholdParams(thresholdParams);
  }
  // setThresholdMarker(int c, List<double> thresholdMarkerTop,
  //   List<int> thresholdValue, double prevVal, double curVal) {

  //   double scaleRatio = 1;
  //   bool isAudioListen = context.read<DataStatusProvider>().isMicrophoneData;
  //   if (isAudioListen) {
  //     scaleRatio = gainChannel[c];
  //   } else {
  //     scaleRatio = gainChannel[c];
  //   }
  //   // if (isAudioListen) {
  //   //   scaleRatio = listChannelAudio[listDefaultIndex[c]] / curVal;
  //   // } else {
  //   //   scaleRatio = listChannelSerial[listDefaultIndex[c]] / curVal;
  //   // }

  //   double tempMarkerTop = thresholdMarkerTop[c];
  //   final double prevScaleRatio = scaleRatio;
  //   final double prevTempMarkerTop = tempMarkerTop;

  //   double median = levelMedian[c] == -1 ? initialLevelMedian[c] : levelMedian[c];
  //   double medianDistance = listMedianDistance[c];

  //   print('medianDistance');
  //   print(medianDistance);
  //   int iconMarkerTop = 18;


  //   if (scaleRatio == 1)
  //     // return;
  //     tempMarkerTop = median + medianDistance * scaleRatio - iconMarkerTop;
  //   else if (scaleRatio < 1) {
  //     if (excessiveTopGain - 1 > 0) {
  //       excessiveTopGain--;
  //       return;
  //     } else {
  //       excessiveTopGain = 0;
  //     }

  //     print(tempMarkerTop);
  //     scaleRatio = scaleRatio;
  //     // tempMarkerTop = tempMarkerTop + thresholdMarkerTop[0] * scaleRatio;
  //     tempMarkerTop = median + medianDistance * scaleRatio - iconMarkerTop;
  //     print(tempMarkerTop);
  //     print("-----------");
  //     // scaleRatio = scaleRatio * -1;
  //   } else {
  //     //UP or +
  //     if (excessiveBottomGain - 1 > 0) {
  //       excessiveBottomGain--;
  //       print('excessiveBottomGain return');
  //       print(excessiveBottomGain);

  //       return;
  //     } else {
  //       excessiveBottomGain = 0;
  //     }

  //     // print("decreasing? " +
  //     //     prevVal.toString() +
  //     //     " _ " +
  //     //     curVal.toString() +
  //     //     " : " +
  //     //     scaleRatio.toString());
  //     // print(tempMarkerTop);
  //     // print(median);
  //     // print(medianDistance);
  //     // scaleRatio = 1 - scaleRatio;
  //     // tempMarkerTop = tempMarkerTop + thresholdMarkerTop[0] * scaleRatio;
  //     tempMarkerTop = median + medianDistance * scaleRatio - iconMarkerTop;

  //     // print(tempMarkerTop);
  //     // print("-----------");
  //   }

  //   if (tempMarkerTop < 50) {
  //     excessiveTopGain++;
  //     markerOutOfRange = 1;
  //     thresholdMarkerTop[c] = tempMarkerTop;
  //   } else if (tempMarkerTop > MediaQuery.of(context).size.height * 0.95) {
  //     excessiveBottomGain++;

  //     markerOutOfRange = 2;
  //     thresholdMarkerTop[c] = tempMarkerTop;
  //     // listIndexAudio[c] = listChannelAudio.indexOf(prevVal).toDouble();
  //     // channelGains[c] = prevVal;
  //   } else {
  //     excessiveTopGain = 0;
  //     excessiveBottomGain = 0;
  //     markerOutOfRange = 0;
  //     thresholdMarkerTop[c] = tempMarkerTop;
  //   }
  //   double heightFactor = (gainChannel[c] / signalMultiplier);
  // }  

  void initLevelMedian(int channelsLength, int selectedIdx) {
    print("Channels Length: $channelsLength");
    for (int c = 0; c < channelsLength; c++) {
      signalMultiplierChannel[c] = signalMultiplier;
      double heightScale = (signalMultiplier * gainChannel[c] / initialThresholdScale );
      double calculatedMedian =
          (c * MediaQuery.of(context).size.height / channelsLength) +
              MediaQuery.of(context).size.height / channelsLength / 2;

      // final halfMaxIntValue =
      //     MediaQuery.of(context).size.height / channelsLength / 8;
      final halfMaxIntValue =
          MediaQuery.of(context).size.height / channelsLength / 8;

      thresholdMarkerTop[c] = calculatedMedian - halfMaxIntValue - thresholdIconTopDifference;
      thresholdPositionY[c] = thresholdMarkerTop[c];

      thresholdValue[c] = ((thresholdMarkerTop[c] +
                      thresholdIconTopDifference -
                      calculatedMedian)
                  .floor() *
              heightScale)
          .floor();
      print("halfMaxIntValue: [$c] ${thresholdMarkerTop[c]} $calculatedMedian $halfMaxIntValue - $thresholdIconTopDifference ---- ${thresholdValue[c]}");
      print("Threshold Value : [$c] ${thresholdValue[c]} = ${thresholdMarkerTop[c] + thresholdIconTopDifference - calculatedMedian }");
      // -75 position = 1000 threshold == gain 0.125
      // 1000 = -75 * a * 0.125 = > a = 8000 /-75 => a=106
      initialLevelMedian[c] = calculatedMedian;
      listMedianDistance[c] = thresholdMarkerTop[c] + thresholdIconTopDifference - calculatedMedian;
    }
    print("MEDIAN: $initialLevelMedian | $listMedianDistance" );

  }

  void thresholdMenuListener() {
    print("thresholdMenuListener");
    keyboardFocusNode.requestFocus();
    // initializeDeviceListener();
  }
  
  void changeActiveThresholdIdx(int idx) {
    // initLevelMedian(channelCount, idx);
  }

  void initializeDeviceListener() {
    isInitializedGraph = false;
    print("Initial Device Listener");
    if (ProcessingUtil.initializeDevice.value == 0 ) {
      defaultGain = 0.25 * 0.25;
      initializeGraph();
      initLevelMedian(1, 0);

    } else {
      Future.delayed(Duration(seconds: 1), (){
        print("DECREASE GAINNNNN");
        print("initializeDeviceListener channelCount: $channelCount");
        defaultGain = (0.25 * 0.25) / 27;
        initializeGraph();
        initLevelMedian(channelCount, 0);
        // for (int i = 0; i < channelCount; i++) {
        //   decreaseGain(i, isInitial:true);
        //   decreaseGain(i, isInitial:true);
        //   decreaseGain(i, isInitial:true);
        // }
        setState(() {});
      });
    }
  }
  

  void decreaseGain(int idx, {bool isInitial = false}) {
    double prevVal = gainChannel[idx];
    // gainChannel[idx] /= 3;
    if (ProcessingUtil.initializeDevice.value == 0) {
      gainChannel[idx] = gainChannel[idx] * pow(1.1, -1);
    } else {
      gainChannel[idx] = gainChannel[idx] * pow(1.25, -1);
    }
    setThresholdMarker(idx, thresholdMarkerTop, thresholdValue, prevVal, gainChannel[idx]);
    GraphGainProvider graphGainProvider =
        Provider.of<GraphGainProvider>(context, listen: false);
    if (!isInitial) {
      graphGainProvider.decreaseGainChannel(idx);
    }

  }
  
  void increaseGain(int idx) {
    double prevVal = gainChannel[idx];
    // gainChannel[idx] *= 3;
    if (ProcessingUtil.initializeDevice.value == 0) {
      gainChannel[idx] = gainChannel[idx] * pow(1.1, 1);
    } else {
      gainChannel[idx] = gainChannel[idx] * pow(1.25, 1);
    }
    selectedThresholdMarker = idx;
    setThresholdMarker(idx, thresholdMarkerTop, thresholdValue, prevVal, gainChannel[idx]);

    GraphGainProvider graphGainProvider =
        Provider.of<GraphGainProvider>(context, listen: false);
    graphGainProvider.increaseGainChannel(idx);
  }
}

class DraggableButton extends StatefulWidget {
  const DraggableButton({super.key});

  @override
  State<DraggableButton> createState() => _DraggableButtonState();
}

class _DraggableButtonState extends State<DraggableButton> {
  double offset = 0;
  static const double _padding = 50;

  @override
  Widget build(BuildContext context) {
    VerticalDragProvider verticalDragProvider =
        Provider.of<VerticalDragProvider>(context, listen: false);
    double initialOffset = verticalDragProvider.initialOffset;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () {},
      onVerticalDragUpdate: (DragUpdateDetails dragUpdateVerticalDetails) {
        offset += dragUpdateVerticalDetails.primaryDelta!;
        final finalOffset =
            offset.clamp(-initialOffset + _padding, initialOffset - _padding);
        final topPosition = finalOffset;
        verticalDragProvider.setDragPosition(topPosition);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [],
        ),
      ),
    );
  }
}

class DraggableRectangle extends StatefulWidget {
  const DraggableRectangle({super.key});

  @override
  State<DraggableRectangle> createState() => _DraggableRectangleState();
}

class _DraggableRectangleState extends State<DraggableRectangle> {
  Offset position = const Offset(0, 0);
  double _buttonWidth = 50;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      return Consumer<GraphResumePlayProvider>(
          builder: (context, isGraphStatus, snapshot) {
        if (isGraphStatus.graphStatus) {
          return Container();
        }
        {
          return Align(
              alignment: const Alignment(0, 0.75),
              child: DecoratedBox(
                  decoration: const BoxDecoration(
                      color: Color.fromARGB(255, 83, 80, 80)),
                  child: SizedBox(
                    height: 20,
                    width: double.infinity,
                    child: Stack(
                      children: [
                        Consumer<GraphDataProvider>(
                            builder: (context, graphDataProvider, _) {
                          _buttonWidth = graphDataProvider.getViewPortWidth() *
                              constraints.maxWidth;
                          // graphDataProvider.setBarGraphButtonWidth(_buttonWidth);

                          return Positioned(
                            right: position.dy,
                            child: GestureDetector(
                              onPanUpdate: (DragUpdateDetails details) {
                                setState(() {
                                  double y = position.dy - details.delta.dx;
                                  // print("y: $y, position.dy : ${position.dy}, details.dy: ${details.delta.dx}");
                                  y = y.clamp(
                                      0, constraints.maxWidth - _buttonWidth);

                                  position = Offset(0, y);
                                  // print("Offset: ${position}");
                                });
                              },
                              onPanEnd: (DragEndDetails dragEndDetails) {
                                double rightRatio =
                                    position.dy / constraints.maxWidth;
                                double leftRatio = (constraints.maxWidth -
                                        position.dy -
                                        _buttonWidth) /
                                    constraints.maxWidth;
                                // print("the left ratio $leftRatio and right $rightRatio");

                                // print("leftRatio : $leftRatio, rightRatio: $rightRatio");
                                graphDataProvider.setPanLevel(
                                    leftRatio, rightRatio);
                              },
                              child: Container(
                                height: 20,
                                width:
                                    _buttonWidth, // Adj  ust the width as per your requirement
                                color: Colors.grey,
                              ),
                            ),
                          );
                        }),
                      ],
                    ),
                  )));
        }
      });
    });
  }
}


class FftSection extends StatefulWidget {
  const FftSection({super.key});

  @override
  State<FftSection> createState() => _FftSectionState();
}
class _FftSectionState extends State<FftSection> {
  @override
  void initState() {
    super.initState();
    Stream<List<double>> dataStream =
        Provider.of<GraphDataProvider>(context, listen: false)
                .outputGraphStream ??
            const Stream.empty();
    dataStream.listen((data) {
      setState(() {});
    });
  }
  
  @override
  Widget build(BuildContext context) {
    bool isFftShowing = context.read<FftStatusProvider>().isFftShowing;
    // print("ProcessingUtil.fftDrawData == null :   ${MediaQuery.of(context).size.width}");
    // print("ProcessingUtil.fftDrawData == null :   ${ProcessingUtil.fftDrawData == null}");
    return Positioned(
      left:0,
      bottom: 150,
      child: 
        // ProcessingUtil.fftDrawData == null?
        !isFftShowing || ProcessingUtil.fftDrawData == null?
        Container()
        :
        Container(
          width: MediaQuery.of(context).size.width,
          height: MediaQuery.of(context).size.height * 0.2,
          // color: Colors.red,
          child: CustomPaint(
            painter: FftPainter(fftData: ProcessingUtil.fftDrawData!)
          ),
        )
    );
  }

}
