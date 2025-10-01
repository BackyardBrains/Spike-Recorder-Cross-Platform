/**
 * Test script to verify electrical series reading functionality
 */

import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'lib/models/nwbfile_utils/nwbfile_utils_native.dart';

void main() async {
  print('🧪 Testing Electrical Series Reading');
  print('====================================');

  final nwbUtil = NwbFileUtilImpl();
  
  try {
    // Test reading electrical series data
    print('\n📖 Testing electrical series reading...');
    
    // Prepare output buffers
    const int maxSamples = 10000;  // Adjust based on your expected data size
    Int16List outSamples = Int16List(maxSamples);
    Int32List outSamplesCount = Int32List(1);
    
    // Test reading channel 0
    print('📊 Reading channel 0...');
    bool success = await nwbUtil.readElectricalSeries(
      outSamples, 
      outSamplesCount, 
      0,  // selectedChannel
      1   // channelCount (this parameter might not be used in your implementation)
    );
    
    if (success) {
      int actualSamples = outSamplesCount[0];
      print('✅ Successfully read $actualSamples samples from channel 0');
      
      if (actualSamples > 0) {
        // Display statistics
        int minValue = outSamples[0];
        int maxValue = outSamples[0];
        double sum = 0.0;
        
        for (int i = 0; i < actualSamples; i++) {
          int value = outSamples[i];
          if (value < minValue) minValue = value;
          if (value > maxValue) maxValue = value;
          sum += value;
        }
        
        double average = sum / actualSamples;
        
        print('📈 Data Statistics:');
        print('   Min value: $minValue');
        print('   Max value: $maxValue');
        print('   Average: ${average.toStringAsFixed(2)}');
        print('   Total samples: $actualSamples');
        
        // Display first 20 samples
        print('\n📊 First 20 samples:');
        for (int i = 0; i < 20 && i < actualSamples; i++) {
          print('   Sample $i: ${outSamples[i]}');
        }
        
        // Display last 10 samples if we have enough data
        if (actualSamples > 30) {
          print('\n📊 Last 10 samples:');
          for (int i = actualSamples - 10; i < actualSamples; i++) {
            print('   Sample $i: ${outSamples[i]}');
          }
        }
        
        // Test reading multiple channels if available
        print('\n📊 Testing multiple channels...');
        
        for (int channel = 0; channel < 4; channel++) {  // Test up to 4 channels
          Int16List channelSamples = Int16List(1000);  // Smaller buffer for channel test
          Int32List channelSamplesCount = Int32List(1);
          
          bool channelSuccess = await nwbUtil.readElectricalSeries(
            channelSamples,
            channelSamplesCount,
            channel,
            1
          );
          
          if (channelSuccess && channelSamplesCount[0] > 0) {
            print('   ✅ Channel $channel: ${channelSamplesCount[0]} samples');
            
            // Show first 3 samples from each channel
            print('      First 3 samples: ${channelSamples[0]}, ${channelSamples[1]}, ${channelSamples[2]}');
          } else {
            print('   ❌ Channel $channel: No data or error');
          }
        }
        
      } else {
        print('⚠️  No samples were read (empty dataset)');
      }
    } else {
      print('❌ Failed to read electrical series data');
    }
    
    print('\n💡 Usage Tips:');
    print('==============');
    print('1. Make sure you have written data using addElectricalSeries first');
    print('2. Ensure the recording process completed successfully (isFinishRecording = 1)');
    print('3. Check that the NWB file exists and is not corrupted');
    print('4. The data you get back should match what you originally wrote');
    print('5. Data is automatically converted back from float to int16 with proper scaling');
    
  } catch (e) {
    print('❌ Error during testing: $e');
  }
}

/// Helper function to compare written vs read data
void compareData(Int16List originalData, Int16List readData, int samples) {
  print('\n🔍 Comparing written vs read data:');
  
  int matches = 0;
  int differences = 0;
  double maxDifference = 0.0;
  
  for (int i = 0; i < samples; i++) {
    int diff = (originalData[i] - readData[i]).abs();
    if (diff == 0) {
      matches++;
    } else {
      differences++;
      if (diff > maxDifference) {
        maxDifference = diff.toDouble();
      }
    }
  }
  
  print('   ✅ Exact matches: $matches');
  print('   ⚠️  Differences: $differences');
  print('   📊 Max difference: $maxDifference');
  
  double accuracy = (matches / samples) * 100;
  print('   📈 Accuracy: ${accuracy.toStringAsFixed(1)}%');
  
  if (accuracy > 95) {
    print('   🎉 Excellent data fidelity!');
  } else if (accuracy > 80) {
    print('   👍 Good data fidelity');
  } else {
    print('   ⚠️  Data fidelity could be improved');
  }
}






