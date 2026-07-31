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

  // Clean up NWB data
  print('\n4. Cleaning up NWB data:');
  cleanupNwbData();
  print('Cleanup completed');

  print('\n✅ iOS NWB Plugin test completed successfully!');
  print('Note: Full file content retrieval requires manual memory management in Dart FFI');
}


