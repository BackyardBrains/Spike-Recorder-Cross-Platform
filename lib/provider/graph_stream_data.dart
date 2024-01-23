import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:spikerbox_architecture/models/global_buffer.dart';

class GraphDataProvider extends ChangeNotifier {
  int delay = 0;
  static const int _graphBufferLength = 4000;
  // int bufferDuration = 30;

  double _scale = 1.0;
  int _startIndex = 0;
  int _endIndex = _graphBufferLength - 1;
  int _timer = 20;
  int get timer => _timer;
  int get graphBufferLength => _graphBufferLength;

  int samplesInCurrentView = _graphBufferLength;

  int get sampleOnGraph => samplesInCurrentView;

  int timeOnGraph = kIsWeb ? 1000 : 120000;

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
    // print("the input  ${input.length}");
    Int16List int16List = input.buffer.asInt16List();
    int valueCount = int16List.length;
    delay++;
    // if (delay == 1000) {
    //   print("dsf");
    // }
    // int k = 0;

    // for (int i = 0; i < _entireGraphBuffer.length; i++) {
    //   if (i < _entireGraphBuffer.length - valueCount) {
    //     _entireGraphBuffer[i] = _entireGraphBuffer[i + valueCount];
    //   } else {
    //     _entireGraphBuffer[i] = int16List[k];
    //     k++;
    //   }
    // }
    // print(
    //     "the entireGraphBuffer ${_entireGraphBuffer.length} and int16List ${int16List.length}");
    for (int i = 0; i < _entireGraphBuffer.length; i++) {
      _entireGraphBuffer[i] = int16List[i];
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
      // Int16List newInt16List =
      //     _entireGraphBuffer.sublist(_startIndex, _endIndex);
      // Int16List n = Int16List(_endIndex - _startIndex);

      // for (int i = 0; i < n.length; i++) {
      //   n[i] = newInt16List[i];
      // }
      // Int16List afterEnvelopData = envelopData(n, 2000);
      // _outputGraphStreamController.add(afterEnvelopData.buffer.asUint8List());

      // print("the _entire graph first index value is ${_entireGraphBuffer.}")
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
  // void setScrollIndex(double delta) {
  //   _scale += delta * -0.001;
  //   _scale = _scale.clamp(0, 1);

  //   int tempSamplesInCurrentView = (_graphBufferLength * _scale).floor();

  //   // Samples should be more than 100
  //   tempSamplesInCurrentView =
  //       tempSamplesInCurrentView > 100 ? tempSamplesInCurrentView : 100;

  //   // Samples should be more than 10%
  //   tempSamplesInCurrentView =
  //       tempSamplesInCurrentView > (_graphBufferLength * 0.1)
  //           ? tempSamplesInCurrentView
  //           : (_graphBufferLength * 0.1).floor();

  //   samplesInCurrentView = (_endIndex) - tempSamplesInCurrentView < 0
  //       ? (_endIndex)
  //       : tempSamplesInCurrentView;
  //   _startIndex = (_endIndex) - samplesInCurrentView;

  //   _scale = (samplesInCurrentView / _graphBufferLength).clamp(0, 1);

  //   // print(
  //   //     "on setScrollIndex: $_startIndex - $_endIndex, tempSamplesInCurrentView: $tempSamplesInCurrentView, samples: $samplesInCurrentView");

  //   timeCalculate(samplesInCurrentView);
  //   updateGraph();

  //   notifyListeners();
  // }
  void setScrollIndex(double delta, int sampleRate) {
    _scale += delta * -0.0001;
    _scale = _scale.clamp(0.001, 1);
    if (kIsWeb) {
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
      int durationToDisplay = (_scale * 1 * 1000).toInt();
      timeOnGraph = durationToDisplay;
      // timeCalculate(samplesInCurrentView);
    } else {
      /// In milliseconds
      int durationToDisplay = (_scale * 120 * 1000).toInt();
      // print("Duration ${durationToDisplay}");
      localPlugin.setEnvelopConfigure(durationToDisplay, sampleRate);

      timeOnGraph = durationToDisplay;
    }

    updateGraph();

    notifyListeners();
  }

  timeCalculate(int currentSample) {
    (double.tryParse((currentSample / _graphBufferLength)
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

  // set the bufferlength

  // setBufferLength(int graphBufferLength) {
  //   print("the buffer length is ${_graphBufferLength}");
  //   // _graphBufferLength = graphBufferLength * 30;

  //   notifyListeners();
  // }

  //enveloping the data

  Int16List envelopData(Int16List samples, int totalPoints) {
    int stepSize = (samples.length / totalPoints).round();
    Int16List envelopePoints =
        Int16List(totalPoints * 2); // Double the size for min and max values

    for (int i = 0; i < totalPoints; i++) {
      int start = i * stepSize;
      int end = (i + 1) * stepSize;
      end = end > samples.length ? samples.length : end;

      int maxVal = samples.sublist(start, end).reduce(max);
      int minVal = samples.sublist(start, end).reduce(min);
      envelopePoints[i * 2] = maxVal;
      envelopePoints[i * 2 + 1] = minVal;
    }

    return envelopePoints;
  }
  // Int16List envelopData(Int16List sourceData, int envelopedLength) {
  //   // Initialize the list to store enveloped data
  //   Int16List envelopedData = Int16List(envelopedLength);

  //   // Initialize circular buffer for envelopes
  //   int head = 0;
  //   List<Int16List> envelopes = List.generate(
  //     21,
  //     (index) => Int16List((sourceData.length / (1 << index)).ceil()),
  //   );

  //   // Iterate through each sample in the source data
  //   for (int i = 0; i < sourceData.length; i++) {
  //     // Iterate through different levels of envelopes
  //     for (int j = 1; j <= 21; j++) {
  //       int skipCount = 1 << j;
  //       int envelopeIndex = j - 1;
  //       int envelopeSampleIndex = (head ~/ skipCount);

  //       // Check if the envelope index is within bounds
  //       if (envelopeSampleIndex >= envelopes[envelopeIndex].length) {
  //         continue;
  //       }

  //       // Retrieve the current value in the envelope
  //       int dst = envelopes[envelopeIndex][envelopeSampleIndex];

  //       // Update the envelope based on the current sample
  //       if (head % skipCount == 0) {
  //         envelopes[envelopeIndex][envelopeSampleIndex] = sourceData[i];
  //       } else {
  //         envelopes[envelopeIndex][envelopeSampleIndex] =
  //             dst < sourceData[i] ? sourceData[i] : dst;
  //       }
  //     }

  //     // Add the raw data to the enveloped data (circular buffer)
  //     envelopedData[head++] = sourceData[i];

  //     // Wrap around the circular buffer if it reaches the specified length
  //     if (head == envelopedLength) {
  //       head = 0;
  //     }
  //   }

  //   // Return the enveloped data
  //   return envelopedData;
  // }
}
