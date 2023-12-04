import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

class DragGraphHorizontally extends StatefulWidget {
  const DragGraphHorizontally({super.key, required this.sliderWidget});

  final Widget sliderWidget;
  @override
  State<DragGraphHorizontally> createState() => _DragGraphHorizontallyState();
}

class _DragGraphHorizontallyState extends State<DragGraphHorizontally> {
  late DragDownDetails dragDownDetails;
  late DragUpdateDetails dragDetails;
  late DragUpdateDetails dragHorizontalDetails;
  num curTimeScaleBar = 1000;
  int horizontalDiff = 0;
  double prevY = 0.0;
  double scaleBarWidth = 2.0;
  num timeScale = 10000;
  ScaleUpdateDetails scaleDetails = ScaleUpdateDetails();
  int timeScaleBar = 80;
  List<double> arrTimeScale = [0.1, 1, 10, 50, 100, 500, 1000, 5000, 10000];

  bool isZooming = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragUpdate: (DragUpdateDetails details) {
          dragHorizontalDetails = details;
        },
        onHorizontalDragDown: (DragDownDetails details) {
          dragDownDetails = details;
        },
        onHorizontalDragEnd: (DragEndDetails dragEndDetails) {},
        child: Listener(
          onPointerSignal: (PointerSignalEvent dragDetails) {
            if (dragDetails is PointerScrollEvent) {
              int direction = 0;

              if (dragDetails.kind != PointerDeviceKind.mouse) {
                return;
              }

              if (dragDetails.scrollDelta.dx == 0.0 &&
                  dragDetails.scrollDelta.dy == 0.0) {
                return;
              } else if (dragDetails.scrollDelta.dy < 0 &&
                  dragDetails.scrollDelta.dy > -500) {
                prevY = dragDetails.scrollDelta.dy;
                //down
                direction = -1;

                if (timeScaleBar - 1 < 10) {
                } else {
                  timeScaleBar--;
                }
              } else if (dragDetails.scrollDelta.dy > 0 &&
                  dragDetails.scrollDelta.dy < 500) {
                direction = 1;
                prevY = dragDetails.scrollDelta.dy;

                if (timeScaleBar + 1 > 80) {
                } else {
                  timeScaleBar++;
                }
              }
              int transformScale = (timeScaleBar / 10).floor();

              curTimeScaleBar = (arrTimeScale[transformScale] / 10);

              var data = {
                "timeScaleBar": arrTimeScale[transformScale], // label in UI
                "levelScale": timeScaleBar, //scrollIdx
                "posX": dragDetails.localPosition.dx,
                "direction": direction
              };

              if (timeScaleBar == -1) {
                timeScale = 1;
              } else {
                timeScale = arrTimeScale[transformScale];
              }

              if (timeScale == 10000) {
                horizontalDiff = 0;
                isZooming = false;
              } else {
                if (horizontalDiff > 0) {
                  isZooming = true;
                } else {
                  isZooming = false;
                }
              }
            }
          },
          child: widget.sliderWidget,
        ));
  }
}
