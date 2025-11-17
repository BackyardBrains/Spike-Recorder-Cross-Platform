import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:spikerbox_architecture/provider/graph_stream_data.dart';
import 'package:spikerbox_architecture/provider/isgraphplay_provider.dart';
import 'package:spikerbox_architecture/screen/graph_template.dart';
import 'package:spikerbox_architecture/screen/spiker_box_ui.dart';
import 'package:spikerbox_architecture/widget/spiker_box_button.dart';

class SoundWaveView extends StatefulWidget {
  static PointerScrollEvent? dragDetails;
  static int direction = 0;
  static double previousScale = 1.0;

  const SoundWaveView({
    super.key,
  });

  @override
  State<SoundWaveView> createState() => _SoundWaveViewState();
}

class _SoundWaveViewState extends State<SoundWaveView> {
  @override
  Widget build(BuildContext context) {
    if (Platform.isAndroid || Platform.isIOS) { 
      return GestureDetector(
        onScaleEnd: (ScaleEndDetails details) {
        },
        onScaleUpdate: (ScaleUpdateDetails details) {
          // print("scale: ${details}");
          SoundWaveView.dragDetails = PointerScrollEvent(
            // position: Offset.zero,
            // scrollDelta: Offset.zero,
            // scrollDelta: Offset(details.horizontalScale, details.verticalScale),
            position: details.focalPoint,
            scrollDelta: details.focalPointDelta,
            timeStamp: details.sourceTimeStamp ?? Duration.zero,
            kind: PointerDeviceKind.touch,
          );
      

          if ((details.scale > 1.2 || details.scale < 0.8) && (SoundWaveView.previousScale - details.scale).abs() > 0.2) {
            SoundWaveView.previousScale = details.scale;
            Provider.of<GraphDataProvider>(context, listen: false)
                .notifyZoomEvent(SoundWaveView.previousScale > 1 ? -4 : 4); // Convert scale to scroll-like values
          }

          // Use the same zoom event system for scale gestures
        },
        child: const SpikerBoxUi(),
      );
    } else {

      return Listener(
        onPointerSignal: (PointerSignalEvent event) {
          if (event is PointerScrollEvent) {
            SoundWaveView.dragDetails = event;

            Provider.of<GraphDataProvider>(context, listen: false)
                .notifyZoomEvent(event.scrollDelta.dy);

            print("scrollDelta: ${event.scrollDelta}");
          }
        },
        child: GestureDetector(
          onScaleUpdate: (ScaleUpdateDetails details) {
            print("scale: ${details.scale}");

            double scale = details.scale;
            // Use the same zoom event system for scale gestures
            if (scale != 1) {
              Provider.of<GraphDataProvider>(context, listen: false)
                  .notifyZoomEvent(scale > 1 ? -10 : 10); // Convert scale to scroll-like values
            }
          },
          child: const SpikerBoxUi(),
        ),
      );
    }
  }
}

class BottomButtons extends StatefulWidget {
  const BottomButtons({
    super.key,
    required this.pauseButton,
  });

  final Function(bool isPlay) pauseButton;

  @override
  State<BottomButtons> createState() => _BottomButtonsState();
}

class _BottomButtonsState extends State<BottomButtons> {
  @override
  Widget build(BuildContext context) {
    bool isGraphStatus = context.read<GraphResumePlayProvider>().graphStatus;
    // print("IS GRAPH STATUS: $isGraphStatus");

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        isGraphStatus? SizedBox():
        SpikerBoxButton(
          padding: const EdgeInsets.all(5),
          iconSize: 20,
          iconData: Icons.refresh,
          onTapButton: () {
            context.read<GraphDataProvider>().resetGraphBuffer();
          },
        ),
        const SizedBox(
          width: 15,
        ),
        SpikerBoxButton(
          padding: const EdgeInsets.all(10),
          iconSize: 40,
          iconData: isGraphStatus ? Icons.pause : Icons.play_arrow,
          onTapButton: () {
            GraphTemplate.isPlayerPaused = !GraphTemplate.isPlayerPaused;
            isGraphStatus = !isGraphStatus;
            widget.pauseButton(isGraphStatus);
            setState(() {});
          },
        ),
        const SizedBox(
          width: 15,
        ),
        isGraphStatus? SizedBox():
        SpikerBoxButton(
          padding: const EdgeInsets.all(5),
          iconSize: 20,
          iconData: Icons.keyboard_tab,
          onTapButton: () {
            context.read<GraphDataProvider>().forwardGraphBuffer();
          },
        ),
      ],
    );
  }
}
