import 'dart:ffi';
import 'dart:io';
import 'lib/nwbfile_plugin.dart';

void main() async {
  print('Testing iOS NWB Plugin Functionality');
  print('=====================================');

  // Test basic math functions
  print('\n1. Testing basic math functions:');
  int result = sum(5, 3);
  print('sum(5, 3) = $result');

  // Test NWB processing
  print('\n2. Testing NWB processing:');
  int initResult = processingInit();
  print('processingInit() result: $initResult');

  // Test NWB file data access
  print('\n3. Testing NWB file data access:');
  int fileSize = getNwbFileSize();
  print('NWB file size: $fileSize bytes');

  if (fileSize > 0) {
    // Allocate buffer for the file data
    final buffer = malloc<Char>(fileSize);
    
    try {
      int bytesRead = getNwbFileData(buffer, fileSize);
      print('Bytes read: $bytesRead');
      
      if (bytesRead > 0) {
        // Convert the buffer to a string
        final bytes = buffer.asTypedList(bytesRead);
        final content = String.fromCharCodes(bytes);
        print('NWB file content:');
        print('----------------');
        print(content);
        print('----------------');
      }
    } finally {
      // Clean up the buffer
      malloc.free(buffer);
    }
  }

  // Clean up NWB data
  print('\n4. Cleaning up NWB data:');
  cleanupNwbData();
  print('Cleanup completed');

  print('\n✅ iOS NWB Plugin test completed successfully!');
}
