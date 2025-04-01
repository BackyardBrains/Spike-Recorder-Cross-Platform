import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ffi';
import 'package:ffi/ffi.dart';
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
	Pointer<Pointer<Int16>>? currentDataBuffer;

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
			final bufferViews = List<Int16List>.generate(
				_channelCount,
				(i) => (currentDataBuffer!.value + i).cast<Int16>().asTypedList(sampleCount)
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
	int prepareForSignalDrawingProcess( Pointer<Pointer<Int16>> outSamples,
                                          Pointer<Int32> outSampleCounts,
                                          Pointer<Float> outEventIndices,
                                          Pointer<Int32> outEventCount,
                                          Pointer<Int32> inEventIndices,
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
		if (currentDataBuffer != null) {
			for (int i = 0; i < _channelCount; i++) {
				calloc.free((currentDataBuffer!.value + i).cast<Pointer<Int16>>().value);
			}
			calloc.free(currentDataBuffer!.value);
			calloc.free(currentDataBuffer!);
			currentDataBuffer = null;
		}
		
		ProcessingBindings.instance.cleanup();
		_isInitialized = false;
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
