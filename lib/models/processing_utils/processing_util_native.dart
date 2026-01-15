import 'dart:async';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ffi';
import 'dart:io';
// import 'dart:ui';
import 'package:ffi/ffi.dart';
import 'package:spikerbox_architecture/models/CircularFloatArrayBuffer.dart';
import 'package:spikerbox_architecture/models/FftDrawBuffer.dart';
import 'package:spikerbox_architecture/models/default_config_model.dart';
import 'package:spikerbox_architecture/provider/graph_stream_data.dart';
import 'package:spikerbox_architecture/screen/graph_template.dart';
import 'package:spikerbox_architecture/screen/spiker_box_ui.dart';
import 'package:spikerbox_architecture/widget/fft_painter.dart';
import 'processing_util.dart';
// import 'package:native_add/native_add.dart';
import 'package:processing_ffi/processing_ffi.dart' as pb;
// import 'package:processing_ffi/processing_bindings.dart';
// import 'processing_bindings.dart';

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
  int _sampleRate = 44100;
  int _channelCount = 1;
  int defaultChannelCountNoExpansionBoard = -1;
  int defaultSampleRateNoExpansionBoard = -1;
  String currentExpansionBoardString = "";
  int currentDrawSurfaceWidth = 0;

  @override
  CircularFloatArrayBuffer fftBuffer = CircularFloatArrayBuffer(500, 500);

  // final outEventIndicesPtr = calloc<Float>(100);

  // Implementation of the data buffer
  Pointer<Pointer<Int16>>? currentDataBuffer;
  int? _allocatedChannelCount; // Track the actual number of channels allocated
  // @override
  // var currentDataBuffer;
  Pointer<Int32>? inEventIndicesPtr;
  Pointer<Int32>? inEventLabelsPtr;

  // @override
  // var currentDataBuffer;
  @override
  Future<bool> initWithConfig(Int32List config) async {
    print("initWithConfig: $config");
    final result = pb.processingBindings.init();
    setupDartCallbacks();
    if (result != 0) {
      print('Failed to initialize processing: $result');
      return false;
    }
    pb.processingBindings.setSampleRate(config[0].toInt());
    pb.processingBindings.setChannelCount(config[1].toInt());
    sampleRate = config[0].toInt();
    _sampleRate = config[0].toInt();
    channelCount = config[1].toInt();
    _channelCount = config[1].toInt();
    ProcessingUtil.medianChannelValueAdjuster = List.generate(channelCount, (_) => 0);
    
    int drawSurfaceWidth = config[7].toInt();
    currentDrawSurfaceWidth = drawSurfaceWidth;
    
    ProcessingUtil.drawingBuffers.clear();
    for (int i = 0; i < channelCount; i++) {
      ProcessingUtil.drawingBuffers
          .add(Int16List(drawSurfaceWidth.toInt() * 5));
      ProcessingUtil.drawingBufferCounts.add(drawSurfaceWidth.toInt() * 5);
    }
    print("FINISH initWithConfig: $config");

    return Future.value(true);
  }


  final ReceivePort _nativeCallbackPort = ReceivePort();
  @override
  void setupDartCallbacks() {
    // Listen for messages from C++
    print("setupDartCallbacks start");
    _nativeCallbackPort.listen((message) {
      print("setupDartCallbacks listen start $message");
      // if (message is List && message.isNotEmpty) {
        // final String messageType = message[0] as String;
        final int value1 = message as int;
        handleExpansionBoardTypeDetection(value1);
        // final int value2 = message.length > 2 ? message[2] as int : 0;
        
        // Handle different message types
        // switch (messageType) {
        //   case 'onExpansionBoardTypeDetection':
        //     print("onExpansionBoardTypeDetection: $value1");
        //     handleExpansionBoardTypeDetection(value1);
        //     break;
        //   // Add more cases as needed
        //   default:
        //     print('Unknown message type: $messageType');
        // }
      // }
    });

    
    // Pass the required pointer from Dart to C++
    final result = pb.processingBindings.initDartApiDL(NativeApi.initializeApiDLData);
    if (result != 0) throw "Failed to initialize Dart DL API";    
    else {
      print('Dart DL API initialized successfully');
    }
    print("setupDartCallbacks end");

    pb.processingBindings.registerDartPort(_nativeCallbackPort.sendPort.nativePort);
    // Register the port with C++
    // final int result = pb.processingBindings.registerDartPort(
    //   _nativeCallbackPort.sendPort.nativePort
    // );
    
    // if (result != 0) {
    //   print('Failed to register Dart port: $result');
    // } else {
    //   print('Dart port registered successfully');
    // }
  }

  // Cleanup when done
  @override
  void cleanupDartCallbacks() {
    pb.processingBindings.unregisterDartPort();
    postChannelCountController.close();
    _nativeCallbackPort.close();
  }  

  void handleExpansionBoardTypeDetection(int expBoardType) {
    print('Expansion board type detected: $expBoardType');
    print("setExpansionBoardTypeDart");
    print(GraphTemplate.selectedBoard);
    if (GraphTemplate.selectedBoard != null) {
      print("setExpansionBoardTypeDart1");
      if (GraphTemplate.selectedBoard!.expansionBoards != null) {
        print("setExpansionBoardTypeDart2 ${GraphTemplate.selectedBoard!.expansionBoards!}");
        for (var expBoard in GraphTemplate.selectedBoard!.expansionBoards!) {
          print("setExpansionBoardTypeDart3 ${expBoardType.toString()}");
          if (expBoard.boardType == expBoardType.toString()) {
            print("setExpansionBoardTypeDart4");
            if (currentExpansionBoardString == "" && expBoardType == 0) {
              return;
            } else
            if (currentExpansionBoardString != expBoardType.toString()) {
              currentExpansionBoardString = expBoardType.toString();
              if (expBoard.maxSampleRate != null) {
                print("setExpansionBoardTypeDart5");
                int boardChannels = -1;
                if (GraphTemplate.selectedBoard!.uniqueName == "HUMANSB") {
                  if (expBoardType == 1) {
                    // int expBoardSampleRate = int.parse(expBoard.maxSampleRate!);
                    // boardChannels = int.parse(GraphTemplate.selectedBoard!.maxNumberOfChannels!);
                    // print("SelectedBoard CHannel: ${GraphTemplate.selectedBoard!.maxNumberOfChannels!} --- maxNumberOfChannels: ${expBoard.maxNumberOfChannels!}");
                    // postChannelCountController.add(boardChannels);
                    // initializeSerial(GraphTemplate.selectedBoard!, currentDrawSurfaceWidth.toDouble(), expansionBoardChannelCount: int.parse(expBoard.maxNumberOfChannels!) );
                    // js.context.callMethod("initializeSerialWeb", [expBoardSampleRate, boardChannels, -1] );

                  } else {
                    int expBoardSampleRate = int.parse(expBoard.maxSampleRate!);
                    boardChannels = int.parse(GraphTemplate.selectedBoard!.maxNumberOfChannels!) + int.parse(expBoard.maxNumberOfChannels!);
                    print("SelectedBoard CHannel: ${GraphTemplate.selectedBoard!.maxNumberOfChannels!} --- maxNumberOfChannels: ${expBoard.maxNumberOfChannels!}");
                    postChannelCountController.add(boardChannels);
                    initializeSerial(GraphTemplate.selectedBoard!, currentDrawSurfaceWidth.toDouble(), expansionBoardChannelCount: int.parse(expBoard.maxNumberOfChannels!) );
                    // js.context.callMethod("initializeSerialWeb", [expBoardSampleRate, boardChannels, -1] );

                  }
                } else {

                  int expBoardSampleRate = int.parse(expBoard.maxSampleRate!);
                  boardChannels = int.parse(GraphTemplate.selectedBoard!.maxNumberOfChannels!) + int.parse(expBoard.maxNumberOfChannels!);
                  print("SelectedBoard CHannel: ${GraphTemplate.selectedBoard!.maxNumberOfChannels!} --- maxNumberOfChannels: ${expBoard.maxNumberOfChannels!}");
                  postChannelCountController.add(boardChannels);
                  initializeSerial(GraphTemplate.selectedBoard!, currentDrawSurfaceWidth.toDouble(), expansionBoardChannelCount: int.parse(expBoard.maxNumberOfChannels!) );
                  // js.context.callMethod("initializeSerialWeb", [expBoardSampleRate, boardChannels, -1] );
                }


                // if (expBoard.boardType == "4") {
                //   ProcessingUtil.medianChannelValueAdjuster = List.generate(boardChannels, (_) => 0);
                //   ProcessingUtil.medianChannelValueAdjuster[3] = -4096;
                // }else {
                //   ProcessingUtil.medianChannelValueAdjuster = List.generate(boardChannels, (_) => 0);
                // }
              }
            }
          } else 
          if (expBoardType == 0) {
            print("setExpansionBoardTypeDart3.5 : $currentExpansionBoardString");
            if (currentExpansionBoardString.isNotEmpty) {
              currentExpansionBoardString = "";
              postChannelCountController.add(defaultChannelCountNoExpansionBoard);
              initializeSerial(GraphTemplate.selectedBoard!, currentDrawSurfaceWidth.toDouble(), expansionBoardChannelCount: int.parse(expBoard.maxNumberOfChannels!) );

              // js.context.callMethod("initializeSerialWeb", [defaultSampleRateNoExpansionBoard, defaultChannelCountNoExpansionBoard, -1] );
              defaultChannelCountNoExpansionBoard = -1;
              defaultSampleRateNoExpansionBoard = -1;              
            }
          }
        }
      }
    }    
    // Your Dart code here
  }

  @override
  Future<bool> init() async {
    if (_isInitialized) return true;
    setupDartCallbacks();
    // Initialize C++ processing
    ProcessingUtil.medianChannelValueAdjuster = List.generate(channelCount, (_) => 0);
    
    print('initialize processing');
    final result = pb.processingBindings.init();
    if (result != 0) {
      print('Failed to initialize processing: $result');
      return false;
    }

    // Set default sample rate
    // print('Failed to set sample rate??:');
    final sampleRateResult = pb.processingBindings.setSampleRate(_sampleRate);
    if (sampleRateResult != 0) {
      print('Failed to set sample rate11: $sampleRateResult');
      return false;
    }

/*
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
*/
    initFft();
    _isInitialized = true;
    return true;
  }

  @override
  void setAveragedSampleCount(int avgSampleCount) {
    print("setAveragedSampleCount: $avgSampleCount");
    pb.processingBindings.setAveragedSampleCount(avgSampleCount);
  }

  @override
  void setThreshold(double thresholdValue) {
    print("SET THRESHOLD: $thresholdValue");
    pb.processingBindings.setThreshold(thresholdValue);
  }

  @override
  Future<bool> initializeMicrophone(
      int channelCount, int sampleRate, double drawSurfaceWidth) async {
    if (!_isInitialized) {
      await init();
    }
    currentDrawSurfaceWidth = drawSurfaceWidth.floor();
    //todo: check if the currentDataBuffer is already initialized. If yes free memory before reinitializing
    if (currentDataBuffer != null) {
      try {
        // Use the actual allocated channel count, or fall back to _channelCount
        final countToFree = _allocatedChannelCount ?? _channelCount;
        if (countToFree > 0) {
          for (int i = 0; i < countToFree; i++) {
            calloc.free(currentDataBuffer![i]);
          }
        }
        calloc.free(currentDataBuffer!);
      } catch (e) {
        print("Error freeing currentDataBuffer: $e");
      }
      currentDataBuffer = null;
      _allocatedChannelCount = null;
      ProcessingUtil.currentEventMarkers = 0;
      // for (int i = 0; i < _channelCount; i++) {
      // 	calloc.free((currentDataBuffer!.value + i).cast<Pointer<Int16>>().value);
      // }
      // calloc.free(currentDataBuffer!.value);
      // calloc.free(currentDataBuffer!);
    }

    ProcessingUtil.drawingBuffers.clear();
    for (int i = 0; i < channelCount; i++) {
      ProcessingUtil.drawingBuffers
          .add(Int16List(drawSurfaceWidth.toInt() * 5));
      ProcessingUtil.drawingBufferCounts.add(drawSurfaceWidth.toInt() * 5);
    }

    // Update local properties
    _channelCount = channelCount;
    _sampleRate = sampleRate;

    // Set channel count and sample rate in C++ processing
    final channelResult = pb.processingBindings.setChannelCount(channelCount);
    if (channelResult != 0) {
      print('Failed to set channel count: $channelResult');
      return false;
    }

    final sampleRateResult = pb.processingBindings.setSampleRate(sampleRate);
    if (sampleRateResult != 0) {
      print('Failed to set sample rate: $sampleRate');
      return false;
    }

    // Pre-allocate the buffer memory
    final int sampleCount =
        (ProcessingUtil.MAX_DISPLAY_SECONDS * sampleRate).toInt();

    // Allocate array of pointers for each channel
    // final channelArrayPtr = calloc<Pointer<Int16>>(channelCount);
    // currentDataBuffer = channelArrayPtr.cast<Pointer<Int16>>();
    // final outSamplesPtr = calloc<Pointer<Int16>>(channelCount);
    // for (int i = 0; i < channelCount; i++) {
    //     outSamplesPtr[i] = calloc<Int16>(drawSurfaceWidth * 5); // 5x for envelope
    // }
    if (currentDataBuffer == null) {
      currentDataBuffer = calloc<Pointer<Int16>>(channelCount);
      for (int i = 0; i < channelCount; i++) {
        currentDataBuffer?[i] = calloc<Int16>(sampleCount); // 5x for envelope
      }
      _allocatedChannelCount = channelCount; // Track the allocated count
    }

    // Allocate memory for each channel
    // for (int i = 0; i < channelCount; i++) {
    // 	channelArrayPtr[i] = calloc<Int16>(sampleCount);
    // }

    print(
        'Microphone initialized with $channelCount channels at $sampleRate Hz');
    print('Buffer size: $channelCount channels × $sampleCount samples');

    // Free existing event marker pointers if they exist (initEventMarkers will reallocate them)
    if (inEventIndicesPtr != null) {
      calloc.free(inEventIndicesPtr!);
      inEventIndicesPtr = null;
    }
    if (inEventLabelsPtr != null) {
      calloc.free(inEventLabelsPtr!);
      inEventLabelsPtr = null;
    }
    
    ProcessingUtil.currentEventMarkers = 0;
    // initEventMarkers will allocate inEventIndicesPtr and inEventLabelsPtr
    initEventMarkers(_sampleRate);
    ProcessingUtil.eventMarkerNotifier.removeListener(eventMarkerListener);
    ProcessingUtil.eventMarkerNotifier.addListener(eventMarkerListener);

    return true;
  }

  @override
  // List<Int16List> processMicrophoneData(Uint8List data, bool isAverageSamples, bool isThresholdingButton, int drawSurfaceWidth, int selectedChannel) {
  List<Int16List> processMicrophoneData(Uint8List data) {
    if (!_isInitialized) {
      throw StateError('ProcessingUtil not initialized. Call init() first.');
    }
    // ProcessingUtil.positionIndex =
    //     (ProcessingUtil.positionIndex + data.length / 2).toInt() %
    //         (ProcessingUtil.MAX_DISPLAY_SECONDS * _sampleRate * 2).toInt();
    // print("ProcessingUtil.positionIndex : $_sampleRate --  ${ProcessingUtil.positionIndex}");

    final outSampleCountsPtr = calloc<Int32>();
    try {
      // Prepare input data pointer
      final inDataPtr = calloc<Uint8>(data.length);
      for (int i = 0; i < data.length; i++) {
        inDataPtr[i] = data[i];
      }

      // Process the microphone data using pre-allocated buffer
      // print("PROCESS MICROPHONE DATA1: ${data.length}");
      final result = pb.processingBindings.processMicrophoneStream(
          currentDataBuffer!, outSampleCountsPtr, inDataPtr, data.length);
      // print("ERROR PROCESS MICROPHONE DATA: ${data.length} $result");
      if (result != 0) {

        // throw Exception('Failed to process microphone data: $result');
      } else {
      }


      // Free input data memory
      calloc.free(inDataPtr);
      int frameCount = (data.length / 2).floor();
      // print("frameCount: $frameCount");
      int removedIndicesCount = 0;
      for (int i = 0; i < ProcessingUtil.currentEventMarkers; i++) {
        if (inEventIndicesPtr![i] - frameCount > 0) {
          inEventIndicesPtr![i] -= frameCount;
          ProcessingUtil.eventPosition[i] = inEventIndicesPtr![i];
        } else {
          if (inEventIndicesPtr![i] != -1) {
            removedIndicesCount++;
            inEventIndicesPtr![i] = -1;
            // DraggableGraph.eventMarkersPosition.removeAt(i);
          }
        }
      }
      for (int i = 0; i < removedIndicesCount; i++) {
        if (inEventIndicesPtr![i] == -1) {
          // print(
          //     "INDEX: $i -- $removedIndicesCount __ ${inEventIndicesPtr![i]} : ${ProcessingUtil.eventLabels} @@ ${inEventIndicesPtr!.asTypedList(ProcessingUtil.currentEventMarkers)}");
          if (ProcessingUtil.eventLabels.isNotEmpty) {
            ProcessingUtil.eventLabels.removeAt(0);
            ProcessingUtil.eventPosition.removeAt(0);
          }
        }
      }
      int tempCurrentEvent = ProcessingUtil.currentEventMarkers;
      ProcessingUtil.currentEventMarkers -= removedIndicesCount;
      if (inEventIndicesPtr != null && inEventIndicesPtr![0] == -1) {
        int eventPositionLen = ProcessingUtil.eventLabels.length;
        // print(
        //     "0ProcessingUtil.eventPosition ${ProcessingUtil.eventPosition.sublist(0, eventPositionLen)} --- ${inEventIndicesPtr!.asTypedList(eventPositionLen)}");
        for (int i = eventPositionLen; i >= 0; i--) {
          inEventIndicesPtr![i] = ProcessingUtil.eventPosition[i];
        }
        for (int i = eventPositionLen; i < tempCurrentEvent; i++) {
          // print("ZEROING: $eventPositionLen - $tempCurrentEvent");
          inEventIndicesPtr![i] =
              (ProcessingUtil.MAX_DISPLAY_SECONDS * _sampleRate).floor();
        }
        // print(
        //     "1ProcessingUtil.eventPosition ${ProcessingUtil.eventPosition.sublist(0, eventPositionLen)} --- ${inEventIndicesPtr!.asTypedList(eventPositionLen)}");
      }
      // print("PROCESS MICROPHONE DATA2: ${data.length}");

      // Create Dart view of the native memory
      final sampleCount = outSampleCountsPtr.value;
      Pointer<Pointer<Int16>> curDataBuffer = currentDataBuffer as Pointer<Pointer<Int16>>;
      final bufferViews = List<Int16List>.generate(
      	_channelCount,
      	(i) => curDataBuffer[i].cast<Int16>().asTypedList(sampleCount)
      );
      return bufferViews;

      
      // return [];
    } finally {
      calloc.free(outSampleCountsPtr);
    }
  }

  @override
  Future<int> setBandFilter(double lowCutOffFreq, double highCutOffFreq) async {
    if (!_isInitialized) {
      await init();
    }

    print("LH: $lowCutOffFreq $highCutOffFreq");
    return pb.processingBindings.setBandFilter(lowCutOffFreq, highCutOffFreq);
  }

  @override
  Future<int> setNotchFilter(double centerFreq) async {
    if (!_isInitialized) {
      await init();
    }
    return pb.processingBindings.setNotchFilter(centerFreq);
  }

  @override
  Future<int> setChannelFilterEnabled(int channel, bool enabled) async {
    if (!_isInitialized) {
      await init();
    }
    return pb.processingBindings
        .setChannelFilterEnabled(channel, enabled ? 1 : 0);
  }


  @override
  int prepareForSignalDrawingProcess(
      outSamples,
      outSampleCounts,
      outEventIndices,
      outEventCount,
      inEventIndices,
      int inEventCount,
      int fromSample,
      int toSample,
      int drawSurfaceWidth) {
    if (!_isInitialized) {
      throw StateError('ProcessingUtil not initialized. Call init() first.');
    }
    currentDrawSurfaceWidth = drawSurfaceWidth;

    try {
      // Call the native function with correct parameters
      final result = pb.processingBindings.prepareForSignalDrawing(
          outSamples,
          outSampleCounts,
          outEventIndices,
          outEventCount,
          inEventIndices,
          inEventCount,
          fromSample,
          toSample,
          drawSurfaceWidth);
      // print("prepareForSignalDrawing: $result $fromSample $toSample");
      return result;
    } catch (e) {
      print('Error in prepareForSignalDrawing: $e');
      return -1;
    }
  }

  // Get the stream of processed data
  Stream<dynamic> get processedDataStream => _dataController.stream;
  
  @override
  StreamController<int> postChannelCountController = StreamController<int>();
  @override
  Stream<int>? postChannelCountStream;

  // Cleanup resources
  Future<void> dispose() async {
    postChannelCountController.close();
    cleanupDartCallbacks();    
    _processingIsolate?.kill();
    portProcessingIsolateToMain?.close();
    await _dataController.close();

    // Free allocated memory
    // try {
    if (currentDataBuffer != null) {
      // for (int i = 0; i < _channelCount; i++) {
      //   calloc.free((currentDataBuffer!.value + i).cast<Pointer<Int16>>().value);
      // }
      // calloc.free(currentDataBuffer!.value);
      // calloc.free(currentDataBuffer!);
      final countToFree = _allocatedChannelCount ?? _channelCount;
      if (countToFree > 0) {
        for (int i = 0; i < countToFree; i++) {
          calloc.free(currentDataBuffer![i]);
        }
      }
      calloc.free(currentDataBuffer!);

      currentDataBuffer = null;
      _allocatedChannelCount = null;
      // free fft pointer      
      try{
        if (window_count.isNotEmpty) {
          for (int i = 0; i < window_count[0]; i++) {
            calloc.free(out_fft_data![i]);
          }
          calloc.free(out_fft_data!);
        }

        calloc.free(out_fft_vertices!);
        calloc.free(out_fft_indices!);
        calloc.free(out_fft_colors!);
        calloc.free(out_fft_vertex_count!);
        calloc.free(out_fft_index_count!);
        calloc.free(out_fft_color_count!);    
      }catch(err) {
        print("err");
        print(err);
      }
    }
    // }catch(err) {

    // }

    pb.processingBindings.cleanup();
    _isInitialized = false;
  }

  @override
  List<Int16List> prepareDisplayMicrophoneData(
      List<Int16List> processedData,
      int drawSurfaceWidth,
      int channelCount,
      double displayTimeMs,
      GraphDataProvider provider,
      int startPositionIdx,
      int endPositionIdx) {
      // return [Int16List(0)];
    if (processedData.isNotEmpty) {
      currentDrawSurfaceWidth = drawSurfaceWidth;
      ProcessingUtil.fromDrawingIdx = startPositionIdx;
      ProcessingUtil.toDrawingIdx = endPositionIdx;
      // Convert Int16List to Float data for signal drawing
      int frameCount = processedData[0].length;
      List<Float32List> floatSignalData = [];

      // Convert each channel's data to float
      for (int i = 0; i < processedData.length; i++) {
        Float32List floatData = Float32List(frameCount);
        for (int j = 0; j < frameCount; j++) {
          floatData[j] = processedData[i][j].toDouble();
        }
        floatSignalData.add(floatData);
      }

      // Prepare for drawing - focusing on the first channel for now
      // Float32List outSignal = Float32List(drawSurfaceWidth * 5); // 5x for envelope
      // Int32List outEvents = Int32List(100); // Max 100 events

      // Allocate memory for output samples (array of float arrays)
      final outSamplesPtr = calloc<Pointer<Int16>>(channelCount);
      for (int i = 0; i < channelCount; i++) {
        outSamplesPtr[i] =
            calloc<Int16>(drawSurfaceWidth * 5); // 5x for envelope
      }

      // Allocate memory for sample counts
      final outSampleCountsPtr = calloc<Int32>(channelCount);

      // Allocate memory for event indices (assuming max 100 events)
      final outEventIndicesPtr =
          calloc<Float>(ProcessingUtil.MAX_EVENT_MARKERS);

      // Allocate memory for event count
      final outEventCountPtr = calloc<Int32>(1);

      // Allocate and prepare input event indices
      // final inEventIndicesPtr = calloc<Int32>(0); // No events yet
      // int sampleResolution = (displayTimeMs*0.001 * _sampleRate).toInt();

      try {
        int result = prepareForSignalDrawingProcess(
            outSamplesPtr, // Pointer<Pointer<Float>>
            outSampleCountsPtr, // Pointer<Int32>
            outEventIndicesPtr, // Pointer<Float>
            outEventCountPtr, // Pointer<Int32>
            inEventIndicesPtr, // Pointer<Int32>
            ProcessingUtil.currentEventMarkers, // int (inEventCount)
            startPositionIdx, // int (fromSample)
            endPositionIdx, // int (toSample)
            drawSurfaceWidth // int
        );

        if (result == 0) {
          // Copy the results back to Dart
          // Get the number of samples from outSampleCountsPtr
          int sampleCount = outSampleCountsPtr.value;
          // Copy the prepared signal data
          //for (int i = 0; i < widget.channelCount; i++) {
          // Int16List channelData = outSamplesPtr[0].asTypedList(sampleCount);
          //print("Sample count: $sampleCount");
          //print("first sample: ${channelData[0]}");
          //se log with this:
          // cat /tmp/flutter_native_crash.log

          // Uint8List uint8Data = Uint8List.view(channelData.buffer);
          // ProcessingUtil.drawingBuffers.clear();
          for (int i = 0; i < channelCount; i++) {
            final temp = outSamplesPtr[i].asTypedList(sampleCount);
            // print("temp: ${temp.length} - $sampleCount :: ${ProcessingUtil.drawingBuffers[i].length}");
            // final arrDouble = List.generate(sampleCount, (index) => temp[index].toDouble());
            // if (ProcessingUtil.drawingBuffers.length <= i) {
            // ProcessingUtil.drawingBuffers.add( arrDouble );
            // } else {
            ProcessingUtil.drawingBuffers[i].setAll(0, temp);
            ProcessingUtil.drawingBufferCounts[i] = sampleCount;
            // }
          }
          DraggableGraph.eventMarkersPosition.clear();
          DraggableGraph.eventMarkersLabels.clear();
          var tempList =
              outEventIndicesPtr.asTypedList(ProcessingUtil.eventLabels.length);
          // print(
          //     "tempList: $tempList --- ${ProcessingUtil.currentEventMarkers}");
          for (double temp in tempList) {
            DraggableGraph.eventMarkersPosition.add(temp);
          }

          int len = ProcessingUtil.eventLabels.length;
          int startPositionIdx = DraggableGraph.startPositionIdx;
          int endPositionIdx = DraggableGraph.endPositionIdx;
          for (int i = 0; i < len; i++) {
            // print("RANGE : $startPositionIdx - $endPositionIdx");
            if (ProcessingUtil.eventPosition[i] >= startPositionIdx && ProcessingUtil.eventPosition[i] <= endPositionIdx ) {
              DraggableGraph.eventMarkersLabels.add(ProcessingUtil.eventLabels[i]);
            }
          }


          // print(
          //     "DraggableGraph.eventMarkersPosition: ${DraggableGraph.eventMarkersPosition}");

          provider.inputListener(Uint8List(0));
          //provider.inputListener(channelData);
          // Get the number of events
          int eventCount = outEventCountPtr.value;
          if (eventCount > 0) {
            // Copy event indices if needed
            // Float32List eventIndices = outEventIndicesPtr.asTypedList(eventCount);
            // Use eventIndices as needed
          }
        }
      } finally {
        // Clean up allocated memory
        for (int i = 0; i < channelCount; i++) {
          calloc.free(outSamplesPtr[i]);
        }
        calloc.free(outSamplesPtr);
        calloc.free(outSampleCountsPtr);
        calloc.free(outEventIndicesPtr);
        calloc.free(outEventCountPtr);
        // calloc.free(inEventIndicesPtr);
      }
    }
    return processedData;
  }

  int MAX_DISPLAY_SECONDS = 10;

  int channelCount = 1;
  int sampleRate = 10000;
  int packetLen = 100000;
  List<int> initialSamples = [];

  @override
  void initializeSerial(Board board, double drawSurfaceWidth, {int expansionBoardChannelCount = 0}) {
    if (!_isInitialized) {}
    final result = pb.processingBindings.init();
    channelCount = int.parse(board.maxNumberOfChannels!) + expansionBoardChannelCount;
    print("Initialize Serial === $channelCount $expansionBoardChannelCount");
    _channelCount = channelCount;
    sampleRate = int.parse(board.maxSampleRate!);
    _sampleRate = sampleRate;
    packetLen = sampleRate * MAX_DISPLAY_SECONDS;
    
    // print("Initialize Serial === $result $channelCount $sampleRate -- PACKET LEN : $packetLen");
    ProcessingUtil.drawingBuffers.clear();
    for (int i = 0; i < channelCount; i++) {
      ProcessingUtil.drawingBuffers
          .add(Int16List(drawSurfaceWidth.toInt() * 5));
      ProcessingUtil.drawingBufferCounts.add(drawSurfaceWidth.toInt() * 5);
    }

    // int res = ProcessingBindings.instance.setBitsPerSample(board.sampleResolution!);
    print(
        "Initialize Serial === $channelCount $sampleRate -- PACKET LEN : $packetLen ${ProcessingUtil.drawingBuffers.length}");
    pb.processingBindings.setChannelCount(channelCount);
    pb.processingBindings.setSampleRate(sampleRate);

    inEventIndicesPtr = calloc<Int32>(ProcessingUtil.MAX_EVENT_MARKERS);
    inEventLabelsPtr = calloc<Int32>(ProcessingUtil.MAX_EVENT_MARKERS);
    ProcessingUtil.currentEventMarkers = 0;
    initEventMarkers(_sampleRate);
    ProcessingUtil.eventMarkerNotifier.removeListener(eventMarkerListener);
    ProcessingUtil.eventMarkerNotifier.addListener(eventMarkerListener);
  }

  @override
  Future<List<Int16List>> processSerialData(Uint8List samples, int displayTimeMs,
      int deviceType, int drawSurfaceWidth,
      [GraphDataProvider? provider]) async {
    // print("samples : $samples | channelCount : $channelCount | drawSurfaceWidth: $drawSurfaceWidth");
    var outSamplesPtr = calloc<Pointer<Int16>>(channelCount);
    for (int i = 0; i < channelCount; i++) {
      outSamplesPtr[i] = calloc<Int16>(drawSurfaceWidth * 5); // 5x for envelope
    }
    // print("END samples : $samples | channelCount : $channelCount");

    final outSampleCountsPtr = calloc<Int32>(channelCount);

    // try {
    // Prepare input data pointer
    final inDataPtr = calloc<Uint8>(samples.length);
    // if (initialSamples.isEmpty) {
    //   for (int i = 0; i < 10; i++) {
    //     initialSamples.addAll([255,255,1,1,128,255]);
    //     initialSamples.addAll([0,10 * i,0,20 * i]);
    //     // initialSamples.addAll([0,10 * i,0,20 * i]);
    //     // initialSamples.addAll([0,10 * i,0,20 * i]);
    //     initialSamples.addAll([255,255,1,1,129,255]);
    //   }
    // }
    for (int i = 0; i < samples.length; i++) {
      inDataPtr[i] = samples[i];
      // inDataPtr[i] = initialSamples[i]; PROCESS SERIAL DATA ERROR START
    }
    // print("PROCESS SERIAL DATA ERROR START ChannelCount: $channelCount -- Samples: ${samples.length} -- drawSurfaceWidth: $drawSurfaceWidth");
    int res = pb.processingBindings.processSampleStream(outSamplesPtr,
        outSampleCountsPtr, inDataPtr, samples.length, deviceType);
    // print("PROCESS SERIAL DATA ERROR END RES: $res");
    // return [Int16List(0), Int16List(0)];
    int minCounter = 100000;
    List<Int16List> buffer =[];
    // if (res != 0) {
      for (int i = 0; i < channelCount; i++) {
        minCounter = min(outSampleCountsPtr[i], minCounter);
        Int16List temp = outSamplesPtr[i].asTypedList(outSampleCountsPtr[i]);
        Int16List arr = Int16List(outSampleCountsPtr[i]);
        arr.setAll(0, temp);
        buffer.add(arr);
      }
    // }
    // Int32List sampleCount = outSampleCountsPtr.asTypedList(channelCount);
    // provider.inputListener(outSamplesPtr[0].asTypedList(sampleCount).buffer.asUint8List());
    // if (samples.reduce(max) > 250) {
    //   print("RES : $res - $samples === ${samples.length} @@@ : [1]=> $list [2]=> $list2");
    // }
    // print("RES : $res - ${samples.length} : == ");
      // Free input data memory
    calloc.free(inDataPtr);
    int frameCount = minCounter;
    int removedIndicesCount = 0;
    // print("RES : ${inEventIndicesPtr![0]} - ${samples.length} : == ");
    for (int i = 0; i < ProcessingUtil.currentEventMarkers; i++) {
      if (inEventIndicesPtr![i] - frameCount > 0) {
        inEventIndicesPtr![i] -= frameCount;
        ProcessingUtil.eventPosition[i] = inEventIndicesPtr![i];

      } else {
        if (inEventIndicesPtr![i] != -1) {
          removedIndicesCount++;
          inEventIndicesPtr![i] = -1;
        }
      }
    }

    for (int i = 0; i < removedIndicesCount; i++) {
      if (inEventIndicesPtr![i] == -1) {
        // print(
        //     "INDEX: $i -- $removedIndicesCount __ ${inEventIndicesPtr![i]} : ${ProcessingUtil.eventLabels} @@ ${inEventIndicesPtr!.asTypedList(ProcessingUtil.currentEventMarkers)}");
        if (ProcessingUtil.eventLabels.isNotEmpty) {
          ProcessingUtil.eventLabels.removeAt(0);
          ProcessingUtil.eventPosition.removeAt(0);
        }
      }
    }
    
    int tempCurrentEvent = ProcessingUtil.currentEventMarkers;
    ProcessingUtil.currentEventMarkers -= removedIndicesCount;
    if (inEventIndicesPtr != null && inEventIndicesPtr![0] == -1) {
      int eventPositionLen = ProcessingUtil.eventLabels.length;
      for (int i = eventPositionLen; i >= 0; i--) {
        inEventIndicesPtr![i] = ProcessingUtil.eventPosition[i];
      }
      for (int i = eventPositionLen; i < tempCurrentEvent; i++) {
        inEventIndicesPtr![i] = (ProcessingUtil.MAX_DISPLAY_SECONDS * _sampleRate).floor();
      }
    }

    // return;
    // }catch (err) {
    //   print("err process Sample Stream");
    //   print(err);
    // }
    for (int i = 0; i < channelCount; i++) {
      calloc.free(outSamplesPtr[i]);
    }
    calloc.free(outSamplesPtr);
    calloc.free(outSampleCountsPtr);
    return Future.value(buffer);
  }

  @override
  Future<Uint8List> processDisplaySerialData(
      int displayTimeMs,
      int deviceType,
      int drawSurfaceWidth,
      GraphDataProvider? provider,
      int startPositionIdx,
      int endPositionIdx) async {
    // Allocate memory for sample counts
    ProcessingUtil.fromDrawingIdx = startPositionIdx;
    ProcessingUtil.toDrawingIdx = endPositionIdx;

    
    var outSamplesPtr = calloc<Pointer<Int16>>(channelCount);
    final outSampleCountsPtr = calloc<Int32>(channelCount);
    for (int i = 0; i < channelCount; i++) {
      outSamplesPtr[i] = calloc<Int16>(drawSurfaceWidth * 5); // 5x for envelope
    }

    // Allocate memory for event indices (assuming max 100 events)
    final outEventIndicesPtr = calloc<Float>(100);

    // Allocate memory for event count
    final outEventCountPtr = calloc<Int32>(1);

    // Allocate and prepare input event indices
    // final inEventIndicesPtr = calloc<Int32>(0); // No events yet
    // print("drawSurfaceWidth : $drawSurfaceWidth");
    try {
      
      // return Future.value(Uint8List(0));
      // print("PREPARE FOR SIGNAL DRAWING - Start Channel Count $channelCount");
      int result = pb.processingBindings.prepareForSignalDrawing(
          outSamplesPtr, // Pointer<Pointer<Float>>
          outSampleCountsPtr, // Pointer<Int32>
          outEventIndicesPtr, // Pointer<Float>
          outEventCountPtr, // Pointer<Int32>
          inEventIndicesPtr!, // Pointer<Int32>
          ProcessingUtil.currentEventMarkers, // int (inEventCount)
          // 0,                       // int (fromSample)
          // (displayTimeMs*0.001 * sampleRate * 1).toInt(),  // int (toSample)
          startPositionIdx, // int (fromSample)
          endPositionIdx, // int (toSample)
          drawSurfaceWidth // int
          );
    
      if (result == 0) {
        // print("startPositionIdx : $startPositionIdx");
        int sampleCount = outSampleCountsPtr.value;
        int eventCount = outEventCountPtr.value;
        if (eventCount > 0) {
          // Float32List eventIndices = outEventIndicesPtr.asTypedList(eventCount);
        }

        for (int i = 0; i < channelCount; i++) {
          final temp = outSamplesPtr[i].asTypedList(sampleCount);
          // final arrDouble = List.generate(sampleCount, (index) => temp[index].toDouble());
          ProcessingUtil.drawingBuffers[i].setAll(0, temp);
          ProcessingUtil.drawingBufferCounts[i] = sampleCount;
        }

        DraggableGraph.eventMarkersPosition.clear();
        DraggableGraph.eventMarkersLabels.clear();
        var tempList =
            outEventIndicesPtr.asTypedList(ProcessingUtil.eventLabels.length);
        // print(
        //     "tempList: $tempList --- ${ProcessingUtil.currentEventMarkers}");
        for (double temp in tempList) {
          DraggableGraph.eventMarkersPosition.add(temp);
        }

        int len = ProcessingUtil.eventLabels.length;
        int startPositionIdx = DraggableGraph.startPositionIdx;
        int endPositionIdx = DraggableGraph.endPositionIdx;
        for (int i = 0; i < len; i++) {
          if (ProcessingUtil.eventPosition[i] >= startPositionIdx && ProcessingUtil.eventPosition[i] <= endPositionIdx ) {
            DraggableGraph.eventMarkersLabels.add(ProcessingUtil.eventLabels[i]);
          }
        }
        // print("RANGE : $startPositionIdx - $endPositionIdx");
        //provider.inputListener(channelData);
        // Get the number of events
      }
      for (int i = 0; i < channelCount; i++) {
        calloc.free(outSamplesPtr[i]);
      }
      calloc.free(outSamplesPtr);

      calloc.free(outSampleCountsPtr);
      calloc.free(outEventIndicesPtr);
      calloc.free(outEventCountPtr);
      // calloc.free(inEventIndicesPtr);
    } catch (err) {
      print("err");
      print(err);
    } finally {}
    return Future.value(Uint8List(0));
  }

  void processSerialDataIsolate(sendPort) async {
    ReceivePort receivePort = ReceivePort();
    sendPort.send(receivePort.sendPort); // Send the isolate's SendPort back

    receivePort.listen((args) async {
      if (args is List) {
        // int data =
        //     await processSerialData(args[0], args[1], args[2], args[3], null);

        // // Send the result back to the main isolate
        // sendPort.send(data);
      } else if (args == 'exit') {
        receivePort.close();
      }
    });
    // return Future.value(1);
  }

  void processDisplaySerialDataIsolate(sendPort) async {
    ReceivePort receivePort = ReceivePort();
    sendPort.send(receivePort.sendPort); // Send the isolate's SendPort back

    receivePort.listen((args) async {
      if (args is List) {
        // Uint8List data = await processDisplaySerialData(args[0], args[1], args[2],0,0);

        // Send the result back to the main isolate
        // sendPort.send(data);
      } else if (args == 'exit') {
        receivePort.close();
      }
    });
    // Uint8List data = await displaySerialData(args[0], args[1], args[2], args[3]);
    // print("displaySerialDataIsolate $data");
    // return Future.value(data);
  }

  @override
  Map<String, dynamic> getInformation() {
    final outInfoPtr = calloc<Int32>(10);
    pb.processingBindings.getInformation(outInfoPtr);
    Map<String, dynamic> map = {};
    final info = outInfoPtr.asTypedList(10);
    map["current_sample_rate"] = info[0];
    map["current_channel_count"] = info[1];
    map["current_bits_per_sample"] = info[2];
    map["current_selected_channel"] = info[3];

    calloc.free(outInfoPtr);
    return map;
  }

  void initEventMarkers(int sampleRate) {
    if (inEventIndicesPtr != null) {
      calloc.free(inEventIndicesPtr!);
      calloc.free(inEventLabelsPtr!);
      inEventIndicesPtr = calloc<Int32>(ProcessingUtil.MAX_EVENT_MARKERS);
      inEventLabelsPtr = calloc<Int32>(ProcessingUtil.MAX_EVENT_MARKERS);
      // ProcessingUtil.eventPosition.clear();
      // for (int i = 0; i < ProcessingUtil.MAX_EVENT_MARKERS; i++) {
      //   ProcessingUtil.eventPosition.add(0);
      // }
      ProcessingUtil.eventPosition = List.generate(ProcessingUtil.MAX_EVENT_MARKERS, (generator) => sampleRate * 10);
      for (int i = 0; i < ProcessingUtil.MAX_EVENT_MARKERS; i++) {
        inEventIndicesPtr![i] = sampleRate * 10;
      }
    } else {
      // Allocate if null before accessing
      inEventIndicesPtr = calloc<Int32>(ProcessingUtil.MAX_EVENT_MARKERS);
      inEventLabelsPtr = calloc<Int32>(ProcessingUtil.MAX_EVENT_MARKERS);
      ProcessingUtil.eventPosition = List.generate(ProcessingUtil.MAX_EVENT_MARKERS, (generator) => sampleRate * 10);
      for (int i = 0; i < ProcessingUtil.MAX_EVENT_MARKERS; i++) {
        inEventIndicesPtr![i] = sampleRate * 10;
      }
    }
    // print(
    //     "inEventIndicesPtr : ${inEventIndicesPtr!.asTypedList(ProcessingUtil.MAX_EVENT_MARKERS)}");
  }

  void eventMarkerListener() {
    List<int> list = ProcessingUtil.eventMarkerNotifier.value;
    if (list[0] == -1) return;
    ProcessingUtil.currentEventMarkers =
        (ProcessingUtil.currentEventMarkers + 1) %
            ProcessingUtil.MAX_EVENT_MARKERS;

    if (ProcessingUtil.currentEventMarkers > ProcessingUtil.MAX_EVENT_MARKERS) {
      ProcessingUtil.currentEventMarkers = 0;
    }
    inEventLabelsPtr![ProcessingUtil.currentEventMarkers] = list[0];
    if (list[1] != -1) {
      inEventIndicesPtr![ProcessingUtil.currentEventMarkers] = list[1];
    }

    ProcessingUtil.eventLabels.add(list[0]);
    // print("ADD LISTENER :  ${ProcessingUtil.eventLabels} === ${ProcessingUtil.eventPosition}");
  }
  
  bool isThresholdBufferInitialized = false;
  @override
  List<int> processThresholdData(List<Int16List> data, int thresholdChannelCount, int drawSurfaceWidth, int selectedChannel, bool isAverageSamples) {

    final inSampleCountsPtr = calloc<Int32>(thresholdChannelCount);
    final outSampleCountsPtr = calloc<Int32>(thresholdChannelCount);
    final outSamplesPtr = calloc<Pointer<Int16>>(thresholdChannelCount);
    // print("TempArrayData: $data");
    Int16List tempArrayData = data[0];
    // Int16List tempArrayData = Int16List.view(data.buffer);
    final frameCount = tempArrayData.length;

    for (int i = 0; i < thresholdChannelCount; i++) {
      inSampleCountsPtr[i] = (frameCount);
      outSamplesPtr[i] = calloc<Int16>( (_sampleRate * ProcessingUtil.MAX_DISPLAY_SECONDS / 2).floor() ); // 5x for envelope
    }

    try {
      // Prepare input data pointer
      // int defaultChannelIndex = 1;
      final inDataPtr = calloc<Pointer<Int16>>(thresholdChannelCount);
      for (int i = 0; i < thresholdChannelCount; i++) {
        inDataPtr[i] = calloc<Int16>( frameCount );
        for (int j = 0; j < frameCount; j++) {
          inDataPtr[i][j] = data[i][j];
        }
      }
      // print("inDataPtr: ");

      // Process the microphone data using pre-allocated buffer
      final inEventLabelsPtr = calloc<Int32>(ProcessingUtil.eventLabels.length);
      final inEventPositionPtr = calloc<Int32>(ProcessingUtil.eventLabels.length);
      for (int i = 0; i < ProcessingUtil.eventLabels.length;  i++) {
        inEventPositionPtr[i] = _sampleRate * 10 - ProcessingUtil.eventPosition[i] - frameCount;
        inEventLabelsPtr[i] = ProcessingUtil.eventLabels[i];
      }

      // print("inEventLabelsPtr: ");
      final result = pb.processingBindings.processThreshold(
          outSamplesPtr, outSampleCountsPtr, inDataPtr, inSampleCountsPtr, inEventPositionPtr, inEventLabelsPtr,ProcessingUtil.eventLabels.length, isAverageSamples);

      if (result != 0) {
        print('Failed to process microphone data: $result');
      }

      // Free input data memory
      int tempArrayCount = outSampleCountsPtr[0];
      // print("tempArrayCount: ");
      calloc.free(outSampleCountsPtr);
      // calloc.free(inDataPtr);
      for (int i = 0; i < thresholdChannelCount; i++) {
        calloc.free(inDataPtr[i]);
        calloc.free(outSamplesPtr[i]);
      }
      calloc.free(inDataPtr);
      calloc.free(outSamplesPtr);
      calloc.free(inSampleCountsPtr);
      calloc.free(inEventLabelsPtr);
      // print("tempArrayCount: $tempArrayCount");
      return [tempArrayCount];
    } catch(err){
      print("err: $err");
    }
    finally {
    }    
    return [];
  }
  
  @override
  void initThreshold(int channelCount, int sampleRate, double drawSurfaceWidth) {
    pb.processingBindings.init();
    pb.processingBindings.setChannelCount(channelCount);
    pb.processingBindings.setSampleRate(sampleRate);
  }
  
  @override
  void setThresholdTriggerType(int eventThresholdTriggeredType) {
    // print("setThresholdTriggerType: ${listMenuOptions.indexOf(eventThresholdTriggeredType)}");
    pb.processingBindings.setAveragingTriggerType(eventThresholdTriggeredType);
  }
  
  @override
  void setIsThresholding(bool flag) {
    pb.processingBindings.setIsThresholding(flag);
  }

  @override
  int thresholdingArraylength = 1;
  
  @override
  List<Float32List> out_fft = [];
  
  @override
  List<int> window_count = [];
  
  @override
  List<int> window_size = [];
  

  Pointer<Pointer<Float>>? out_fft_data;
  Pointer<Float>? out_fft_vertices;
  Pointer<Int16>? out_fft_indices;
  Pointer<Float>? out_fft_colors;
  Pointer<Int32>? out_fft_vertex_count;
  Pointer<Int32>? out_fft_index_count;
  Pointer<Int32>? out_fft_color_count;
  
  List<Float32List> fft = List.generate(500, (idx)=>Float32List(500));

  
  @override
  // void processFftData(Int16List inSamples, List<int> inSampleCounts) {
  void processFftMicrophoneData(List<Int16List> in_samples, List<int> windowCount, List<int> windowSize, List<int> in_sample_counts, int channelCount) async {
    // print("processFftMicrophoneData EXIST");
    if (windowCount.isNotEmpty) {
      window_count.clear();
      window_count.addAll(windowCount);
      window_size.clear();
      window_size.addAll(windowSize);
    }

    Pointer<Int32> out_window_count;
    Pointer<Int32> out_window_size;
    Pointer<Int32> out_frequency_counter;
    int selectedChannel = 0;
    
    if (out_fft_data == null) {
      // print("FFT DATA POINTER EXIST : ${windowCount[selectedChannel]} --- ${windowSize[0]}");
      out_fft_data = calloc<Pointer<Float>>(windowCount[selectedChannel]);

      for (int i = 0; i < windowCount[selectedChannel]; i++) {
        out_fft_data![i] = calloc<Float>(windowSize[0]);
      }
      out_fft.clear();
      out_fft = List<Float32List>.generate(windowCount[selectedChannel], (idx)=> Float32List(windowSize[selectedChannel]));
    }

    // print("OUT FFT DATA PARAMS : ${windowCount[0]} --- ${windowSize[0]}");


    out_window_count = calloc<Int32>(channelCount);
    // out_window_count.asTypedList(channelCount).setAll(0, windowCount);
    out_window_size = calloc<Int32>(channelCount);
    out_frequency_counter = calloc<Int32>(channelCount);

    int signs = -1;
    Pointer<Pointer<Int16>> inSamples = calloc<Pointer<Int16>>(channelCount);
    for (int i = 0; i < channelCount; i++) {
      int sampleCount = in_sample_counts[i];
      inSamples[i] = calloc<Int16>(sampleCount);
      signs = signs * -1;
      for (int j = 0; j < sampleCount; j++) {
        inSamples[i][j] = in_samples[i][j];
        // inSamples[i][j] = (Random().nextInt(100) + 100) * signs;
      }
    }
    Pointer<Int32> inSampleCounts = calloc<Int32>(channelCount);
    for (int i = 0; i < channelCount; i++) {
      inSampleCounts[i] = in_sample_counts[i];
    }


    int res = pb.processingBindings.processFft(out_fft_data!, out_window_count, out_window_size, out_frequency_counter, inSamples, inSampleCounts);    

    // resync the fft with out fft, 
    
    window_count.setAll(0, out_window_count.asTypedList(channelCount));
    window_size.setAll(0, out_window_size.asTypedList(channelCount));

    if (window_count[0] > 0) {
      // print("WINDOW COUNT = $window_count || $windowCount || ${out_window_count[0]}");
      // print("WINDOW SIZE = $window_size || $windowSize || ${out_window_size[selectedChannel]}");
      // copy out_fft_temp to out_fft
      int windowCounter = out_window_count[selectedChannel];
      // print("out_window_count: $windowCounter");
      for (int i = 0; i < windowCounter; i++) {
        int outSize = out_window_count[0];
        // print("WINDOW SIZE: $windowSize");
        Float32List out_fft_list = out_fft_data![i].asTypedList(windowSize[0]);
        out_fft[i].setAll(0, out_fft_list);
        // print("out_FFT : $out_fft_list");
        // out_fft[i].setAll(0, out_fft_temp[i].asTypedList(windowCount));
        fftBuffer.put(out_fft, 0, windowCounter);
      }
      // ProcessingUtil.fftDrawBuffer = FftDrawBuffer(windowCount[selectedChannel], windowSize[selectedChannel]);
      // free memory
      // for (int i = 0; i < channelCount; i++) {
      //   calloc.free(out_fft_data![i]);
      // }
      // calloc.free(out_fft_data!);
    }

    // free memory

    for (int i = 0; i < channelCount; i++) {
      calloc.free(inSamples[i]);
    }
    calloc.free(inSamples);

    calloc.free(out_window_count);
    calloc.free(out_window_size);
    calloc.free(out_frequency_counter);
    calloc.free(inSampleCounts);

  }

Int32List convertRgbaFloat32ListToInt32(Float32List fftColorList, Int32List outColorList) {
  // Ensure the input list has a multiple of 4 elements (R, G, B, A).
  if (fftColorList.length % 4 != 0) {
    print("The RGBA color list must have a length that is a multiple of 4.");
    // throw ArgumentError('The RGBA color list must have a length that is a multiple of 4.');
  }

  final int colorCount = fftColorList.length ~/ 4;

  for (int i = 0; i < colorCount; i++) {
    // Read the four float components (R, G, B, A)
    double R = fftColorList[i * 4];
    double G = fftColorList[i * 4 + 1];
    double B = fftColorList[i * 4 + 2];
    double A = fftColorList[i * 4 + 3];
    
    int r = (R * 255).round();
    int g = (G * 255).round();
    int b = (B * 255).round();
    int a = (A * 255).round();   
    outColorList[i] = (a << 24) | (r << 16) | (g << 8) | b;
  }

  return outColorList;
}  

// int32_t processing_prepare_fft_for_drawing(float* out_vertices, int16_t* out_indices,
//                                          float* out_colors, int32_t* out_vertex_count,
//                                          int32_t* out_index_count, int32_t* out_color_count,
//                                          float** fft_data, int32_t window_count,
//                                          int32_t window_size, float width, float height) {
  @override
  int prepareForFftDrawing(int windowCount, int windowSize, int targetWindowCount, double width, double height){
    if (out_fft_vertices != null && out_fft_indices != null && out_fft_colors != null 
        && out_fft_vertex_count != null && out_fft_index_count != null && out_fft_color_count != null 
          && out_fft_data != null){
      // print("PREPARE FFT DRAWING : ${windowCount} -- ${windowSize} ||| ${width} ___ ${height}");
      // if (out_fft_color_count![0] != 0) {
        int selectedChannelIdx = 0;
        int maxWindowCount = out_fft.length;
        int count = fftBuffer.get(fft);

        if (count > 0) {
          ProcessingUtil.fftDrawBuffer!.add(fft, count);

          Pointer<Pointer<Float>> drawBuffer = calloc<Pointer<Float>>(windowCount);
          int len = ProcessingUtil.fftDrawBuffer!.buffer[0].length;
          for (int i = 0; i < windowCount; i++) {
            drawBuffer[i] = calloc<Float>(len);
            drawBuffer[i].asTypedList(len).setAll(0, ProcessingUtil.fftDrawBuffer!.buffer[i]);
          }
          // return -1;


          pb.processingBindings.prepareFftDrawing(
            out_fft_vertices!, out_fft_indices!, out_fft_colors!, 
            out_fft_vertex_count!, out_fft_index_count!, out_fft_color_count!,
            drawBuffer, windowCount, windowSize, targetWindowCount,width, height);
            // out_fft_data!, windowCount, windowSize, width, height);

          // out_fft.clear();
          // for (int i = 0; i < windowCount; i++) {
          //   out_fft.add(fft_data[i].asTypedList(windowSize));
          // }

          int vertexCount = out_fft_vertex_count![selectedChannelIdx];
          int indicesCountRaw = out_fft_index_count![selectedChannelIdx];
          int indicesCount = indicesCountRaw;
          int colorCountRaw = out_fft_color_count![selectedChannelIdx];
          int colorCount = out_fft_color_count![selectedChannelIdx] ~/ 4;
          Int32List colorList = Int32List(colorCount);
          Float32List fftColorList = out_fft_colors!.asTypedList(colorCountRaw);
          Int16List indicesList = out_fft_indices!.asTypedList(indicesCountRaw);

          convertRgbaFloat32ListToInt32(fftColorList, colorList);
          out_fft_colors!.asTypedList(channelCount);
          // Counter: 65536, 194310, 32768 | 131072 194310
          // print("Counter: $vertexCount, $indicesCount, $colorCount | $colorCountRaw $indicesCountRaw");
          // print("Color List: $colorList"); -16777088, -16777088,
 
          // print("VertexCount: $vertexCount");
          // print("IndexCount: $indicesCountRaw");
          // print("ColorCount: $colorCount ?==? ${colorList.length}");
          // print(out_fft_indices!.asTypedList(indicesCount).length);
          // out_fft_vertices!.asTypedList(vertexCount).fillRange(0, 10, (Random().nextDouble() * 10) );
          // out_fft_vertices![0] = (Random().nextDouble() * 100);
          // out_fft_vertices![1] = (Random().nextDouble() * 100);
          // out_fft_vertices![2] = (Random().nextDouble() * 100);
          // out_fft_vertices![3] = (Random().nextDouble() * 100);
          // out_fft_vertices![4] = (Random().nextDouble() * 100);
          // out_fft_vertices![5] = (Random().nextDouble() * 100);
          // out_fft_vertices![6] = (Random().nextDouble() * 100);
          // out_fft_vertices![7] = (Random().nextDouble() * 100);
          // print("vertexList.sublist(0, 20): ${out_fft_vertices!.asTypedList(vertexCount).sublist(0, 20)}");
          // print("indicesList.sublist(0, 20): ${indicesList.sublist(0, 20)}");
          
          ProcessingUtil.fftDrawData = FftDrawData(
              vertices: out_fft_vertices!.asTypedList(vertexCount), colors: colorList, 
              indices: out_fft_indices!.asTypedList(indicesCount).buffer.asUint16List(), 
              vertexCount: vertexCount, 
              colorCount: colorList.length, 
              indexCount: indicesCount, 
              scaleX: 1, scaleY: 1);          

          for (int i = 0; i < windowCount; i++) {
            calloc.free(drawBuffer[i]);
          }
          calloc.free(drawBuffer);

        }



    }
    return 0;
  }
  
  void initFft() {
    int windowCount = ( (10.0 * 128) / (512 * 0.01).floor() ).floor();
    int windowSize = ( (32 * 4) ).floor();

    out_fft_vertices = calloc<Float>(windowCount * windowSize * 2);
    out_fft_indices = calloc<Int16>(windowCount * windowSize * 6);
    out_fft_colors = calloc<Float>(windowCount * windowSize * 4);
    print("FFT VERTICES : ${windowCount * windowSize * 2}");
    print("FFT INDICES : ${windowCount * windowSize * 6}");
    print("FFT COLORS : ${windowCount * windowSize * 5}");

    ProcessingUtil.fftDrawBuffer = FftDrawBuffer(windowCount, windowSize);
    try{
      out_fft_vertex_count = calloc<Int32>(1);
      out_fft_index_count = calloc<Int32>(1);
      out_fft_color_count = calloc<Int32>(1);

      out_fft_vertex_count![0] = 0;
      out_fft_index_count![0] = 0;
      out_fft_color_count![0] = 0;

    }catch(err) {
      print("err $err");
    }
  }
  
  @override
  void onCallbackPrepareFftDrawingWeb(int resultFftDraw, int selectedChannelIdx) {
  }
  
  @override
  void processingNwbFileInjectData(Int16List data, Int32List sampleCounts, int selectedChannel, int channelCount) {
    Pointer<Int16> inDataPtr = calloc<Int16>(data.length);
    inDataPtr.asTypedList(data.length).setAll(0, data);
    
    Pointer<Int32> sampleCountPtr = calloc<Int32>(channelCount);
    sampleCountPtr.asTypedList(channelCount).setAll(0, sampleCounts);

    pb.processingBindings.nwbfileInjectDataResult(inDataPtr, sampleCountPtr, selectedChannel, channelCount);

    calloc.free(inDataPtr);
    calloc.free(sampleCountPtr);    
  }
  
  @override
  void processingSerialDataResult(Int16List data, Int32List sampleCounts, int channelCount) {
    Pointer<Int16> inDataPtr = calloc<Int16>(data.length);
    inDataPtr.asTypedList(data.length).setAll(0, data);
    Pointer<Int32> sampleCountsPtr = calloc<Int32>(sampleCounts.length);
    sampleCountsPtr.asTypedList(sampleCounts.length).setAll(0, sampleCounts);

    // print("Sample Count  0 : ${sampleCounts[0]} | Channel Count 1 : ${sampleCounts[1]} || Data Length : ${data.length}");
    // print("Channel Value 0 : ${data[0]} | Channel Value 1 : ${data[sampleCounts[1]]}");
    // print("DATA : $data");

    pb.processingBindings.processSerialDataResult(inDataPtr, sampleCountsPtr, channelCount);
    
    calloc.free(inDataPtr);
    calloc.free(sampleCountsPtr);
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
      final result = pb.processingBindings.filterData(pointer, length);
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

// void dartCallback(int value) {
//   print('Dart callback received from C++: $value');
// }

// typedef DartCallbackNative = Void Function(Int32);
// typedef DartCallbackDart = void Function(int);

// final dartCallbackPointer = Pointer.fromFunction<DartCallbackNative>(dartCallback);



Int16List uint8ListToInt16List(Uint8List uint8List, {Endian endian = Endian.little}) {
  if (uint8List.length % 2 != 0) {
    throw ArgumentError("Uint8List length must be an even number for Int16List conversion.");
  }

  final ByteData byteData = uint8List.buffer.asByteData(uint8List.offsetInBytes, uint8List.lengthInBytes);

  final int numInt16 = uint8List.length ~/ 2;
  final Int16List int16List = Int16List(numInt16);

  for (int i = 0; i < numInt16; i++) {
    int16List[i] = byteData.getInt16(i * 2, endian);
  }

  return int16List;
}

// PROCESSING_API int32_t processing_process_fft(float** out_fft, int32_t* out_window_count,
//                              int32_t* out_window_size, const int16_t** in_samples,
//                              const int32_t* in_sample_counts);

