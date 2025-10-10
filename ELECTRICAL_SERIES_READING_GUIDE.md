# Reading Electrical Series from NWB Files - Educational Guide

This guide provides comprehensive examples for reading electrical series data from NWB (Neurodata Without Borders) files using different approaches.

## What is an Electrical Series?

An **Electrical Series** in NWB format stores continuously sampled voltage data from extracellular electrophysiology recordings. It contains:

- **Voltage Data**: Raw electrical measurements (typically in volts or microvolts)
- **Timestamps**: Time points for each sample
- **Electrode Information**: Which electrodes recorded the data
- **Channel Conversion**: Conversion factors for each channel
- **Metadata**: Sampling rate, units, descriptions

## NWB File Structure

```
NWB File
├── /acquisition/
│   └── ElectricalSeries1/          # Your electrical series data
│       ├── data                    # Voltage measurements [time × channels]
│       ├── timestamps              # Time points for each sample
│       ├── electrodes              # Electrode indices
│       ├── channel_conversion      # Per-channel conversion factors
│       └── starting_time           # Start time (alternative to timestamps)
├── /general/
│   └── extracellular_ephys/
│       └── electrodes/             # Electrode table with metadata
└── /file_create_date               # File creation timestamp
```

## Method 1: Using AQNWB Library (Recommended)

This is the most robust and feature-complete approach using the AQNWB library.

```cpp
#include "nwb/NWBFile.hpp"
#include "nwb/ecephys/ElectricalSeries.hpp"
#include "io/BaseIO.hpp"

using namespace AQNWB::NWB;
using namespace AQNWB::IO;

int readElectricalSeriesAQNWB(const std::string& filePath) {
    try {
        // 1. Open the NWB file for reading
        std::shared_ptr<BaseIO> io = AQNWB::createIO("HDF5", filePath);
        auto openStatus = io->open(FileMode::ReadOnly);
        if (openStatus != AQNWB::Types::Success) {
            std::cerr << "Failed to open NWB file: " << filePath << std::endl;
            return 1;
        }

        // 2. Create NWBFile object for reading
        auto nwbFile = RegisteredType::create<NWBFile>("/", io);
        if (!nwbFile) {
            std::cerr << "Failed to create NWBFile object" << std::endl;
            return 1;
        }

        // 3. Access the electrical series (typically in /acquisition/)
        std::string seriesPath = "/acquisition/ElectricalSeries1";
        auto electricalSeries = RegisteredType::create<ElectricalSeries>(seriesPath, io);
        if (!electricalSeries) {
            std::cerr << "ElectricalSeries not found at: " << seriesPath << std::endl;
            return 1;
        }

        // 4. Read the voltage data
        auto dataWrapper = electricalSeries->readData();
        if (dataWrapper) {
            // Get the data as float values (voltage data)
            auto dataBlock = dataWrapper->values<float>();
            
            std::cout << "Successfully read electrical series data!" << std::endl;
            std::cout << "Data dimensions: " << dataBlock.data.size() << " total samples" << std::endl;
            
            // Print first 10 data points
            std::cout << "First 10 voltage samples (in volts):" << std::endl;
            for (size_t i = 0; i < std::min(size_t(10), dataBlock.data.size()); ++i) {
                std::cout << "  Sample " << i << ": " << dataBlock.data[i] << " V" << std::endl;
            }
        }

        // 5. Read timestamps
        auto timestampsWrapper = electricalSeries->readTimestamps();
        if (timestampsWrapper) {
            auto timestampsBlock = timestampsWrapper->values<double>();
            std::cout << "\nTimestamp information:" << std::endl;
            std::cout << "Number of timestamps: " << timestampsBlock.data.size() << std::endl;
            
            if (!timestampsBlock.data.empty()) {
                std::cout << "First timestamp: " << timestampsBlock.data[0] << " seconds" << std::endl;
                std::cout << "Last timestamp: " << timestampsBlock.data.back() << " seconds" << std::endl;
                
                // Calculate sampling rate
                if (timestampsBlock.data.size() > 1) {
                    double samplingRate = 1.0 / (timestampsBlock.data[1] - timestampsBlock.data[0]);
                    std::cout << "Estimated sampling rate: " << samplingRate << " Hz" << std::endl;
                }
            }
        }

        // 6. Read electrode information
        auto electrodesWrapper = electricalSeries->readElectrodes();
        if (electrodesWrapper) {
            auto electrodesBlock = electrodesWrapper->values<int>();
            std::cout << "\nElectrode information:" << std::endl;
            std::cout << "Number of electrodes: " << electrodesBlock.data.size() << std::endl;
            std::cout << "Electrode indices: ";
            for (size_t i = 0; i < electrodesBlock.data.size(); ++i) {
                std::cout << electrodesBlock.data[i] << " ";
            }
            std::cout << std::endl;
        }

        // 7. Read channel conversion factors
        auto conversionWrapper = electricalSeries->readChannelConversion();
        if (conversionWrapper) {
            auto conversionBlock = conversionWrapper->values<float>();
            std::cout << "\nChannel conversion factors:" << std::endl;
            for (size_t i = 0; i < conversionBlock.data.size(); ++i) {
                std::cout << "  Channel " << i << ": " << conversionBlock.data[i] << std::endl;
            }
        }

        // 8. Close the file
        io->close();
        return 0;

    } catch (const std::exception& e) {
        std::cerr << "Error reading electrical series: " << e.what() << std::endl;
        return 1;
    }
}
```

## Method 2: Direct HDF5 Access

For more control or when working with specific HDF5 requirements:

```cpp
#include <H5Cpp.h>
#include <iostream>
#include <vector>

int readElectricalSeriesHDF5(const std::string& filePath) {
    try {
        // 1. Open HDF5 file
        H5::H5File file(filePath, H5F_ACC_RDONLY);
        
        // 2. Open the electrical series dataset
        std::string datasetPath = "/acquisition/ElectricalSeries1/data";
        H5::DataSet dataset = file.openDataSet(datasetPath);
        
        // 3. Get dataset dimensions
        H5::DataSpace dataspace = dataset.getSpace();
        int rank = dataspace.getSimpleExtentNdims();
        std::vector<hsize_t> dims(rank);
        dataspace.getSimpleExtentDims(dims.data(), nullptr);
        
        std::cout << "Dataset dimensions: ";
        for (int i = 0; i < rank; ++i) {
            std::cout << dims[i] << " ";
        }
        std::cout << std::endl;
        
        // 4. Read the data (assuming float type)
        size_t totalElements = 1;
        for (int i = 0; i < rank; ++i) {
            totalElements *= dims[i];
        }
        
        std::vector<float> data(totalElements);
        dataset.read(data.data(), H5::PredType::NATIVE_FLOAT);
        
        std::cout << "Successfully read " << totalElements << " data points" << std::endl;
        
        // 5. Print first few samples
        std::cout << "First 10 samples:" << std::endl;
        for (size_t i = 0; i < std::min(size_t(10), data.size()); ++i) {
            std::cout << "  " << data[i] << std::endl;
        }
        
        // 6. Read timestamps if available
        try {
            std::string timestampsPath = "/acquisition/ElectricalSeries1/timestamps";
            H5::DataSet timestampsDataset = file.openDataSet(timestampsPath);
            
            H5::DataSpace timestampsSpace = timestampsDataset.getSpace();
            hsize_t timestampsDim;
            timestampsSpace.getSimpleExtentDims(&timestampsDim, nullptr);
            
            std::vector<double> timestamps(timestampsDim);
            timestampsDataset.read(timestamps.data(), H5::PredType::NATIVE_DOUBLE);
            
            std::cout << "\nTimestamps (" << timestampsDim << " total):" << std::endl;
            std::cout << "First: " << timestamps[0] << " seconds" << std::endl;
            if (timestamps.size() > 1) {
                std::cout << "Last: " << timestamps.back() << " seconds" << std::endl;
                double samplingRate = 1.0 / (timestamps[1] - timestamps[0]);
                std::cout << "Sampling rate: " << samplingRate << " Hz" << std::endl;
            }
            
        } catch (const H5::Exception& e) {
            std::cout << "No timestamps found, checking for starting_time..." << std::endl;
            
            // Try to read starting_time and rate attributes
            try {
                std::string startingTimePath = "/acquisition/ElectricalSeries1/starting_time";
                H5::DataSet startingTimeDataset = file.openDataSet(startingTimePath);
                double startingTime;
                startingTimeDataset.read(&startingTime, H5::PredType::NATIVE_DOUBLE);
                
                // Read rate attribute
                H5::Attribute rateAttr = startingTimeDataset.openAttribute("rate");
                double rate;
                rateAttr.read(H5::PredType::NATIVE_DOUBLE, &rate);
                
                std::cout << "Starting time: " << startingTime << " seconds" << std::endl;
                std::cout << "Sampling rate: " << rate << " Hz" << std::endl;
                
            } catch (const H5::Exception& e2) {
                std::cout << "No timing information found" << std::endl;
            }
        }
        
        file.close();
        return 0;
        
    } catch (const H5::Exception& e) {
        std::cerr << "HDF5 error: " << e.getDetailMsg() << std::endl;
        return 1;
    }
}
```

## Method 3: Reading Specific Channels or Time Ranges

For memory-efficient reading of large datasets:

```cpp
int readElectricalSeriesPartial(const std::string& filePath, 
                               int startSample, int numSamples,
                               const std::vector<int>& channelIndices) {
    try {
        // Open file
        H5::H5File file(filePath, H5F_ACC_RDONLY);
        H5::DataSet dataset = file.openDataSet("/acquisition/ElectricalSeries1/data");
        
        // Get full dimensions
        H5::DataSpace fileSpace = dataset.getSpace();
        std::vector<hsize_t> dims(2);
        fileSpace.getSimpleExtentDims(dims.data(), nullptr);
        
        hsize_t totalSamples = dims[0];
        hsize_t totalChannels = dims[1];
        
        std::cout << "Full dataset: " << totalSamples << " samples × " 
                  << totalChannels << " channels" << std::endl;
        
        // Define hyperslab for partial reading
        std::vector<hsize_t> offset = {static_cast<hsize_t>(startSample), 0};
        std::vector<hsize_t> count = {static_cast<hsize_t>(numSamples), 
                                     static_cast<hsize_t>(channelIndices.size())};
        
        // Select specific channels
        if (!channelIndices.empty()) {
            // For simplicity, this example reads all channels then selects
            // In practice, you'd use HDF5 hyperslab selection for specific columns
            count[1] = totalChannels;
        }
        
        fileSpace.selectHyperslab(H5S_SELECT_SET, count.data(), offset.data());
        
        // Create memory space
        H5::DataSpace memSpace(2, count.data());
        
        // Read the data
        std::vector<float> data(count[0] * count[1]);
        dataset.read(data.data(), H5::PredType::NATIVE_FLOAT, memSpace, fileSpace);
        
        std::cout << "Read " << count[0] << " samples from " << count[1] 
                  << " channels" << std::endl;
        
        // Process specific channels if requested
        if (!channelIndices.empty()) {
            std::cout << "Extracting data for channels: ";
            for (int ch : channelIndices) {
                std::cout << ch << " ";
            }
            std::cout << std::endl;
            
            // Extract specific channels (assuming data is row-major: samples × channels)
            for (size_t sample = 0; sample < count[0]; ++sample) {
                std::cout << "Sample " << (startSample + sample) << ": ";
                for (int ch : channelIndices) {
                    if (ch < static_cast<int>(totalChannels)) {
                        float value = data[sample * totalChannels + ch];
                        std::cout << value << " ";
                    }
                }
                std::cout << std::endl;
                
                if (sample >= 5) {  // Only show first 5 samples
                    std::cout << "... (showing first 5 samples only)" << std::endl;
                    break;
                }
            }
        }
        
        file.close();
        return 0;
        
    } catch (const H5::Exception& e) {
        std::cerr << "HDF5 error: " << e.getDetailMsg() << std::endl;
        return 1;
    }
}
```

## Method 4: Dart/Flutter Integration

For use in your Flutter application:

```dart
// In your Dart code (lib/models/nwbfile_utils/electrical_series_reader.dart)
import 'dart:ffi';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';

class ElectricalSeriesReader {
  // Native function signatures
  late final int Function(Pointer<Char> filePath, 
                         Pointer<Float> outData, 
                         Pointer<Int32> outDataSize,
                         Pointer<Double> outTimestamps,
                         Pointer<Int32> outTimestampSize) _readElectricalSeries;

  ElectricalSeriesReader(DynamicLibrary dylib) {
    _readElectricalSeries = dylib
        .lookup<NativeFunction<Int32 Function(Pointer<Char>, Pointer<Float>, 
                                            Pointer<Int32>, Pointer<Double>, 
                                            Pointer<Int32>)>>('read_electrical_series_complete')
        .asFunction();
  }

  Future<ElectricalSeriesData?> readElectricalSeries(String filePath) async {
    // Allocate memory for output
    Pointer<Float> dataPtr = calloc<Float>(1000000);  // Adjust size as needed
    Pointer<Int32> dataSizePtr = calloc<Int32>();
    Pointer<Double> timestampsPtr = calloc<Double>(1000000);
    Pointer<Int32> timestampSizePtr = calloc<Int32>();
    
    try {
      // Convert file path to native
      Pointer<Char> pathPtr = filePath.toNativeUtf8().cast<Char>();
      
      // Call native function
      int result = _readElectricalSeries(
        pathPtr, dataPtr, dataSizePtr, timestampsPtr, timestampSizePtr);
      
      if (result == 0) {
        // Success - extract data
        int dataSize = dataSizePtr.value;
        int timestampSize = timestampSizePtr.value;
        
        Float32List data = dataPtr.asTypedList(dataSize);
        Float64List timestamps = timestampsPtr.asTypedList(timestampSize);
        
        return ElectricalSeriesData(
          data: Float32List.fromList(data),
          timestamps: Float64List.fromList(timestamps),
        );
      } else {
        print('Failed to read electrical series: error code $result');
        return null;
      }
    } finally {
      // Clean up memory
      calloc.free(dataPtr);
      calloc.free(dataSizePtr);
      calloc.free(timestampsPtr);
      calloc.free(timestampSizePtr);
    }
  }
}

class ElectricalSeriesData {
  final Float32List data;
  final Float64List timestamps;
  
  ElectricalSeriesData({required this.data, required this.timestamps});
  
  double get samplingRate {
    if (timestamps.length < 2) return 0.0;
    return 1.0 / (timestamps[1] - timestamps[0]);
  }
  
  int get numSamples => data.length;
  
  // Get data for a specific time range
  ElectricalSeriesData getTimeRange(double startTime, double endTime) {
    List<int> indices = [];
    for (int i = 0; i < timestamps.length; i++) {
      if (timestamps[i] >= startTime && timestamps[i] <= endTime) {
        indices.add(i);
      }
    }
    
    Float32List rangeData = Float32List(indices.length);
    Float64List rangeTimestamps = Float64List(indices.length);
    
    for (int i = 0; i < indices.length; i++) {
      rangeData[i] = data[indices[i]];
      rangeTimestamps[i] = timestamps[indices[i]];
    }
    
    return ElectricalSeriesData(data: rangeData, timestamps: rangeTimestamps);
  }
}
```

## Usage Examples

### Basic Usage
```cpp
int main() {
    std::string nwbFilePath = "/path/to/your/recording.nwb";
    
    // Method 1: Using AQNWB (recommended)
    std::cout << "=== Reading with AQNWB Library ===" << std::endl;
    readElectricalSeriesAQNWB(nwbFilePath);
    
    // Method 2: Direct HDF5 access
    std::cout << "\n=== Reading with Direct HDF5 ===" << std::endl;
    readElectricalSeriesHDF5(nwbFilePath);
    
    // Method 3: Partial reading
    std::cout << "\n=== Reading Partial Data ===" << std::endl;
    std::vector<int> channels = {0, 2, 3};  // Read channels 0, 2, and 3
    readElectricalSeriesPartial(nwbFilePath, 1000, 5000, channels);  // 5000 samples starting from sample 1000
    
    return 0;
}
```

### Flutter Usage
```dart
void main() async {
  final reader = ElectricalSeriesReader(dylib);
  final data = await reader.readElectricalSeries('/path/to/recording.nwb');
  
  if (data != null) {
    print('Loaded ${data.numSamples} samples at ${data.samplingRate} Hz');
    
    // Get first 10 seconds of data
    final firstTenSeconds = data.getTimeRange(0.0, 10.0);
    print('First 10 seconds: ${firstTenSeconds.numSamples} samples');
  }
}
```

## Key Points to Remember

1. **Data Types**: Electrical series data is typically stored as float32 (voltage) with float64 timestamps
2. **Dimensions**: Data is usually organized as [time × channels] or [samples × electrodes]
3. **Units**: Voltage data is typically in volts, but check the conversion factors
4. **Memory**: For large files, consider reading data in chunks to avoid memory issues
5. **Error Handling**: Always check return codes and handle exceptions
6. **File Closure**: Ensure files are properly closed after reading

## Troubleshooting

- **File not found**: Check file path and permissions
- **Dataset not found**: Verify the electrical series path (usually `/acquisition/ElectricalSeries1`)
- **Memory issues**: Use partial reading for large datasets
- **Type mismatches**: Check the actual data types in the file using HDFView or similar tools
- **Missing timestamps**: Some files use `starting_time` + `rate` instead of explicit timestamps

This guide should give you a comprehensive understanding of how to read electrical series data from NWB files using various approaches!













