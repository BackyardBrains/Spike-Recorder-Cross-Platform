import 'dart:typed_data';
import 'lib/models/nwbfile_utils/nwbfile_utils.dart';

void main() async {
  print("🧪 Testing NWB Parameter Extraction");
  print("===================================");
  
  // Create NWB file utility instance
  NWBFileUtil nwbUtil = createNwbFileUtil();
  
  // Test parameters
  int selectedChannel = 0;  // Channel to read
  int totalChannels = 4;    // Total channels in the file
  int startTime = 100;      // Start sample
  int endTime = 200;        // End sample
  
  // Prepare output buffers
  int expectedSamples = endTime - startTime;
  Int16List samples = Int16List(expectedSamples);
  Int32List sampleCount = Int32List(1);
  Int32List config = Int32List(5); // For recording parameters
  
  print("\n🎯 Testing Parameter Extraction with Seek Operation");
  print("   Range: $startTime to $endTime");
  print("   Channel: $selectedChannel");
  print("   Expected samples: $expectedSamples");
  
  try {
    // Perform seek operation (this will extract and return parameters)
    bool success = await nwbUtil.seekElectricalSeries(
      samples, 
      sampleCount, 
      config,  // This will be populated with actual NWB parameters
      startTime, 
      endTime, 
      selectedChannel, 
      totalChannels
    );
    
    if (success) {
      print("\n✅ Parameter extraction successful!");
      print("   Samples read: ${sampleCount[0]}");
      
      print("\n📋 Extracted Recording Parameters:");
      print("   🎵 Sample Rate: ${config[0]} Hz");
      print("   📊 Total Channels: ${config[1]}");
      print("   🏷️  Group Name (ID): ${config[2]}");
      print("   📍 Group Index: ${config[3]}");
      print("   ⚡ BitVolts: ${config[4]} µV");
      
      // Analyze the parameters
      print("\n🔍 Parameter Analysis:");
      
      // Sample rate analysis
      if (config[0] > 0) {
        double recordingDuration = sampleCount[0] / config[0].toDouble();
        print("   ⏱️  Recording duration for this segment: ${recordingDuration.toStringAsFixed(3)} seconds");
        
        if (config[0] >= 30000) {
          print("   ✅ High sample rate detected - suitable for neural recording");
        } else if (config[0] >= 1000) {
          print("   ⚠️  Medium sample rate - may be suitable for LFP or EMG");
        } else {
          print("   ⚠️  Low sample rate - check if this is expected");
        }
      }
      
      // Channel analysis
      if (config[1] > 0) {
        print("   📊 Multi-channel recording with ${config[1]} channels");
        if (config[1] >= 64) {
          print("   🧠 High-density recording array");
        } else if (config[1] >= 16) {
          print("   🔬 Medium-density recording");
        } else {
          print("   📡 Low-density or tetrode recording");
        }
      }
      
      // Conversion factor analysis
      if (config[4] > 0) {
        double voltsPerBit = config[4] / 1000000.0; // Convert µV to V
        print("   ⚡ Voltage resolution: ${config[4]} µV per bit (${voltsPerBit} V per bit)");
        
        if (config[4] <= 100) {
          print("   ✅ High resolution - good for small neural signals");
        } else if (config[4] <= 1000) {
          print("   ✅ Medium resolution - suitable for most applications");
        } else {
          print("   ⚠️  Lower resolution - check if adequate for your signals");
        }
      }
      
      // Show some sample data
      if (sampleCount[0] > 0) {
        print("\n📈 Sample Data Preview:");
        int samplesToShow = sampleCount[0] < 10 ? sampleCount[0] : 10;
        for (int i = 0; i < samplesToShow; i++) {
          // Convert to actual voltage using the conversion factor
          double voltageUV = samples[i] * (config[4] / 1000000.0) * 1000000; // in µV
          print("   Sample ${startTime + i}: ${samples[i]} (raw) = ${voltageUV.toStringAsFixed(1)} µV");
        }
      }
      
      print("\n🎉 Parameter extraction test completed successfully!");
      
    } else {
      print("\n❌ Parameter extraction failed!");
      print("💡 This might happen if:");
      print("   - NWB file doesn't exist or is corrupted");
      print("   - File structure doesn't match expected format");
      print("   - Requested time range is out of bounds");
    }
    
  } catch (e) {
    print("\n❌ Exception during parameter extraction: $e");
    print("💡 Check that the NWB file exists and is properly formatted");
  }
  
  print("\n📚 Understanding the Parameters:");
  print("   config[0] = Sample Rate (Hz) - How many samples per second");
  print("   config[1] = Total Channels - Number of recording channels");
  print("   config[2] = Group Name ID - Electrode group identifier");
  print("   config[3] = Group Index - Index within the electrode group");
  print("   config[4] = BitVolts (µV) - Conversion factor from raw values to voltage");
}
