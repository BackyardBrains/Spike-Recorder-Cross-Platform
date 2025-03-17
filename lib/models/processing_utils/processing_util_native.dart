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
  Future<bool> init() async {
    if (_isInitialized) return true;

    // Initialize C++ processing
    final result = ProcessingBindings.instance.init();
    if (result != 0) {
      print('Failed to initialize processing: $result');
      return false;
    }
    
    // Set default sample rate
    final sampleRateResult = 
        ProcessingBindings.instance.setSampleRate(44100);
    if (sampleRateResult != 0) {
      print('Failed to set sample rate: $sampleRateResult');
      return false;
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
    return true;
  }

  @override
  List<Int16List> processMicrophoneData(Uint8List data) {
    if (!_isInitialized) {
      throw StateError('ProcessingUtil not initialized. Call init() first.');
    }

    // Allocate memory for output parameters
    final outSamplesPtr = calloc<Pointer<Int16>>();
    final outSampleCountsPtr = calloc<Int32>();
    
    try {
      // Prepare input data pointer
      final inDataPtr = calloc<Uint8>(data.length);
      for (int i = 0; i < data.length; i++) {
        inDataPtr[i] = data[i];
      }
      
      // Process the microphone data
      final result = ProcessingBindings.instance.processMicrophoneStream(
        outSamplesPtr,
        outSampleCountsPtr,
        inDataPtr,
        data.length
      );
      
      // Free input data memory
      calloc.free(inDataPtr);
      
      if (result != 0) {
        throw Exception('Failed to process microphone data: $result');
      }
      
      // Get the number of samples in the result
      final sampleCount = outSampleCountsPtr.value;
      
      // Convert to Dart list
      final resultSamples = Int16List(sampleCount);
      for (int i = 0; i < sampleCount; i++) {
        resultSamples[i] = outSamplesPtr.value[i];
      }
      
      return [resultSamples]; // Return as list of channels
    } finally {
      // Free allocated memory
      calloc.free(outSamplesPtr);
      calloc.free(outSampleCountsPtr);
    }
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

// Factory function to create an instance
ProcessingUtil createProcessingUtil() => ProcessingUtilImpl();
