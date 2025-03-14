import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'processing_util.dart';
import 'processing_bindings.dart';

// Message class for communication between isolates
class ProcessingMessage {
  final String type;
  final dynamic data;

  ProcessingMessage(this.type, this.data);
}

class ProcessingUtilImpl implements ProcessingUtil {
  Isolate? _processingIsolate;
  SendPort? portMainToProcessingIsolate;
  ReceivePort? portProcessingIsolateToMain;
  final _dataController = StreamController<dynamic>.broadcast();
  bool _isInitialized = false;
  static const int defaultSampleRate = 44100;

  @override
  Future<void> init() async {
    if (_isInitialized) return;

    // Initialize C++ processing
    final result = ProcessingBindings.instance.init();
    if (result != 0) {
      throw Exception('Failed to initialize processing: $result');
    }

    // Set default sample rate
    final sampleRateResult =
        ProcessingBindings.instance.setSampleRate(defaultSampleRate);
    if (sampleRateResult != 0) {
      throw Exception('Failed to set sample rate: $sampleRateResult');
    }

    // Create receive port for main isolate to receive messages from processing isolate
    portProcessingIsolateToMain = ReceivePort();

    // Create a completer to wait for the SendPort
    final completer = Completer<SendPort>();

    // Set up a single listener for all messages from the processing isolate
    portProcessingIsolateToMain!.listen((message) {
      if (!completer.isCompleted && message is SendPort) {
        // First message is the SendPort from the processing isolate
        portMainToProcessingIsolate = message;
        completer.complete(message);
      } else if (message is ProcessingMessage) {
        // Process subsequent messages
        switch (message.type) {
          case 'processedData':
            _dataController.add(message.data);
            break;
          case 'error':
            _dataController.addError(message.data);
            break;
        }
      }
    });

    // Spawn the processing isolate
    _processingIsolate = await Isolate.spawn(
      _processingIsolateFunction,
      portProcessingIsolateToMain!.sendPort,
    );

    // Wait for the SendPort to be received before continuing
    await completer.future;

    _isInitialized = true;
  }

  @override
  Future<void> processNewData(dynamic data) async {
    if (!_isInitialized) {
      throw StateError('ProcessingUtil not initialized. Call init() first.');
    }

    portMainToProcessingIsolate?.send(ProcessingMessage('newData', data));
  }

  // Get the stream of processed data
  Stream<dynamic> get processedDataStream => _dataController.stream;

  // Cleanup resources
  Future<void> dispose() async {
    _processingIsolate?.kill();
    portProcessingIsolateToMain?.close();
    await _dataController.close();
    ProcessingBindings.instance.cleanup();
    _isInitialized = false;
  }
}

// This function runs in the processing isolate
void _processingIsolateFunction(SendPort portToMain) {
  // Create receive port for processing isolate to receive messages from main
  final portFromMain = ReceivePort();

  // Send the processing isolate's SendPort back to main isolate
  portToMain.send(portFromMain.sendPort);

  // Listen for messages from main isolate
  portFromMain.listen((message) {
    if (message is ProcessingMessage) {
      try {
        switch (message.type) {
          case 'newData':
            // Process the data using C++ implementation
            final processedData = _processData(message.data);
            // Send processed data back to main isolate
            portToMain.send(ProcessingMessage('processedData', processedData));
            break;
        }
      } catch (e) {
        portToMain.send(ProcessingMessage('error', e.toString()));
      }
    }
  });
}

// Process data using C++ implementation
dynamic _processData(dynamic data) {
  if (data is List<double>) {
    final length = data.length;
    final pointer = calloc<Double>(length);

    try {
      // Copy data to native memory
      for (var i = 0; i < length; i++) {
        pointer[i] = data[i];
      }

      // Process data using C++ implementation
      final result = ProcessingBindings.instance.filterData(pointer, length);
      if (result != 0) {
        throw Exception('Failed to process data: $result');
      }

      // Copy processed data back to Dart
      return List<double>.generate(length, (i) => pointer[i]);
    } finally {
      calloc.free(pointer);
    }
  } else if (data is Uint8List) {
    // Convert Uint8List to doubles, process, and convert back
    final doubles = data.map((e) => e.toDouble()).toList();
    final processed = _processData(doubles);
    return Uint8List.fromList(processed.map((e) => e.round()).toList());
  } else {
    throw UnsupportedError('Unsupported data type: ${data.runtimeType}');
  }
}

// Export the implementation
ProcessingUtil createProcessingUtil() => ProcessingUtilImpl();
