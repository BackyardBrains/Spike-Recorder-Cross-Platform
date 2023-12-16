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
            Row(
              children: [
                Text(
                  "Average Time = ${debugTimeList.averageTime}",
                  style: SoftwareTextStyle().kWtMediumTextStyle,
                ),
              ],
            ),
            Text(
              "Min TIme = ${debugTimeList.minTime} ",
              style: SoftwareTextStyle().kWtMediumTextStyle,
            ),
            Text(
              "Mxn TIme = ${debugTimeList.maxTime} ",
              style: SoftwareTextStyle().kWtMediumTextStyle,
            ),
          ],
        );
      }
      return const SizedBox.shrink();
    });
  }
}
