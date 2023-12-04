import 'dart:math';
import 'package:flutter_audio_waveforms/flutter_audio_waveforms.dart'
    as WavForm;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:spikerbox_architecture/provider/graph_gain_provider.dart';
import 'package:spikerbox_architecture/provider/graph_stream_data.dart';
import 'package:spikerbox_architecture/provider/isgraphplay_provider.dart';
import 'package:spikerbox_architecture/provider/vertical_dragprovider.dart';

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

  @override
  Widget build(BuildContext context) {
    return const Stack(
      children: [
        DraggableSection(),

        TimeCalculateWidget(),

        DraggableRectangle(),

        //   } else {
        //     return Container();
        //   }
        // }),
        // Container()
      ],
    );
  }
}

class TimeCalculateWidget extends StatefulWidget {
  const TimeCalculateWidget({
    super.key,
  });

  @override
  State<TimeCalculateWidget> createState() => _TimeCalculateWidgetState();
}

class _TimeCalculateWidgetState extends State<TimeCalculateWidget> {
  @override
  Widget build(BuildContext context) {
    return Consumer<GraphDataProvider>(builder: (context, timerCalculate, _) {
      return Align(
        alignment: const Alignment(1, 0.7),
        child: SizedBox(
          height: 40,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                height: 5,
                width: 300,
                color: Colors.white,
              ),
              Text(
                timerCalculate.sampleOnGraph.toString(),
                style: SoftwareTextStyle().kWtMediumTextStyle,
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
    return LayoutBuilder(builder: (context, constraints) {
      Provider.of<VerticalDragProvider>(context, listen: false).initialOffset =
          constraints.maxHeight / 2;
      return Consumer<VerticalDragProvider>(
        builder: (context, verticalDrag, snapshot) {
          return Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              Positioned(
                top: verticalDrag.topPosition,
                left: 0,
                child: SizedBox(
                  width: constraints.maxWidth,
                  height: constraints.maxHeight,
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(child: DraggableButton()),
                      Expanded(
                        child: DraggableGraph(),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      );
    });
  }
}

class DraggableGraph extends StatefulWidget {
  const DraggableGraph({super.key});

  @override
  State<DraggableGraph> createState() => _DraggableGraphState();
}

class _DraggableGraphState extends State<DraggableGraph> {
  @override
  Widget build(BuildContext context) {
    Stream<List<double>> dataStream =
        Provider.of<GraphDataProvider>(context, listen: false)
                .outputGraphStream ??
            const Stream.empty();
    return LayoutBuilder(builder: (context, constraints) {
      return Consumer<GraphGainProvider>(
          builder: (context, graphGainProvider, _) {
        return StreamBuilder<List<double>>(
          stream: dataStream,
          builder: (context, snapshot) {
            if (snapshot.hasData) {
              List<double>? streamDouble = snapshot.data;
              // eventMarkersNumber = snapshot.data;
              // eventMarkersPosition = snapshot.data!;
              return WavForm.PolygonWaveform(
                showActiveWaveform: true,
                inactiveColor: SoftwareColors.kGraphColor,
                activeColor: Colors.transparent,
                maxDuration: const Duration(days: 1),
                elapsedDuration: const Duration(hours: 0),
                samples: streamDouble!,
                height: constraints.maxHeight,
                width: constraints.maxWidth,
                channelIdx: 1,
                channelActive: -1,
                // channelTop: top,
                gain: graphGainProvider.gain,
                levelMedian: constraints.maxHeight / 2,
                strokeWidth: 1.25,
                eventMarkersNumber: 1,
                // eventMarkersPosition: eventMarkersPosition,
              );
            } else if (snapshot.hasError) {
              // Handle error state here
              return Text('Error: ${snapshot.error}');
            } else {
              // Handle loading state here
              return const Center(
                  child: SizedBox(
                      height: 50,
                      width: 50,
                      child: CircularProgressIndicator(color: Colors.green)));
            }
          },
        );
      });
    });
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
          children: [
            GestureDetector(
              onTap: () {
                GraphGainProvider graphGainProvider =
                    Provider.of<GraphGainProvider>(context, listen: false);
                graphGainProvider.setGain(graphGainProvider.gain * 3);
              },
              child: Container(
                decoration: BoxDecoration(
                  color: SoftwareColors.kButtonBackGroundColor,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.add, color: Colors.black, size: 15),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: Center(
                child: SizedBox(
                  height: 20,
                  width: 30,
                  child: CustomPaint(
                    foregroundPainter: DropletPainter(),
                  ),
                ),
              ),
            ),
            GestureDetector(
              onTap: () {
                GraphGainProvider graphGainProvider =
                    Provider.of<GraphGainProvider>(context, listen: false);
                graphGainProvider.setGain(graphGainProvider.gain * 0.25);
              },
              child: Container(
                decoration: BoxDecoration(
                  color: SoftwareColors.kButtonBackGroundColor,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.remove, color: Colors.black, size: 15),
              ),
            ),
          ],
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
                      alignment: AlignmentDirectional.centerStart,
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
