import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

class GraphDataProvider extends ChangeNotifier {
  int _timer = 20;
  int get timer => _timer;
  double _viewportWidth = 0.1; // Default 10% of total width
  int _samplesOnGraph = 1000; // Default value

  Stream<Uint8List>? _inputGraphStream;
  Stream<List<double>>? _outputGraphStream;
  final StreamController<Uint8List> _outputGraphStreamController = StreamController.broadcast();

  final _zoomEventController = StreamController<double>.broadcast();
  Stream<double> get zoomEvents => _zoomEventController.stream;

  Stream<List<double>>? get outputGraphStream => _outputGraphStream;
  int get sampleOnGraph => _samplesOnGraph;
  double getViewPortWidth() => _viewportWidth;

  void setStreamOfData(Stream<Uint8List> graphStreamData) {
      _inputGraphStream = graphStreamData;
      _outputGraphStream = _outputGraphStreamController.stream
            .asBroadcastStream()
            .transform(myStreamTransformer());

      _inputGraphStream!.listen(inputListener);
  }

  void inputListener(Uint8List input) {
      _outputGraphStreamController.add(input);
  }

  void setScrollIndex(double delta) {
      // Handle zooming logic here if needed
      notifyListeners();
  }

  void resetGraphBuffer() {
      // Reset any necessary state
      notifyListeners();
  }

  StreamTransformer<Uint8List, List<double>> myStreamTransformer() {
    return StreamTransformer<Uint8List, List<double>>.fromHandlers(
      handleData: (value, sink) {
        Int16List iList = value.buffer.asInt16List();
        List<double> dt = List.generate(iList.length, (index) => iList[index].toDouble());
        sink.add(dt);
      },
    );
  }

  setTimer(int setTime) {
      _timer = setTime;
      notifyListeners();
  }

  void setPanLevel(double leftRatio, double rightRatio) {
    _viewportWidth = 1.0 - (leftRatio + rightRatio);
    notifyListeners();
  }

  void notifyZoomEvent(double scrollDelta) {
    _zoomEventController.add(scrollDelta);
  }

  @override
  void dispose() {
    _zoomEventController.close();
    super.dispose();
  }
}
