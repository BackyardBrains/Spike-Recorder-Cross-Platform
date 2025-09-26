import 'dart:async';
import 'dart:ffi';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'package:nwbfile_plugin/nwbfile_plugin.dart' as nwb;
import 'package:path_provider/path_provider.dart';
import 'package:spikerbox_architecture/models/nwbfile_utils/nwbfile_utils.dart';

class NwbFileUtilImpl implements NWBFileUtil {
  @override
  Future<bool> processingInit(int sampleRate, int channelCount) async {
    final path = (await getApplicationDocumentsDirectory()).path;
    print("NWB file path: $path");
    Pointer<Char> charPointer = path.toString().toNativeUtf8().cast<Char>();

    nwb.processingInit(charPointer,sampleRate, channelCount);
    return Future.value(true);
  }

  @override
  Future<bool> addElectricalSeries(Int16List data, Int32List samplesCount, int selectedChannel,int channelCount, int isFinishRecording) {
    // print("addElectricalSeries: $isFinishRecording");
    Pointer<Int16> dataPtr = calloc<Int16>(data.length);
    dataPtr.asTypedList(data.length).setAll(0, data);
    Pointer<Int32> samplesCountPtr = calloc<Int32>(samplesCount.length);
    samplesCountPtr.asTypedList(samplesCount.length).setAll(0, samplesCount);
    nwb.nwbfile_add_electrical_series(dataPtr, samplesCountPtr, selectedChannel, channelCount, isFinishRecording);
    return Future.value(true);
  }
  
  @override
  Future<bool> readElectricalSeries(Int16List outSamples, Int32List outSamplesCount, int selectedChannel, int channelCount) {
    Pointer<Int16> outSamplesPtr = calloc<Int16>(outSamples.length);
    Pointer<Int32> outSamplesCountPtr = calloc<Int32>(outSamplesCount.length);
    
    try {
      print("📖 Reading electrical series data...");
      print("   Channel: $selectedChannel");
      print("   Expected samples: ${outSamples.length}");
      
      int result = nwb.nwbfile_read_electrical_series(outSamplesPtr, outSamplesCountPtr, selectedChannel, channelCount);
      
      print("📊 Read result: $result");
      
      if (result == 0) {
        // Success - copy data back from native memory
        int actualSampleCount = outSamplesCountPtr.value;
        print("📊 Actual samples read: $actualSampleCount");
        
        // Copy the data back to the Dart list
        if (actualSampleCount > 0 && actualSampleCount <= outSamples.length) {
          for (int i = 0; i < actualSampleCount; i++) {
            outSamples[i] = outSamplesPtr[i];
          }
          outSamplesCount[0] = actualSampleCount;
          
          print("✅ Successfully copied $actualSampleCount samples");
          
          // Print first few samples for verification
          if (actualSampleCount > 0) {
            print("📈 First 5 samples:");
            for (int i = 0; i < 5 && i < actualSampleCount; i++) {
              print("   Sample $i: ${outSamples[i]}");
            }
          }
          
          return Future.value(true);
        } else {
          print("❌ Invalid sample count: $actualSampleCount");
          return Future.value(false);
        }
      } else {
        print("❌ Failed to read electrical series, error code: $result");
        return Future.value(false);
      }
    } finally {
      calloc.free(outSamplesPtr);
      calloc.free(outSamplesCountPtr);
    }
  }

  @override
  Future<bool> seekElectricalSeries(Int16List outSamples, Int32List outSamplesCount, Int32List outConfig, int startTimeStamp, int endTimeStamp, int selectedChannel, int channelCount) {
    Pointer<Int16> outSamplesPtr = calloc<Int16>(outSamples.length);
    Pointer<Int32> outSamplesCountPtr = calloc<Int32>(outSamplesCount.length);
    Pointer<Int32> outConfigPtr = calloc<Int32>(10); // Allocate for 5 config parameters
    try {
      print("🎯 Seeking electrical series data...");
      print("   Time range: $startTimeStamp to $endTimeStamp");
      print("   Channel: $selectedChannel");
      print("   Expected samples: ${endTimeStamp - startTimeStamp}");
      
      int result = nwb.nwbfile_seek_electrical_series(outSamplesPtr, outSamplesCountPtr, outConfigPtr, startTimeStamp, endTimeStamp, selectedChannel, channelCount);
      
      print("📊 Seek result: $result");
      
      if (result == 0) {
        // Success - copy data back from native memory
        int actualSampleCount = outSamplesCountPtr.value;
        print("📊 Actual samples read: $actualSampleCount");
        
        // Copy the data back to the Dart list
        if (actualSampleCount > 0 && actualSampleCount <= outSamples.length) {
          for (int i = 0; i < actualSampleCount; i++) {
            outSamples[i] = outSamplesPtr[i];
          }
          outSamplesCount[0] = actualSampleCount;
          
          // Copy configuration parameters
          for (int i = 0; i < 5 && i < outConfig.length; i++) {
            outConfig[i] = outConfigPtr[i];
          }
          
          print("✅ Successfully copied $actualSampleCount samples from seek operation");
          
          // Print configuration parameters
          print("📋 Recording Configuration:");
          print("   Sample Rate: ${outConfig[0]} Hz");
          print("   Total Channels: ${outConfig[1]}");
          print("   Group Name (ID): ${outConfig[2]}");
          print("   Group Index: ${outConfig[3]}");
          print("   BitVolts (µV): ${outConfig[4]}");
          
          // Print first few samples for verification
          if (actualSampleCount > 0) {
            print("📈 First 5 samples from seek:");
            for (int i = 0; i < 5 && i < actualSampleCount; i++) {
              print("   Sample ${startTimeStamp + i}: ${outSamples[i]}");
            }
          }
          
          return Future.value(true);
        } else {
          print("❌ Invalid sample count from seek: $actualSampleCount");
          return Future.value(false);
        }
      } else {
        print("❌ Failed to seek electrical series, error code: $result");
        return Future.value(false);
      }
    } finally {
      outSamples.setAll(0, outSamplesPtr.asTypedList(outSamples.length));
      outSamplesCount.setAll(0, outSamplesCountPtr.asTypedList(outSamplesCount.length));
      outConfig.setAll(0, outConfigPtr.asTypedList(10));

      calloc.free(outSamplesPtr);
      calloc.free(outSamplesCountPtr);
      calloc.free(outConfigPtr);
    }
  }
}

NWBFileUtil createNwbFileUtil() => NwbFileUtilImpl();