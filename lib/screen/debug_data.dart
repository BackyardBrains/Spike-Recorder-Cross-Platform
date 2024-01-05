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
            Text(
              "Packet Detail of render data(audio serial) on Graph",
              style: SoftwareTextStyle().kWtMediumTextStyle,
            ),
            Text(
              "Average Time = ${debugTimeList.averageTime} microsecond /per packet",
              style: SoftwareTextStyle().kWtMediumTextStyle,
            ),
            Text(
              "Min Time = ${debugTimeList.minTime} microsecond",
              style: SoftwareTextStyle().kWtMediumTextStyle,
            ),
            Text(
              "Max Time = ${debugTimeList.maxTime} microsecond",
              style: SoftwareTextStyle().kWtMediumTextStyle,
            ),
          ],
        );
      }
      return const SizedBox.shrink();
    });
  }
}
