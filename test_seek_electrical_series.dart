import 'dart:typed_data';
import 'lib/models/nwbfile_utils/nwbfile_utils.dart';

void main() async {
  print("🎯 Testing NWB File Seek Functionality");
  print("=====================================");
  
  // Create NWB file utility instance
  NWBFileUtil nwbUtil = createNwbFileUtil();
  
  // Test parameters
  int selectedChannel = 0;  // Channel to read
  int totalChannels = 4;    // Total channels in the file
  
  // Test 1: Seek first 100 samples
  print("\n📊 Test 1: Seeking first 100 samples (0-100)");
  await testSeek(nwbUtil, 0, 100, selectedChannel, totalChannels, "First 100 samples");
  
  // Test 2: Seek middle section
  print("\n📊 Test 2: Seeking middle section (200-300)");
  await testSeek(nwbUtil, 200, 300, selectedChannel, totalChannels, "Middle section");
  
  // Test 3: Seek small range
  print("\n📊 Test 3: Seeking small range (50-60)");
  await testSeek(nwbUtil, 50, 60, selectedChannel, totalChannels, "Small range");
  
  // Test 4: Seek different channel
  print("\n📊 Test 4: Seeking channel 1 (500-600)");
  await testSeek(nwbUtil, 500, 600, 1, totalChannels, "Different channel");
  
  // Test 5: Error case - invalid range
  print("\n📊 Test 5: Error case - invalid range (1000-2000)");
  await testSeek(nwbUtil, 1000, 2000, selectedChannel, totalChannels, "Invalid range (should fail)");
  
  print("\n✅ All seek tests completed!");
}

Future<void> testSeek(NWBFileUtil nwbUtil, int startTime, int endTime, int channel, int totalChannels, String testName) async {
  print("\n🎯 $testName");
  print("   Range: $startTime to $endTime");
  print("   Channel: $channel");
  
  // Calculate expected sample count
  int expectedSamples = endTime - startTime;
  
  // Prepare output buffers
  Int16List samples = Int16List(expectedSamples);
  Int32List sampleCount = Int32List(1);
  Int32List config = Int32List(5); // For recording parameters
  
  try {
    // Perform seek operation
    bool success = await nwbUtil.seekElectricalSeries(
      samples, 
      sampleCount, 
      config,  // Add config parameter
      startTime, 
      endTime, 
      channel, 
      totalChannels
    );
    
    if (success) {
      print("✅ Seek operation successful!");
      print("   Samples read: ${sampleCount[0]}");
      
      // Show recording configuration
      print("   📋 Recording Configuration:");
      print("      Sample Rate: ${config[0]} Hz");
      print("      Total Channels: ${config[1]}");
      print("      Group Name (ID): ${config[2]}");
      print("      Group Index: ${config[3]}");
      print("      BitVolts (µV): ${config[4]}");
      
      // Show sample statistics
      if (sampleCount[0] > 0) {
        int min = samples[0];
        int max = samples[0];
        double sum = 0;
        
        for (int i = 0; i < sampleCount[0]; i++) {
          int value = samples[i];
          if (value < min) min = value;
          if (value > max) max = value;
          sum += value;
        }
        
        double average = sum / sampleCount[0];
        
        print("   📈 Statistics:");
        print("      Min: $min");
        print("      Max: $max");
        print("      Average: ${average.toStringAsFixed(2)}");
        
        // Show first few samples
        print("   📊 First few samples:");
        int samplesToShow = sampleCount[0] < 5 ? sampleCount[0] : 5;
        for (int i = 0; i < samplesToShow; i++) {
          print("      Sample ${startTime + i}: ${samples[i]}");
        }
      }
      
    } else {
      print("❌ Seek operation failed!");
    }
    
  } catch (e) {
    print("❌ Exception during seek: $e");
  }
}
