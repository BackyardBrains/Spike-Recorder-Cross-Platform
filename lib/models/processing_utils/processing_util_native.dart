import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart';
import 'package:spikerbox_architecture/models/default_config_model.dart';
import 'package:spikerbox_architecture/provider/graph_stream_data.dart';
import 'processing_util.dart';
import 'processing_bindings.dart';

// Message class for communication between isolates
class ProcessingMessage 
{
	final String type;
	final dynamic data;

	ProcessingMessage(this.type, this.data);
}

class ProcessingUtilImpl implements ProcessingUtil 
{

	Isolate? _processingIsolate;
	SendPort? portMainToProcessingIsolate;
	ReceivePort? portProcessingIsolateToMain;
	final _dataController = StreamController<dynamic>.broadcast();
	bool _isInitialized = false;
	int _sampleRate = 44100;
	int _channelCount = 1;

  	// Implementation of the data buffer
	@override
	// Pointer<Pointer<Int16>>? currentDataBuffer;
	  var currentDataBuffer;

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
		final sampleRateResult = ProcessingBindings.instance.setSampleRate(44100);
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
	Future<bool> initializeMicrophone(int channelCount, int sampleRate) async 
	{
		if (!_isInitialized) {
			await init();
		}
		//todo: check if the currentDataBuffer is already initialized. If yes free memory before reinitializing
		if (currentDataBuffer != null) {
			for (int i = 0; i < _channelCount; i++) {
				calloc.free((currentDataBuffer!.value + i).cast<Pointer<Int16>>().value);
			}
			calloc.free(currentDataBuffer!.value);
			calloc.free(currentDataBuffer!);
		}
		// Update local properties
		_channelCount = channelCount;
		_sampleRate = sampleRate;

		// Set channel count and sample rate in C++ processing
		final channelResult = ProcessingBindings.instance.setChannelCount(channelCount);
		if (channelResult != 0) {
			print('Failed to set channel count: $channelResult');
			return false;
		}

		final sampleRateResult = ProcessingBindings.instance.setSampleRate(sampleRate);
		if (sampleRateResult != 0) {
			print('Failed to set sample rate: $sampleRate');
			return false;
		}

		// Pre-allocate the buffer memory
		final int sampleCount = (ProcessingUtil.MAX_DISPLAY_SECONDS * sampleRate).toInt();
		
		// Allocate array of pointers for each channel
		final channelArrayPtr = calloc<Pointer<Int16>>(channelCount);
		currentDataBuffer = channelArrayPtr.cast<Pointer<Int16>>();
		
		// Allocate memory for each channel
		for (int i = 0; i < channelCount; i++) {
			channelArrayPtr[i] = calloc<Int16>(sampleCount);
		}

		print('Microphone initialized with $channelCount channels at $sampleRate Hz');
		print('Buffer size: $channelCount channels × $sampleCount samples');
		
		return true;
	}


		@override
	List<Int16List> processMicrophoneData(Uint8List data) {
		if (!_isInitialized) {
			throw StateError('ProcessingUtil not initialized. Call init() first.');
		}

		final outSampleCountsPtr = calloc<Int32>();

		try {
			// Prepare input data pointer
			final inDataPtr = calloc<Uint8>(data.length);
			for (int i = 0; i < data.length; i++) {
				inDataPtr[i] = data[i];
			}

			// Process the microphone data using pre-allocated buffer
			final result = ProcessingBindings.instance.processMicrophoneStream(
				currentDataBuffer!, 
				outSampleCountsPtr, 
				inDataPtr, 
				data.length
			);

			// Free input data memory
			calloc.free(inDataPtr);

			if (result != 0) {
				throw Exception('Failed to process microphone data: $result');
			}

			// Create Dart view of the native memory
			final sampleCount = outSampleCountsPtr.value;
      Pointer<Pointer<Int16>> curDataBuffer = currentDataBuffer as Pointer<Pointer<Int16>>;
			final bufferViews = List<Int16List>.generate(
				_channelCount,
				(i) => (curDataBuffer.value + i).cast<Int16>().asTypedList(sampleCount)
			);

			return bufferViews;
		} finally {
			calloc.free(outSampleCountsPtr);
		}
	}

  @override
  Future<int> setBandFilter(double lowCutOffFreq, double highCutOffFreq) async {
    if (!_isInitialized) {
      await init();
    }
    return ProcessingBindings.instance.setBandFilter(lowCutOffFreq, highCutOffFreq);
  }

  @override
  Future<int> setNotchFilter(double centerFreq) async {
    if (!_isInitialized) {
      await init();
    }
    return ProcessingBindings.instance.setNotchFilter(centerFreq);
  }

  
	@override
	int prepareForSignalDrawingProcess(outSamples,
                                     outSampleCounts,
                                     outEventIndices,
                                     outEventCount,
                                     inEventIndices,
                                          int inEventCount,
                                          int fromSample,
                                          int toSample,
                                          int drawSurfaceWidth)
	{
		if (!_isInitialized) {
			throw StateError('ProcessingUtil not initialized. Call init() first.');
		}
		
		try {
			// Call the native function with correct parameters
			final result = ProcessingBindings.instance.prepareForSignalDrawing(
				outSamples,
        outSampleCounts,
				outEventIndices,
				outEventCount,
				inEventIndices,
        inEventCount,
				fromSample,
				toSample,
				drawSurfaceWidth
			);
			
			return result;
		} catch (e) {
			print('Error in prepareForSignalDrawing: $e');
			return -1;
		}
	}

	// Get the stream of processed data
	Stream<dynamic> get processedDataStream => _dataController.stream;

  	// Cleanup resources
	Future<void> dispose() async 
	{
		_processingIsolate?.kill();
		portProcessingIsolateToMain?.close();
		await _dataController.close();
		
		// Free allocated memory
    // try {
      if (currentDataBuffer != null) {
        for (int i = 0; i < _channelCount; i++) {
          calloc.free((currentDataBuffer!.value + i).cast<Pointer<Int16>>().value);
        }
        calloc.free(currentDataBuffer!.value);
        calloc.free(currentDataBuffer!);
        currentDataBuffer = null;
      }
    // }catch(err) {

    // }
		
		ProcessingBindings.instance.cleanup();
		_isInitialized = false;
	}
  
   @override
   List<Int16List> prepareDisplayMicrophoneData(List<Int16List> processedData, int drawSurfaceWidth, int channelCount, double displayTimeMs, GraphDataProvider provider) {
    if (processedData.isNotEmpty) {
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
        Float32List outSignal = Float32List(drawSurfaceWidth * 5); // 5x for envelope
        Int32List outEvents = Int32List(100); // Max 100 events
        
        // Allocate memory for output samples (array of float arrays)
        final outSamplesPtr = calloc<Pointer<Int16>>(channelCount);
        for (int i = 0; i < channelCount; i++) {
            outSamplesPtr[i] = calloc<Int16>(drawSurfaceWidth * 5); // 5x for envelope
        }

        // Allocate memory for sample counts
        final outSampleCountsPtr = calloc<Int32>(channelCount);

        // Allocate memory for event indices (assuming max 100 events)
        final outEventIndicesPtr = calloc<Float>(100);

        // Allocate memory for event count
        final outEventCountPtr = calloc<Int32>(1);

        // Allocate and prepare input event indices
        final inEventIndicesPtr = calloc<Int32>(0); // No events yet

        try {
            int result = prepareForSignalDrawingProcess(
                outSamplesPtr,           // Pointer<Pointer<Float>>
                outSampleCountsPtr,      // Pointer<Int32>
                outEventIndicesPtr,      // Pointer<Float>
                outEventCountPtr,        // Pointer<Int32>
                inEventIndicesPtr,       // Pointer<Int32>
                0,                       // int (inEventCount)
                0,                       // int (fromSample)
                (displayTimeMs*0.001 * _sampleRate).toInt(),  // int (toSample)
                drawSurfaceWidth         // int
            );

            if (result == 0) {
                // Copy the results back to Dart
                // Get the number of samples from outSampleCountsPtr
                int sampleCount = outSampleCountsPtr.value;
                //print("sampleCount: $sampleCount");
                // Copy the prepared signal data

                //for (int i = 0; i < widget.channelCount; i++) {
                Int16List channelData = outSamplesPtr[0].asTypedList(sampleCount);
                //print("Sample count: $sampleCount");
                //print("first sample: ${channelData[0]}");
                //se log with this:
                // cat /tmp/flutter_native_crash.log  
                

                Uint8List uint8Data = Uint8List.view(channelData.buffer);
                provider.inputListener(uint8Data);
                //provider.inputListener(channelData);
                // Get the number of events
                int eventCount = outEventCountPtr.value;
                if (eventCount > 0) {
                    // Copy event indices if needed
                    Float32List eventIndices = outEventIndicesPtr.asTypedList(eventCount);
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
            calloc.free(inEventIndicesPtr);
        }
    }    
     return processedData;
  }
   
  int MAX_DISPLAY_SECONDS = 10000;

  int channelCount = 1;
  int sampleRate = 10000;
  int packetLen = 100000;
  List<int> initialSamples = [];

  @override
  void initializeSerial(Board board) {
		if (!_isInitialized) {
		}  
    final result = ProcessingBindings.instance.init();    
    channelCount = int.parse(board.maxNumberOfChannels!);
    sampleRate = int.parse(board.maxSampleRate!);
    packetLen = sampleRate * MAX_DISPLAY_SECONDS;
    // print("Initialize Serial === $result $channelCount $sampleRate -- PACKET LEN : $packetLen");
    
    // int res = ProcessingBindings.instance.setBitsPerSample(board.sampleResolution!);
    print("Initialize Serial === $channelCount $sampleRate -- PACKET LEN : $packetLen");
    ProcessingBindings.instance.setChannelCount(channelCount);
    ProcessingBindings.instance.setSampleRate(sampleRate);
  }

  @override
  void processSerialData(Uint8List samples, int displayTimeMs, int deviceType, int drawSurfaceWidth, GraphDataProvider provider) {
    // print("SERIAL DATA: $channelCount - ${samples.length} : $drawSurfaceWidth -- $sampleRate : $displayTimeMs DEVICETYPE: $deviceType");
    var outSamplesPtr = calloc<Pointer<Int16>>(channelCount);
    for (int i = 0; i < channelCount; i++) {
      outSamplesPtr[i] = calloc<Int16>(drawSurfaceWidth * 5); // 5x for envelope
    }

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
        // inDataPtr[i] = initialSamples[i];
      }
      int res = ProcessingBindings.instance.processSampleStream(outSamplesPtr, outSampleCountsPtr, inDataPtr, samples.length, deviceType);
      var list = outSamplesPtr[0].asTypedList(100);
      Int32List sampleCount = outSampleCountsPtr.asTypedList(2);
      // provider.inputListener(outSamplesPtr[0].asTypedList(sampleCount).buffer.asUint8List());
      // print("RES : $res - ${samples.sublist(0,sampleCount[0])} : $list == $sampleCount");
      // print("RES : $res - ${samples.length} : == $sampleCount");
      calloc.free(inDataPtr);
      // return;
    // }catch (err) {
    //   print("err process Sample Stream");
    //   print(err);
    // }
    for (int i = 0; i < channelCount; i++) {
        calloc.free(outSamplesPtr[i]);
    }
    calloc.free(outSamplesPtr);


    // Allocate memory for sample counts
    outSamplesPtr = calloc<Pointer<Int16>>(channelCount);
    for (int i = 0; i < channelCount; i++) {
        outSamplesPtr[i] = calloc<Int16>(drawSurfaceWidth * 5); // 5x for envelope
    }

    // Allocate memory for event indices (assuming max 100 events)
    final outEventIndicesPtr = calloc<Float>(100);

    // Allocate memory for event count
    final outEventCountPtr = calloc<Int32>(1);

    // Allocate and prepare input event indices
    final inEventIndicesPtr = calloc<Int32>(0); // No events yet
    // print("drawSurfaceWidth : $drawSurfaceWidth");
    try {
      int result = ProcessingBindings.instance.prepareForSignalDrawing(
          outSamplesPtr,           // Pointer<Pointer<Float>>
          outSampleCountsPtr,      // Pointer<Int32>
          outEventIndicesPtr,      // Pointer<Float>
          outEventCountPtr,        // Pointer<Int32>
          inEventIndicesPtr,       // Pointer<Int32>
          0,                       // int (inEventCount)
          0,                       // int (fromSample)
          (displayTimeMs*0.001 * sampleRate * 1).toInt(),  // int (toSample)
          drawSurfaceWidth         // int
      );
      if (result == 0) {
        int sampleCount = outSampleCountsPtr.value;
        Int16List channelData = outSamplesPtr[0].asTypedList(sampleCount);
        // Uint8List uint8Data = Uint8List.view(channelData.buffer);
        Uint8List uint8Data = (channelData.buffer.asUint8List());
        // print("uint8Data $sampleCount");
        // print(uint8Data.sublist( uint8Data.length * 7 ~/ 8, uint8Data.length));
        // print(channelData.sublist(0, 30));
        // uint8Data.fillRange(0, (sampleCount * 1.99).toInt(), -77);
        provider.inputListener(uint8Data);
        int eventCount = outEventCountPtr.value;
        if (eventCount > 0) {
          // Float32List eventIndices = outEventIndicesPtr.asTypedList(eventCount);
        }
      }
      for (int i = 0; i < channelCount; i++) {
          calloc.free(outSamplesPtr[i]);
      }
      calloc.free(outSamplesPtr);

      calloc.free(outSampleCountsPtr);
      calloc.free(outEventIndicesPtr);
      calloc.free(outEventCountPtr);
      calloc.free(inEventIndicesPtr);      

    }catch(err) {
      print("err");
      print(err);
    } finally {
    }

  }


  @override
  Map<String, dynamic> getInformation() {
    final outInfoPtr = calloc<Int32>(10);
    ProcessingBindings.instance.getInformation(outInfoPtr);
    Map<String, dynamic> map = {};
    final info = outInfoPtr.asTypedList(10);
    map["current_sample_rate"] = info[0];
    map["current_channel_count"] = info[1];
    map["current_bits_per_sample"] = info[2];
    map["current_selected_channel"] = info[3];

    calloc.free(outInfoPtr);
    return map;
  }

}


// This function runs in the processing isolate
void _processingIsolateFunction(SendPort portToMain) 
{
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
dynamic _processData(dynamic data) 
{
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
