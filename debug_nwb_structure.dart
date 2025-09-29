/**
 * Debug script to inspect NWB file structure and help diagnose the H5D error
 */

import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:path_provider/path_provider.dart';

// Import your plugin
import 'native_implementation/pluggins/nwbfile_plugin/lib/nwbfile_plugin.dart' as nwb;

void main() async {
  print('🔍 NWB File Structure Debug Tool');
  print('=================================');

  // Get the expected file path
  final directory = await getApplicationDocumentsDirectory();
  final filePath = '${directory.path}/example_recording2.nwb';
  
  print('📂 Checking file: $filePath');
  
  // Check if file exists
  final file = File(filePath);
  if (!await file.exists()) {
    print('❌ File does not exist at: $filePath');
    print('💡 Make sure to run the recording process first to create the NWB file');
    return;
  }
  
  final fileSize = await file.length();
  print('✅ File exists, size: ${fileSize} bytes');
  
  // Convert path to native string
  final pathPtr = filePath.toNativeUtf8().cast<Char>();
  
  try {
    print('\n🔍 Inspecting NWB file structure...');
    print('====================================');
    
    // Call the debug function
    final result = nwb.debugNwbFileStructure(pathPtr);
    
    print('\n📊 Debug function result: $result');
    
    switch (result) {
      case 0:
        print('✅ Successfully inspected file structure');
        break;
      case -1:
        print('❌ File path is null');
        break;
      case -2:
        print('❌ Failed to open file - file may be corrupted or not a valid HDF5 file');
        break;
      case -3:
        print('❌ HDF5 error occurred while reading file structure');
        break;
      case -4:
        print('❌ General error occurred');
        break;
      default:
        print('❌ Unknown error code: $result');
    }
    
    print('\n🔧 Attempting to read electrical series...');
    print('==========================================');
    
    // Try the electrical series reading function
    final outSamplesPtr = calloc<Int16>(1000);  // Allocate space for samples
    final outSamplesCountPtr = calloc<Int32>(1);  // Allocate space for count
    
    try {
      final readResult = nwb.nwbfile_read_electrical_series(
        outSamplesPtr, 
        outSamplesCountPtr, 
        0,  // selectedChannel
        1   // channelCount
      );
      
      print('📊 Read function result: $readResult');
      
      switch (readResult) {
        case 0:
          print('✅ Successfully read electrical series data');
          break;
        case -1:
          print('❌ Failed to open NWB file');
          break;
        case -2:
          print('❌ Could not find electrical series data in expected locations');
          break;
        case -3:
          print('❌ HDF5 error during reading');
          break;
        case -4:
          print('❌ General error during reading');
          break;
        case 1:
          print('⚠️  Function returned 1 (legacy return code)');
          break;
        default:
          print('❌ Unknown read result: $readResult');
      }
      
    } finally {
      calloc.free(outSamplesPtr);
      calloc.free(outSamplesCountPtr);
    }
    
  } finally {
    calloc.free(pathPtr);
  }
  
  print('\n💡 Troubleshooting Tips:');
  print('========================');
  print('1. If the file structure shows no electrical series data:');
  print('   - Check if the recording process completed successfully');
  print('   - Verify the NWB file was written correctly');
  print('');
  print('2. If you see datasets but not in expected locations:');
  print('   - Update the code to use the actual path shown above');
  print('   - The data might be in /acquisition/<SeriesName>/data');
  print('');
  print('3. If the file cannot be opened:');
  print('   - The file might be corrupted or still being written');
  print('   - Try closing any applications that might have the file open');
  print('');
  print('4. Use external tools for verification:');
  print('   - h5dump -n "$filePath" (shows structure)');
  print('   - h5ls -r "$filePath" (lists all datasets)');
  print('   - HDFView (GUI tool for HDF5 files)');
}



