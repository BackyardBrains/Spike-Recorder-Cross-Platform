import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

class GraphDataProvider extends ChangeNotifier {
  int delay = 0;
  static const int _graphBufferLength = 10000;
  double _scale = 1.0;
  int _startIndex = 0;
  int _endIndex = _graphBufferLength - 1;
  int _timer = 20;
  int get timer => _timer;

  int samplesInCurrentView = _graphBufferLength;

  int get sampleOnGraph => samplesInCurrentView;

  final Int16List _entireGraphBuffer =
      Int16List.fromList(List.generate(_graphBufferLength, (index) => 0));

  Stream<Uint8List>? _inputGraphStream;

  Stream<List<double>>? _outputGraphStream;
  final StreamController<Uint8List> _outputGraphStreamController =
      StreamController.broadcast();

  Stream<List<double>>? get outputGraphStream => _outputGraphStream;

  /// Initializes the incoming data stream [_inputGraphStream]
  /// Initializes the stream to output data to graph [_outputGraphStream]
  void setStreamOfData(Stream<Uint8List> graphStreamData) {
    _inputGraphStream = graphStreamData;
    _outputGraphStream = _outputGraphStreamController.stream
        .asBroadcastStream()
        .transform(myStreamTransformer());

    _inputGraphStream!.listen(inputListener);
  }

  setTimer(int setTime) {
    _timer = setTime;
    notifyListeners();
  }

  /// Transforms the data from Int16 list (as Uint8List) to List<double>
  StreamTransformer<Uint8List, List<double>> myStreamTransformer() {
    StreamTransformer<Uint8List, List<double>> convert =
        StreamTransformer<Uint8List, List<double>>.fromHandlers(
      handleData: (value, sink) {
        // print("the value receive is ${value.sublist(0, 10)}");
        Int16List iList = value.buffer.asInt16List();
        List<double> dt =
            List.generate(iList.length, (index) => index.toDouble());

        for (int i = 0; i < iList.length; i++) {
          dt[i] = iList[i].toDouble();
        }
        sink.add(dt);
      },
    );
    return convert;
  }

  void inputListener(Uint8List input) {
    Int16List int16List = input.buffer.asInt16List();
    int valueCount = int16List.length;
    delay++;
    // if (delay == 1000) {
    //   print("dsf");
    // }
    int k = 0;

    for (int i = 0; i < _entireGraphBuffer.length; i++) {
      if (i < _entireGraphBuffer.length - valueCount) {
        _entireGraphBuffer[i] = _entireGraphBuffer[i + valueCount];
      } else {
        _entireGraphBuffer[i] = int16List[k];
        k++;
      }
    }

    updateGraph();
  }

  void resetGraphBuffer() {
    for (int i = 0; i < _entireGraphBuffer.length; i++) {
      _entireGraphBuffer[i] = 0;
    }

    updateGraph();
  }

  void updateGraph() {
    try {
      _outputGraphStreamController.add(_entireGraphBuffer
          .sublist(_startIndex, _endIndex)
          .buffer
          .asUint8List());
    } catch (e) {
      // print(
      //     "Exception: _entireGraphBufferLength : ${_entireGraphBuffer.length}, _startIndex: $_startIndex, _endIndex: $_endIndex");
    }
  }

  /// Sets the start and end index from where to read the data from [_entireGraphBuffer]
  void setScrollIndex(double delta) {
    _scale += delta * -0.001;
    _scale = _scale.clamp(0, 1);

    int tempSamplesInCurrentView = (_graphBufferLength * _scale).floor();

    // Samples should be more than 100
    tempSamplesInCurrentView =
        tempSamplesInCurrentView > 100 ? tempSamplesInCurrentView : 100;

    // Samples should be more than 10%
    tempSamplesInCurrentView =
        tempSamplesInCurrentView > (_graphBufferLength * 0.1)
            ? tempSamplesInCurrentView
            : (_graphBufferLength * 0.1).floor();

    samplesInCurrentView = (_endIndex) - tempSamplesInCurrentView < 0
        ? (_endIndex)
        : tempSamplesInCurrentView;
    _startIndex = (_endIndex) - samplesInCurrentView;

    _scale = (samplesInCurrentView / _graphBufferLength).clamp(0, 1);

    // print(
    //     "on setScrollIndex: $_startIndex - $_endIndex, tempSamplesInCurrentView: $tempSamplesInCurrentView, samples: $samplesInCurrentView");

    timeCalculate(samplesInCurrentView);
    updateGraph();

    notifyListeners();
  }

  timeCalculate(int currentSample) {
    int timeOfGraph = (double.tryParse((currentSample / _graphBufferLength)
                .toStringAsFixed(1)
                .replaceAll(".", "")) ??
            (currentSample / _graphBufferLength))
        .toInt();
    setTimer(currentSample + 1);
  }

  double getViewPortWidth() {
    int len = _endIndex - _startIndex;
    double ratio = len / _graphBufferLength;
    ratio = ratio.clamp(0, 1);
    return ratio;
  }

  void setPanLevel(double leftRatio, double rightRatio) {
    _startIndex = (_graphBufferLength * leftRatio).toInt();
    _startIndex = _startIndex < 0 ? 0 : _startIndex;

    _endIndex = _startIndex + samplesInCurrentView;
    _endIndex = _endIndex < _graphBufferLength ? _endIndex : _endIndex - 1;
    // print(
    //     "In SetPanLevel : _startIndex : $_startIndex, _endIndex: $_endIndex, samplesInCurrentView: $samplesInCurrentView");

    updateGraph();
  }
}
