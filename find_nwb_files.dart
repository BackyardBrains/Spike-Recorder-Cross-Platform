import 'dart:io';

void main() async {
  print("🔍 Searching for NWB files...");
  
  // Common locations where NWB files might be stored
  List<String> searchPaths = [
    "/Users/macbook/Documents",
    "/Users/macbook/Library/Containers/com.example.nwbapplication/Data/Documents",
    "/Users/macbook/development/BYB/GH/SR_GH/AI/Spike-Recorder-Cross-Platform",
    "/Users/macbook/Desktop",
    "/tmp",
  ];
  
  bool foundAny = false;
  
  for (String searchPath in searchPaths) {
    print("\n📂 Checking directory: $searchPath");
    
    try {
      Directory dir = Directory(searchPath);
      if (await dir.exists()) {
        print("✅ Directory exists");
        
        // List all .nwb files in this directory
        await for (FileSystemEntity entity in dir.list(recursive: false)) {
          if (entity is File && entity.path.endsWith('.nwb')) {
            foundAny = true;
            FileStat stat = await entity.stat();
            print("📄 Found NWB file: ${entity.path}");
            print("   Size: ${stat.size} bytes");
            print("   Modified: ${stat.modified}");
            
            // Try to verify it's a valid HDF5 file
            try {
              RandomAccessFile file = await entity.open();
              List<int> header = await file.read(8);
              await file.close();
              
              // HDF5 files start with specific magic bytes
              if (header.length >= 8 && 
                  header[0] == 0x89 && 
                  header[1] == 0x48 && 
                  header[2] == 0x44 && 
                  header[3] == 0x46) {
                print("   ✅ Valid HDF5 file format");
              } else {
                print("   ❌ Not a valid HDF5 file (wrong header)");
              }
            } catch (e) {
              print("   ⚠️  Could not verify file format: $e");
            }
          }
        }
        
        // Also check for any files with "recording" in the name
        await for (FileSystemEntity entity in dir.list(recursive: false)) {
          if (entity is File && 
              (entity.path.contains('recording') || entity.path.contains('example')) &&
              !entity.path.endsWith('.nwb')) {
            print("📄 Related file: ${entity.path}");
          }
        }
        
      } else {
        print("❌ Directory does not exist");
      }
    } catch (e) {
      print("❌ Error accessing directory: $e");
    }
  }
  
  if (!foundAny) {
    print("\n❌ No .nwb files found in any searched locations!");
    print("💡 Make sure you have created an NWB file first using writeElectricalSeries");
    print("💡 The file should be created when you run your write operation");
  } else {
    print("\n✅ Search complete! Use one of the found file paths in your code.");
  }
  
  print("\n💡 You can also manually search for .nwb files using:");
  print("   find /Users/macbook -name '*.nwb' -type f 2>/dev/null");
}







