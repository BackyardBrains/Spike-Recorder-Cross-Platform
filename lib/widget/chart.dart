import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import 'dart:async';

import '../models/models.dart';

class ChartView extends StatefulWidget {
  const ChartView({
    super.key,
    required this.stream,
  });
  final Stream<Uint8List> stream;

  @override
  State<ChartView> createState() => _ChartViewState();
}

class _ChartViewState extends State<ChartView> {
  List<DataPoint> _dataPoints = [];
  static const _graphPointsLength = kGraphPointsCount;

  final Random _random = Random();
  int _xCount = _graphPointsLength;

  ChartSeriesController? _controller;

  @override
  void initState() {
    super.initState();
    _dataPoints =
        List.generate(_graphPointsLength, (index) => DataPoint(index, 0));

    widget.stream.listen((event) {
      // ByteData byteData = event.buffer.asByteData();
      // List<int> newDataPoints = [];
      // for (int i = 0; i < byteData.lengthInBytes; i += 2) {
      //   newDataPoints.add(byteData.getUint16(i, Endian.big));
      // }

      Int16List newDataPoints = event.buffer.asInt16List();

      int l = min(newDataPoints.length, kGraphPointsCount);

      // Remove old points from start of buffer
      _dataPoints.removeRange(0, l);

      Iterable<DataPoint> newPoints = newDataPoints.sublist(0, l).map((e) {
        return DataPoint(_xCount++, e);
      });

      // Add new points to end of buffer
      _dataPoints.addAll(newPoints);

      if (_controller != null) {
        _controller?.updateDataSource(
          removedDataIndexes: List.generate(l, (index) => index),
          addedDataIndexes:
              List.generate(l, (index) => (_dataPoints.length - l) + index),
        );
      } else {
        Debugging.printing("Chart controller is null");
      }
    });
  }

  @override
  void dispose() {
    super.dispose();
  }

  int _generateRandomValue() {
    return _random.nextInt(120) + 20;
  }

  @override
  Widget build(BuildContext context) {
    return SfCartesianChart(
      borderWidth: 0,
      borderColor: Colors.white,
      enableSideBySideSeriesPlacement: true,
      primaryXAxis: NumericAxis(),
      primaryYAxis: NumericAxis(),

      // primaryXAxis: CategoryAxis(isVisible: true),
      // primaryYAxis: CategoryAxis(isVisible: true),
      series: <FastLineSeries<DataPoint, int>>[
        FastLineSeries<DataPoint, int>(
          dataSource: _dataPoints,
          onRendererCreated: (ChartSeriesController controller) {
            _controller = controller;
          },
          xValueMapper: (DataPoint data, _) => data.x,
          yValueMapper: (DataPoint data, _) => data.y,
          animationDuration: 0,
        ),
      ],
    );
  }
}

class DataPoint {
  final int x;
  final int y;

  DataPoint(this.x, this.y);

  @override
  String toString() {
    return 'DataPoint x: $x, y: $y\n';
  }
}
