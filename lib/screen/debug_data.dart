import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:spikerbox_architecture/constant/const_export.dart';

import '../provider/provider_export.dart';

class DebugTheDataDetail extends StatefulWidget {
  const DebugTheDataDetail({super.key});

  @override
  State<DebugTheDataDetail> createState() => _DebugTheDataDetailState();
}

class _DebugTheDataDetailState extends State<DebugTheDataDetail> {
  @override
  Widget build(BuildContext context) {
    return Consumer2<DebugTimeProvider, DataStatusProvider>(
        builder: (context, debugTimeList, dataStatus, snapshot) {
      if (dataStatus.isDebugging) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _TextWidget(
              text: "Packet Detail of render data(audio serial) on Graph",
            ),
            _TextWidget(
              text:
                  "Average Time = ${debugTimeList.averageTime} microsecond /per packet",
            ),
            _TextWidget(
              text: "Min Time = ${debugTimeList.minTime} microsecond",
            ),
            _TextWidget(
              text: "Max Time = ${debugTimeList.maxTime} microsecond",
            ),
            // _TextWidget(
            //     text:
            //         "Audio Avg Time = ${debugTimeList.audioDetail.avgTime.toString()}"),
            // _TextWidget(
            //     text:
            //         "Audio Max Time = ${debugTimeList.audioDetail.maxTime.toString()}"),
            // _TextWidget(
            //     text:
            //         "Audio Min Time = ${debugTimeList.audioDetail.minTime.toString()}")
          ],
        );
      }
      return const SizedBox.shrink();
    });
  }
}

class _TextWidget extends StatelessWidget {
  const _TextWidget({super.key, required this.text});
  final String text;
  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: SoftwareTextStyle().kWtMediumTextStyle,
    );
  }
}
