/**
 * @file electrical_series_dart_example.dart
 * @brief Dart/Flutter example for reading electrical series data from NWB files
 * 
 * This example shows how to interface with native C++ code to read electrical
 * series data in a Flutter application.
 */

import 'dart:ffi';
import 'dart:typed_data';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:path_provider/path_provider.dart';

/// Data structure to hold electrical series information
class ElectricalSeriesData {
  final Float32List voltageData;
  final Float64List timestamps;
  final Int32List electrodeIndices;
  final Float32List channelConversions;
  final String dataUnit;
  final int numSamples;
  final int numChannels;

  ElectricalSeriesData({
    required this.voltageData,
    required this.timestamps,
    required this.electrodeIndices,
    required this.channelConversions,
    required this.dataUnit,
    required this.numSamples,
    required this.numChannels,
  });

  /// Calculate sampling rate from timestamps
  double get samplingRate {
    if (timestamps.length < 2) return 0.0;
    return 1.0 / (timestamps[1] - timestamps[0]);
  }

  /// Get recording duration in seconds
  double get duration {
    if (timestamps.isEmpty) return 0.0;
    return timestamps.last - timestamps.first;
  }

  /// Get voltage data for a specific channel
  Float32List getChannelData(int channelIndex) {
    if (channelIndex >= numChannels || channelIndex < 0) {
      throw ArgumentError('Invalid channel index: $channelIndex');
    }

    Float32List channelData = Float32List(numSamples);
    for (int sample = 0; sample < numSamples; sample++) {
      channelData[sample] = voltageData[sample * numChannels + channelIndex];
    }
    return channelData;
  }

  /// Get data for a specific time range
  ElectricalSeriesData getTimeRange(double startTime, double endTime) {
    List<int> indices = [];
    for (int i = 0; i < timestamps.length; i++) {
      if (timestamps[i] >= startTime && timestamps[i] <= endTime) {
        indices.add(i);
      }
    }

    if (indices.isEmpty) {
      return ElectricalSeriesData(
        voltageData: Float32List(0),
        timestamps: Float64List(0),
        electrodeIndices: electrodeIndices,
        channelConversions: channelConversions,
        dataUnit: dataUnit,
        numSamples: 0,
        numChannels: numChannels,
      );
    }

    // Extract data for the time range
    Float32List rangeVoltageData = Float32List(indices.length * numChannels);
    Float64List rangeTimestamps = Float64List(indices.length);

    for (int i = 0; i < indices.length; i++) {
      int originalIndex = indices[i];
      rangeTimestamps[i] = timestamps[originalIndex];
      
      for (int ch = 0; ch < numChannels; ch++) {
        rangeVoltageData[i * numChannels + ch] = 
            voltageData[originalIndex * numChannels + ch];
      }
    }

    return ElectricalSeriesData(
      voltageData: rangeVoltageData,
      timestamps: rangeTimestamps,
      electrodeIndices: electrodeIndices,
      channelConversions: channelConversions,
      dataUnit: dataUnit,
      numSamples: indices.length,
      numChannels: numChannels,
    );
  }

  /// Calculate basic statistics for a channel
  Map<String, double> getChannelStats(int channelIndex) {
    Float32List channelData = getChannelData(channelIndex);
    
    if (channelData.isEmpty) {
      return {'min': 0.0, 'max': 0.0, 'mean': 0.0, 'std': 0.0};
    }

    double min = channelData[0];
    double max = channelData[0];
    double sum = 0.0;

    for (double value in channelData) {
      if (value < min) min = value;
      if (value > max) max = value;
      sum += value;
    }

    double mean = sum / channelData.length;
    
    // Calculate standard deviation
    double sumSquaredDiff = 0.0;
    for (double value in channelData) {
      double diff = value - mean;
      sumSquaredDiff += diff * diff;
    }
    double std = sqrt(sumSquaredDiff / channelData.length);

    return {
      'min': min,
      'max': max,
      'mean': mean,
      'std': std,
    };
  }

  @override
  String toString() {
    return 'ElectricalSeriesData(samples: $numSamples, channels: $numChannels, '
           'duration: ${duration.toStringAsFixed(2)}s, '
           'samplingRate: ${samplingRate.toStringAsFixed(1)}Hz, unit: $dataUnit)';
  }
}

/// Native function signatures for reading electrical series
typedef ReadElectricalSeriesNative = Int32 Function(
  Pointer<Char> filePath,
  Pointer<Char> seriesName,
  Pointer<Float> outVoltageData,
  Pointer<Int32> outVoltageDataSize,
  Pointer<Double> outTimestamps,
  Pointer<Int32> outTimestampsSize,
  Pointer<Int32> outElectrodes,
  Pointer<Int32> outElectrodesSize,
  Pointer<Float> outChannelConversions,
  Pointer<Int32> outChannelConversionsSize,
  Pointer<Char> outDataUnit,
  Pointer<Int32> outNumChannels,
);

typedef ReadElectricalSeriesDart = int Function(
  Pointer<Char> filePath,
  Pointer<Char> seriesName,
  Pointer<Float> outVoltageData,
  Pointer<Int32> outVoltageDataSize,
  Pointer<Double> outTimestamps,
  Pointer<Int32> outTimestampsSize,
  Pointer<Int32> outElectrodes,
  Pointer<Int32> outElectrodesSize,
  Pointer<Float> outChannelConversions,
  Pointer<Int32> outChannelConversionsSize,
  Pointer<Char> outDataUnit,
  Pointer<Int32> outNumChannels,
);

typedef ReadElectricalSeriesPartialNative = Int32 Function(
  Pointer<Char> filePath,
  Pointer<Char> seriesName,
  Int32 startSample,
  Int32 numSamples,
  Pointer<Int32> channelIndices,
  Int32 numChannelIndices,
  Pointer<Float> outVoltageData,
  Pointer<Int32> outVoltageDataSize,
  Pointer<Double> outTimestamps,
  Pointer<Int32> outTimestampsSize,
);

typedef ReadElectricalSeriesPartialDart = int Function(
  Pointer<Char> filePath,
  Pointer<Char> seriesName,
  int startSample,
  int numSamples,
  Pointer<Int32> channelIndices,
  int numChannelIndices,
  Pointer<Float> outVoltageData,
  Pointer<Int32> outVoltageDataSize,
  Pointer<Double> outTimestamps,
  Pointer<Int32> outTimestampsSize,
);

/// Main class for reading electrical series data
class ElectricalSeriesReader {
  late final DynamicLibrary _dylib;
  late final ReadElectricalSeriesDart _readElectricalSeries;
  late final ReadElectricalSeriesPartialDart _readElectricalSeriesPartial;

  ElectricalSeriesReader() {
    // Load the native library
    if (Platform.isMacOS) {
      _dylib = DynamicLibrary.open('libnwbfile_plugin.dylib');
    } else if (Platform.isLinux) {
      _dylib = DynamicLibrary.open('libnwbfile_plugin.so');
    } else if (Platform.isWindows) {
      _dylib = DynamicLibrary.open('nwbfile_plugin.dll');
    } else if (Platform.isAndroid) {
      _dylib = DynamicLibrary.open('libnwbfile_plugin.so');
    } else if (Platform.isIOS) {
      _dylib = DynamicLibrary.process();
    } else {
      throw UnsupportedError('Platform not supported');
    }

    // Bind native functions
    _readElectricalSeries = _dylib
        .lookup<NativeFunction<ReadElectricalSeriesNative>>('read_electrical_series_complete')
        .asFunction<ReadElectricalSeriesDart>();

    _readElectricalSeriesPartial = _dylib
        .lookup<NativeFunction<ReadElectricalSeriesPartialNative>>('read_electrical_series_partial')
        .asFunction<ReadElectricalSeriesPartialDart>();
  }

  /// Read complete electrical series data from NWB file
  Future<ElectricalSeriesData?> readElectricalSeries(
    String filePath, {
    String seriesName = 'ElectricalSeries1',
  }) async {
    // Allocate memory for output data (adjust sizes based on expected data size)
    const int maxSamples = 1000000;
    const int maxChannels = 64;
    const int maxStringLength = 256;

    Pointer<Float> voltageDataPtr = calloc<Float>(maxSamples * maxChannels);
    Pointer<Int32> voltageDataSizePtr = calloc<Int32>();
    Pointer<Double> timestampsPtr = calloc<Double>(maxSamples);
    Pointer<Int32> timestampsSizePtr = calloc<Int32>();
    Pointer<Int32> electrodesPtr = calloc<Int32>(maxChannels);
    Pointer<Int32> electrodesSizePtr = calloc<Int32>();
    Pointer<Float> channelConversionsPtr = calloc<Float>(maxChannels);
    Pointer<Int32> channelConversionsSizePtr = calloc<Int32>();
    Pointer<Char> dataUnitPtr = calloc<Char>(maxStringLength);
    Pointer<Int32> numChannelsPtr = calloc<Int32>();

    try {
      // Convert strings to native
      Pointer<Char> filePathPtr = filePath.toNativeUtf8().cast<Char>();
      Pointer<Char> seriesNamePtr = seriesName.toNativeUtf8().cast<Char>();

      print('📖 Reading electrical series: $seriesName from $filePath');

      // Call native function
      int result = _readElectricalSeries(
        filePathPtr,
        seriesNamePtr,
        voltageDataPtr,
        voltageDataSizePtr,
        timestampsPtr,
        timestampsSizePtr,
        electrodesPtr,
        electrodesSizePtr,
        channelConversionsPtr,
        channelConversionsSizePtr,
        dataUnitPtr,
        numChannelsPtr,
      );

      if (result == 0) {
        // Success - extract data
        int voltageDataSize = voltageDataSizePtr.value;
        int timestampsSize = timestampsSizePtr.value;
        int electrodesSize = electrodesSizePtr.value;
        int channelConversionsSize = channelConversionsSizePtr.value;
        int numChannels = numChannelsPtr.value;

        print('✅ Successfully read electrical series data:');
        print('   📊 Voltage data points: $voltageDataSize');
        print('   ⏰ Timestamps: $timestampsSize');
        print('   🔌 Electrodes: $electrodesSize');
        print('   📈 Channels: $numChannels');

        // Extract data from native memory
        Float32List voltageData = voltageDataPtr.asTypedList(voltageDataSize);
        Float64List timestamps = timestampsPtr.asTypedList(timestampsSize);
        Int32List electrodeIndices = electrodesPtr.asTypedList(electrodesSize);
        Float32List channelConversions = channelConversionsPtr.asTypedList(channelConversionsSize);
        String dataUnit = dataUnitPtr.cast<Utf8>().toDartString();

        // Create copies of the data (since the native memory will be freed)
        return ElectricalSeriesData(
          voltageData: Float32List.fromList(voltageData),
          timestamps: Float64List.fromList(timestamps),
          electrodeIndices: Int32List.fromList(electrodeIndices),
          channelConversions: Float32List.fromList(channelConversions),
          dataUnit: dataUnit,
          numSamples: timestampsSize,
          numChannels: numChannels,
        );
      } else {
        print('❌ Failed to read electrical series: error code $result');
        return null;
      }
    } finally {
      // Clean up memory
      calloc.free(voltageDataPtr);
      calloc.free(voltageDataSizePtr);
      calloc.free(timestampsPtr);
      calloc.free(timestampsSizePtr);
      calloc.free(electrodesPtr);
      calloc.free(electrodesSizePtr);
      calloc.free(channelConversionsPtr);
      calloc.free(channelConversionsSizePtr);
      calloc.free(dataUnitPtr);
      calloc.free(numChannelsPtr);
    }
  }

  /// Read partial electrical series data (specific time range and channels)
  Future<ElectricalSeriesData?> readElectricalSeriesPartial(
    String filePath, {
    String seriesName = 'ElectricalSeries1',
    required int startSample,
    required int numSamples,
    List<int>? channelIndices,
  }) async {
    // Allocate memory for output data
    Pointer<Float> voltageDataPtr = calloc<Float>(numSamples * 64);  // Max 64 channels
    Pointer<Int32> voltageDataSizePtr = calloc<Int32>();
    Pointer<Double> timestampsPtr = calloc<Double>(numSamples);
    Pointer<Int32> timestampsSizePtr = calloc<Int32>();

    // Prepare channel indices
    Pointer<Int32> channelIndicesPtr = nullptr;
    int numChannelIndices = 0;
    
    if (channelIndices != null && channelIndices.isNotEmpty) {
      numChannelIndices = channelIndices.length;
      channelIndicesPtr = calloc<Int32>(numChannelIndices);
      for (int i = 0; i < numChannelIndices; i++) {
        channelIndicesPtr[i] = channelIndices[i];
      }
    }

    try {
      // Convert strings to native
      Pointer<Char> filePathPtr = filePath.toNativeUtf8().cast<Char>();
      Pointer<Char> seriesNamePtr = seriesName.toNativeUtf8().cast<Char>();

      print('📖 Reading partial electrical series:');
      print('   📂 File: $filePath');
      print('   📊 Series: $seriesName');
      print('   ⏰ Samples: $startSample to ${startSample + numSamples - 1}');
      if (channelIndices != null) {
        print('   🔌 Channels: ${channelIndices.join(", ")}');
      }

      // Call native function
      int result = _readElectricalSeriesPartial(
        filePathPtr,
        seriesNamePtr,
        startSample,
        numSamples,
        channelIndicesPtr,
        numChannelIndices,
        voltageDataPtr,
        voltageDataSizePtr,
        timestampsPtr,
        timestampsSizePtr,
      );

      if (result == 0) {
        // Success - extract data
        int voltageDataSize = voltageDataSizePtr.value;
        int timestampsSize = timestampsSizePtr.value;

        print('✅ Successfully read partial electrical series data:');
        print('   📊 Voltage data points: $voltageDataSize');
        print('   ⏰ Timestamps: $timestampsSize');

        // Extract data from native memory
        Float32List voltageData = voltageDataPtr.asTypedList(voltageDataSize);
        Float64List timestamps = timestampsPtr.asTypedList(timestampsSize);

        // For partial reads, we don't have electrode/conversion info
        return ElectricalSeriesData(
          voltageData: Float32List.fromList(voltageData),
          timestamps: Float64List.fromList(timestamps),
          electrodeIndices: Int32List(0),
          channelConversions: Float32List(0),
          dataUnit: 'volts',
          numSamples: timestampsSize,
          numChannels: numChannelIndices > 0 ? numChannelIndices : 1,
        );
      } else {
        print('❌ Failed to read partial electrical series: error code $result');
        return null;
      }
    } finally {
      // Clean up memory
      calloc.free(voltageDataPtr);
      calloc.free(voltageDataSizePtr);
      calloc.free(timestampsPtr);
      calloc.free(timestampsSizePtr);
      if (channelIndicesPtr != nullptr) {
        calloc.free(channelIndicesPtr);
      }
    }
  }

  /// List available electrical series in an NWB file
  Future<List<String>> listElectricalSeries(String filePath) async {
    // This would require a separate native function to list available series
    // For now, return common series names
    return ['ElectricalSeries1', 'ElectricalSeries2', 'recording1', 'recording2'];
  }
}

/// Widget for displaying electrical series data in Flutter
class ElectricalSeriesWidget extends StatefulWidget {
  final ElectricalSeriesData data;
  final int selectedChannel;

  const ElectricalSeriesWidget({
    Key? key,
    required this.data,
    this.selectedChannel = 0,
  }) : super(key: key);

  @override
  _ElectricalSeriesWidgetState createState() => _ElectricalSeriesWidgetState();
}

class _ElectricalSeriesWidgetState extends State<ElectricalSeriesWidget> {
  late int _selectedChannel;
  double _timeStart = 0.0;
  double _timeEnd = 10.0;

  @override
  void initState() {
    super.initState();
    _selectedChannel = widget.selectedChannel;
    _timeEnd = math.min(10.0, widget.data.duration);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Data info
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Electrical Series Data', style: Theme.of(context).textTheme.headline6),
                const SizedBox(height: 8),
                Text('Samples: ${widget.data.numSamples}'),
                Text('Channels: ${widget.data.numChannels}'),
                Text('Duration: ${widget.data.duration.toStringAsFixed(2)} seconds'),
                Text('Sampling Rate: ${widget.data.samplingRate.toStringAsFixed(1)} Hz'),
                Text('Unit: ${widget.data.dataUnit}'),
              ],
            ),
          ),
        ),
        
        // Channel selector
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Channel Selection', style: Theme.of(context).textTheme.subtitle1),
                DropdownButton<int>(
                  value: _selectedChannel,
                  items: List.generate(widget.data.numChannels, (index) {
                    return DropdownMenuItem(
                      value: index,
                      child: Text('Channel $index'),
                    );
                  }),
                  onChanged: (value) {
                    setState(() {
                      _selectedChannel = value ?? 0;
                    });
                  },
                ),
              ],
            ),
          ),
        ),
        
        // Time range selector
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Time Range', style: Theme.of(context).textTheme.subtitle1),
                RangeSlider(
                  values: RangeValues(_timeStart, _timeEnd),
                  min: 0.0,
                  max: widget.data.duration,
                  divisions: 100,
                  labels: RangeLabels(
                    '${_timeStart.toStringAsFixed(1)}s',
                    '${_timeEnd.toStringAsFixed(1)}s',
                  ),
                  onChanged: (values) {
                    setState(() {
                      _timeStart = values.start;
                      _timeEnd = values.end;
                    });
                  },
                ),
              ],
            ),
          ),
        ),
        
        // Channel statistics
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Channel $_selectedChannel Statistics', 
                     style: Theme.of(context).textTheme.subtitle1),
                const SizedBox(height: 8),
                FutureBuilder<Map<String, double>>(
                  future: Future.value(widget.data.getChannelStats(_selectedChannel)),
                  builder: (context, snapshot) {
                    if (snapshot.hasData) {
                      final stats = snapshot.data!;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Min: ${stats['min']!.toStringAsFixed(6)} V'),
                          Text('Max: ${stats['max']!.toStringAsFixed(6)} V'),
                          Text('Mean: ${stats['mean']!.toStringAsFixed(6)} V'),
                          Text('Std: ${stats['std']!.toStringAsFixed(6)} V'),
                        ],
                      );
                    }
                    return const CircularProgressIndicator();
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Example usage function
Future<void> demonstrateElectricalSeriesReading() async {
  print('🚀 Electrical Series Reading Example');
  print('====================================');

  final reader = ElectricalSeriesReader();
  
  // Get the documents directory
  final directory = await getApplicationDocumentsDirectory();
  final filePath = '${directory.path}/example_recording2.nwb';
  
  print('📂 File path: $filePath');
  
  // Check if file exists
  if (!await File(filePath).exists()) {
    print('❌ NWB file not found at: $filePath');
    return;
  }
  
  try {
    // Method 1: Read complete electrical series
    print('\n🔬 Method 1: Reading Complete Electrical Series');
    print('==============================================');
    
    final completeData = await reader.readElectricalSeries(filePath);
    if (completeData != null) {
      print('✅ Complete data loaded:');
      print('   $completeData');
      
      // Show first channel statistics
      if (completeData.numChannels > 0) {
        final stats = completeData.getChannelStats(0);
        print('   📊 Channel 0 stats: ${stats.toString()}');
      }
      
      // Get first 10 seconds of data
      if (completeData.duration > 10) {
        final firstTenSeconds = completeData.getTimeRange(0.0, 10.0);
        print('   ⏰ First 10 seconds: ${firstTenSeconds.numSamples} samples');
      }
    }
    
    // Method 2: Read partial data
    print('\n🔬 Method 2: Reading Partial Electrical Series');
    print('==============================================');
    
    final partialData = await reader.readElectricalSeriesPartial(
      filePath,
      startSample: 1000,
      numSamples: 5000,
      channelIndices: [0, 1, 2],
    );
    
    if (partialData != null) {
      print('✅ Partial data loaded:');
      print('   $partialData');
    }
    
    // Method 3: List available series
    print('\n🔬 Method 3: Listing Available Series');
    print('====================================');
    
    final availableSeries = await reader.listElectricalSeries(filePath);
    print('📋 Available electrical series:');
    for (final series in availableSeries) {
      print('   • $series');
    }
    
  } catch (e) {
    print('❌ Error during electrical series reading: $e');
  }
}

// Required imports for the widget example
import 'package:flutter/material.dart';
import 'dart:math' as math;

/// Main function for running the example
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Run the demonstration
  await demonstrateElectricalSeriesReading();
  
  // Run the Flutter app if needed
  // runApp(MyApp());
}

/// Simple Flutter app demonstrating the electrical series widget
class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Electrical Series Reader',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: ElectricalSeriesScreen(),
    );
  }
}

class ElectricalSeriesScreen extends StatefulWidget {
  @override
  _ElectricalSeriesScreenState createState() => _ElectricalSeriesScreenState();
}

class _ElectricalSeriesScreenState extends State<ElectricalSeriesScreen> {
  ElectricalSeriesData? _data;
  bool _loading = false;
  final ElectricalSeriesReader _reader = ElectricalSeriesReader();

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
    });

    try {
      final directory = await getApplicationDocumentsDirectory();
      final filePath = '${directory.path}/example_recording2.nwb';
      
      final data = await _reader.readElectricalSeries(filePath);
      setState(() {
        _data = data;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading data: $e')),
      );
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Electrical Series Reader'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _data != null
              ? SingleChildScrollView(
                  padding: const EdgeInsets.all(16.0),
                  child: ElectricalSeriesWidget(data: _data!),
                )
              : Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.insert_drive_file, size: 64),
                      const SizedBox(height: 16),
                      const Text('No electrical series data loaded'),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadData,
                        child: const Text('Load Data'),
                      ),
                    ],
                  ),
                ),
    );
  }
}


















