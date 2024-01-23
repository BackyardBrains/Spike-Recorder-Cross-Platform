import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:spikerbox_architecture/provider/graph_stream_data.dart';
import 'package:spikerbox_architecture/provider/isgraphplay_provider.dart';
import 'package:spikerbox_architecture/provider/provider_export.dart';
import 'package:spikerbox_architecture/screen/spiker_box_ui.dart';
import 'package:spikerbox_architecture/widget/spiker_box_button.dart';

class SoundWaveView extends StatefulWidget {
  const SoundWaveView({
    super.key,
  });

  @override
  State<SoundWaveView> createState() => _SoundWaveViewState();
}

class _SoundWaveViewState extends State<SoundWaveView> {
  @override
  Widget build(BuildContext context) {
    SampleRateProvider sampleRate = context.read<SampleRateProvider>();

    EnvelopConfig envelopConfig = context.read<EnvelopConfig>();
    print("sample rate is $sampleRate");
    return Listener(
      onPointerSignal: (PointerSignalEvent event) {
        if (event is PointerScrollEvent) {
          Provider.of<GraphDataProvider>(context, listen: false)
              .setScrollIndex(event.scrollDelta.dy, sampleRate, envelopConfig);
        }
      },
      child: GestureDetector(
        onScaleUpdate: (ScaleUpdateDetails details) {
          double scale = details.scale;
          if (scale > 1) {
            scale = 1 / scale;
            // print("the scale is $scale");
          } else if (scale < 1) {
            scale = -scale;
            // print("the scale is decreasing $scale");
          }
          // For panning left to right
          // else {
          //   if (details.focalPointDelta.dx > 0) {
          //     print("Panning right");
          //   } else if (details.focalPointDelta.dx < 0) {
          //     print("Panning left");
          //   }
          //   return;
          // }
          Provider.of<GraphDataProvider>(context, listen: false)
              .setScrollIndex(scale * 10, sampleRate, envelopConfig);
        },
        child: const SpikerBoxUi(),
      ),
    );
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

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
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
            isGraphStatus = !isGraphStatus;

            widget.pauseButton(isGraphStatus);
            setState(() {});
          },
        ),
        const SizedBox(
          width: 15,
        ),
        SpikerBoxButton(
          padding: const EdgeInsets.all(5),
          iconSize: 20,
          iconData: Icons.keyboard_tab,
          onTapButton: () {},
        ),
      ],
    );
  }
}
