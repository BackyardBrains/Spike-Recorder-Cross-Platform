#include "nwbfile_processing_plugin.hpp"
#include <iostream>
#include <memory>
#include <string>
#include <vector>

#include "Utils.hpp"
#include "Channel.hpp"
#include "nwb/NWBFile.hpp"
#include "nwb/misc/AnnotationSeries.hpp"
#include "nwb/RecordingContainers.hpp"
#include "nwb/ecephys/ElectricalSeries.hpp"
#include <H5Cpp.h>

// Global buffer to store NWB file data
std::vector<uint8_t> g_nwb_file_data;
bool g_nwb_file_ready = false;

// A very short-lived native function.
//
// For very short-lived functions, it is fine to call them on the main isolate.
// They will block the Dart execution while running the native function, so
// only do this for native functions which are guaranteed to be short-lived.
FFI_PLUGIN_EXPORT int sum(int a, int b) { return a + b; }

// A longer-lived native function, which occupies the thread calling it.
//
// Do not call these kind of native functions in the main isolate. They will
// block Dart execution. This will cause dropped frames in Flutter applications.
// Instead, call these native functions on a separate isolate.
FFI_PLUGIN_EXPORT int sum_long_running(int a, int b) {
  // Simulate work.
#if _WIN32
  Sleep(5000);
#else
  usleep(5000 * 1000);
#endif
  return a + b;
}
FFI_PLUGIN_EXPORT int32_t processing_update() {
    try {
      const std::string outputPath = "test.nwb";
      H5::Exception::dontPrint();
      std::cout << "AQNWB Recording Workflow UPDATE Example" << std::endl;
      std::cout << "================================" << std::endl;


    //   std::shared_ptr<AQNWB::IO::BaseIO> io = AQNWB::createIO("HDF5", outputPath);
    //   auto openStatus = io->open(AQNWB::IO::FileMode::Overwrite);
    //   if (openStatus != AQNWB::Types::Success) {
    //       std::cerr << "Failed to open IO" << std::endl;
    //       return 1;
    //   }

      
      std::shared_ptr<AQNWB::IO::BaseIO> readio = AQNWB::createIO("HDF5", outputPath);
      auto openStatus = readio->open(AQNWB::IO::FileMode::ReadWrite);
      if (openStatus != AQNWB::Types::Success) {
          std::cerr << "Failed to open file for reading: " << outputPath << std::endl;
          return 1;
      }
      std::cout << "Successfully opened file for reading: " << outputPath << std::endl;
      auto readNWBFile = AQNWB::NWB::RegisteredType::create<AQNWB::NWB::NWBFile>("/", readio);
      std::cout << "READING ELECTRODE TABLE:" << std::endl;
      auto readElectrodeTable1 = readNWBFile->readElectrodeTable();
      if (readElectrodeTable1) {
          std::cout << "READING LOCATION COLUMN:" << std::endl;
          try {
              auto locationColumn1 = readElectrodeTable1->readLocationColumn();
              if (locationColumn1) {
                  std::cout << "READING LOCATION COLUMN VALUES:" << std::endl;
                  auto locationColumnValues1 = locationColumn1->readData();
                  if (locationColumnValues1) {
                      auto values = locationColumnValues1->values<std::string>();
                      std::cout << "Location column values: " << values.data.size() << std::endl;
                      for (size_t i = 0; i < values.data.size(); ++i) {
                          std::cout << "  [" << i << "]: " << values.data[i] << std::endl;
                      }
                  } else {
                      std::cout << "  Warning: Could not read location column data" << std::endl;
                  }
              } else {
                  std::cout << "  Warning: Could not read location column" << std::endl;
              }
          } catch (const std::exception& e) {
              std::cout << "  Error reading location column: " << e.what() << std::endl;
          }
      } else {
          std::cout << "  Warning: Could not read electrode table" << std::endl;
      }
        
      std::unordered_set<std::string> searchTypes = {"AnnotationSeries"};
      auto foundTypes = readio->findTypes("/", searchTypes, AQNWB::IO::SearchMode::CONTINUE_ON_TYPE, true);
      
      std::cout << "Found " << foundTypes.size() << " AnnotationSeries objects:" << std::endl;
      
      if (foundTypes.empty()) {
          std::cout << "No AnnotationSeries found in the file." << std::endl;
          std::unique_ptr<AQNWB::NWB::RecordingContainers> recordingContainers = std::make_unique<AQNWB::NWB::RecordingContainers>();

          std::vector<std::string> annotationNames = {"AnnotationSeries1", "AnnotationSeries2", "NewAnnotationSeries"};
          std::vector<AQNWB::Types::SizeType> annotationContainerIndexes;
          std::cout << "Create annotation Series0." << std::endl;
          auto annotationSeriesStatus = readNWBFile->createAnnotationSeries(
              annotationNames,
              recordingContainers.get(),
              annotationContainerIndexes);
              std::cout << "Create annotation Series." << std::endl;
              if (annotationSeriesStatus != AQNWB::Types::Success) {
              std::cerr << "Failed to create AnnotationSeries" << std::endl;
              return 1;
          }
          
            std::cout << "Created annotation series at paths:" << std::endl;
            for (size_t i = 0; i < annotationNames.size(); ++i) {
                std::cout << "  " << i << ": /acquisition/" << annotationNames[i] << std::endl;
            }

            // write annotation data
            std::vector<std::string> mockAnnotations = {
                "Start recording", "Subject moved", "End recording"};
            std::vector<double> mockTimestamps = {0.1, 0.5, 1.0};
            std::vector<SizeType> positionOffset = {0};
            SizeType dataShape = mockAnnotations.size();
                
                
        
            // write to both annotation series using the correct container indexes
            recordingContainers->writeAnnotationSeriesData(
                annotationContainerIndexes[0], dataShape, mockAnnotations, mockTimestamps.data());
            recordingContainers->writeAnnotationSeriesData(
                annotationContainerIndexes[1], dataShape, mockAnnotations, mockTimestamps.data());     
        //   return 0;
      }

      // read annotation series
      std::cout << "Reading annotation series..." << std::endl;
      
      // Try to read the annotation series we just created
      std::vector<std::string> annotationPaths = {
          "/acquisition/AnnotationSeries1",
          "/acquisition/AnnotationSeries2",
          "/acquisition/NewAnnotationSeries"
      };
      
      for (const auto& annotationPath : annotationPaths) {
          try {
              std::cout << "Trying to read annotation series at: " << annotationPath << std::endl;
              
              // Create annotation series object for reading
              auto annotationSeriesObj = AQNWB::NWB::RegisteredType::create<AQNWB::NWB::AnnotationSeries>(annotationPath, readio);
              
              // Read the data from the annotation series
              auto readDataWrapper = annotationSeriesObj->readData();
              if (readDataWrapper) {
                std::cout << "Read Data Wrapper: " << std::endl;
                try {
                        std::cout << "Read Data Wrapper VALUES0: " << std::endl;
                        
                        // Add additional safety checks before calling values()
                        if (!readDataWrapper) {
                            std::cout << "  Warning: readDataWrapper is null" << std::endl;
                            continue;
                        }
                        
                        // Try to get the data with additional error handling
                        std::cout << "Attempting to read string values..." << std::endl;
                        
                        // Wrap the values() call in its own try-catch to isolate the crash
                        try {
                            auto dataBlock = readDataWrapper->values<std::string>();
                            std::cout << "Read Data Wrapper VALUES1: " << std::endl;
                            
                            // Check if dataBlock is valid
                            if (dataBlock.data.empty()) {
                                std::cout << "  Warning: Data block is empty" << std::endl;
                                continue;
                            }
                            
                            std::cout << "  ✓ Found annotation series at: " << annotationPath << std::endl;
                            std::cout << "  Data size: " << dataBlock.data.size() << std::endl;
                            
                            // Print the annotation data
                            std::cout << "  Annotations:" << std::endl;
                            for (size_t i = 0; i < dataBlock.data.size(); ++i) {
                                std::cout << "    [" << i << "]: " << dataBlock.data[i] << std::endl;
                            }
                            
                        } catch (const std::exception& e) {
                            std::cout << "  Error calling values<std::string>(): " << e.what() << std::endl;
                            continue;
                        }
                      
                      // Read associated timestamps
                      auto timestampsWrapper = annotationSeriesObj->readTimestamps();
                      if (timestampsWrapper) {
                          try {
                              auto timestampsBlock = timestampsWrapper->values<double>();
                              std::cout << "  Timestamps size: " << timestampsBlock.data.size() << std::endl;
                              std::cout << "  Timestamps:" << std::endl;
                              for (size_t i = 0; i < timestampsBlock.data.size(); ++i) {
                                  std::cout << "    [" << i << "]: " << timestampsBlock.data[i] << " seconds" << std::endl;
                              }
                          } catch (const std::exception& e) {
                              std::cout << "  Warning: Could not read timestamps: " << e.what() << std::endl;
                          }
                      }
                      
                      std::cout << std::endl;
                      
                  } catch (const std::exception& e) {
                      std::cout << "  Warning: Could not read data from " << annotationPath << ": " << e.what() << std::endl;
                  }
              } else {
                  std::cout << "  ✗ No data found at: " << annotationPath << std::endl;
              }
              
          } catch (const std::exception& e) {
              std::cout << "  ✗ No annotation series found at: " << annotationPath << std::endl;
          }
      }
      
      // Read all annotation series after adding new ones
      std::cout << "\n=== Reading All Annotation Series (After Adding New Ones) ===" << std::endl;
      
      // Updated list of all annotation series paths
      std::vector<std::string> allAnnotationPaths = {
          "/acquisition/AnnotationSeries1",
          "/acquisition/AnnotationSeries2", 
          "/acquisition/NewAnnotationSeries"
      };
      
      for (const auto& annotationPath : allAnnotationPaths) {
          try {
              std::cout << "Reading annotation series at: " << annotationPath << std::endl;
              
              // Create annotation series object for reading
              auto annotationSeriesObj = AQNWB::NWB::RegisteredType::create<AQNWB::NWB::AnnotationSeries>(annotationPath, readio);
              
              // Read the data from the annotation series
              auto readDataWrapper = annotationSeriesObj->readData();
              if (readDataWrapper) {
                  try {
                      // Add additional safety checks before calling values()
                      if (!readDataWrapper) {
                          std::cout << "  Warning: readDataWrapper is null" << std::endl;
                          continue;
                      }
                      
                      // Try to get the data with additional error handling
                      std::cout << "Attempting to read string values..." << std::endl;
                      
                      // Wrap the values() call in its own try-catch to isolate the crash
                      try {
                          auto dataBlock = readDataWrapper->values<std::string>();
                          
                          // Check if dataBlock is valid
                          if (dataBlock.data.empty()) {
                              std::cout << "  Warning: Data block is empty" << std::endl;
                              continue;
                          }
                          
                          std::cout << "  ✓ Found annotation series with " << dataBlock.data.size() << " annotations:" << std::endl;
                          
                          // Print the annotation data
                          for (size_t i = 0; i < dataBlock.data.size(); ++i) {
                              std::cout << "    [" << i << "]: " << dataBlock.data[i] << std::endl;
                          }
                          
                      } catch (const std::exception& e) {
                          std::cout << "  Error calling values<std::string>(): " << e.what() << std::endl;
                          continue;
                      }
                      
                      // Read associated timestamps
                      auto timestampsWrapper = annotationSeriesObj->readTimestamps();
                      if (timestampsWrapper) {
                          try {
                              auto timestampsBlock = timestampsWrapper->values<double>();
                              std::cout << "  Timestamps:" << std::endl;
                              for (size_t i = 0; i < timestampsBlock.data.size(); ++i) {
                                  std::cout << "    [" << i << "]: " << timestampsBlock.data[i] << " seconds" << std::endl;
                              }
                          } catch (const std::exception& e) {
                              std::cout << "  Warning: Could not read timestamps: " << e.what() << std::endl;
                          }
                      }
                      
                      std::cout << std::endl;
                      
                  } catch (const std::exception& e) {
                      std::cout << "  Warning: Could not read data from " << annotationPath << ": " << e.what() << std::endl;
                  }
              } else {
                  std::cout << "  ✗ No data found at: " << annotationPath << std::endl;
              }
              
          } catch (const std::exception& e) {
              std::cout << "  ✗ No annotation series found at: " << annotationPath << std::endl;
          }
      }
      // Read the ElectrodesTable
      auto readElectrodeTable = readNWBFile->readElectrodeTable();
        auto locationColumn = readElectrodeTable->readLocationColumn();
        auto locationColumnValues = locationColumn->readData()->values();

        // Note: channels2 was not defined, commenting out this line
        // readElectrodeTable->addElectrodes(channels2);
        readElectrodeTable->finalize();

      // read the location data. Note that both the type of the class and
      // the data values is being set for us, here, VectorDataTyped<std::string>
        readElectrodeTable = readNWBFile->readElectrodeTable();
        auto readColNames = readElectrodeTable->readColNames()->values().data;
        auto locationColumn2 = readElectrodeTable->readGroupNameColumn();
        auto locationColumnValues2 = locationColumn2->readData()->values();
        locationColumnValues.data.size();

      // Note: These operations belong to processing_init(), not processing_update()
      // auto flushStatus = io->flush();
      // if (flushStatus != AQNWB::Types::Success) {
      //     std::cerr << "Flush failed" << std::endl;
      //     return 1;
      // }
  
      // // 8) Stop recording and finalize the file
      // auto stopRecordingStatus = io->stopRecording();
      // if (stopRecordingStatus != AQNWB::Types::Success) {
      //     std::cerr << "Failed to stop recording" << std::endl;
      //     return 1;
      // }
  
      // auto finalizeStatus = nwbfile->finalize();
      // if (finalizeStatus != AQNWB::Types::Success) {
      //     std::cerr << "Failed to finalize NWB file" << std::endl;
      //     return 1;
      // }
  
      // auto closeStatus = io->close();
      // if (closeStatus != AQNWB::Types::Success) {
      //     std::cerr << "Failed to close IO" << std::endl;
      //     return 1;
      // }
  
      std::cout << "Successfully processed NWB file: " << outputPath << std::endl;
    } catch (const std::exception& e) {
      std::cerr << "Error: " << e.what() << std::endl;
      return 1;
    }
    return 0;
}

// Function to check if annotation series exist in the NWB file
FFI_PLUGIN_EXPORT int32_t check_annotation_series() {
    try {
        const std::string outputPath = "test.nwb";
        H5::Exception::dontPrint();
        std::cout << "Checking for Annotation Series in NWB file..." << std::endl;
        std::cout << "=============================================" << std::endl;

        std::shared_ptr<AQNWB::IO::BaseIO> readio = AQNWB::createIO("HDF5", outputPath);
        auto openStatus = readio->open(AQNWB::IO::FileMode::ReadOnly);
        if (openStatus != AQNWB::Types::Success) {
            std::cout << "Failed to open NWB file for reading" << std::endl;
            return -1;
        }

        // Search for AnnotationSeries types in the file
        std::unordered_set<std::string> searchTypes = {"AnnotationSeries"};
        auto foundTypes = readio->findTypes("/", searchTypes, AQNWB::IO::SearchMode::CONTINUE_ON_TYPE, true);
        
        std::cout << "Found " << foundTypes.size() << " AnnotationSeries objects:" << std::endl;
        
        if (foundTypes.empty()) {
            std::cout << "No AnnotationSeries found in the file." << std::endl;
            readio->close();
            return 0;
        }
        
        for (const auto& [path, type] : foundTypes) {
            std::cout << "  - Path: " << path << " (Type: " << type << ")" << std::endl;
        }
        
        readio->close();
        return foundTypes.size();
        
    } catch (const std::exception& e) {
        std::cout << "Error checking annotation series: " << e.what() << std::endl;
        return -1;
    }
}

// Processing initialization function
FFI_PLUGIN_EXPORT int32_t processing_init() {
  try {
    H5::Exception::dontPrint();
    std::cout << "AQNWB Recording Workflow Example" << std::endl;
    std::cout << "================================" << std::endl;

    // 1) Create the I/O object
    // /Users/macbook/Library/Containers/com.example.nwbapplication/Data/Documents
    // /Users/macbook/Library/Containers/com.example.nwbapplication/Data/Downloads/
    const std::string outputPath = "example_recording.nwb";
    std::shared_ptr<AQNWB::IO::BaseIO> io = AQNWB::createIO("HDF5", outputPath);
    auto openStatus = io->open(AQNWB::IO::FileMode::Overwrite);
    if (openStatus != AQNWB::Types::Success) {
        std::cerr << "Failed to open IO" << std::endl;
        return 1;
    }

    // 2) Create the RecordingContainers object
    std::unique_ptr<AQNWB::NWB::RecordingContainers> recordingContainers =
        std::make_unique<AQNWB::NWB::RecordingContainers>();

    // 3) Create and initialize the NWBFile
    std::unique_ptr<AQNWB::NWB::NWBFile> nwbfile = std::make_unique<AQNWB::NWB::NWBFile>(io);
    auto initStatus = nwbfile->initialize(AQNWB::generateUuid(),
                                          "Example ecephys session",
                                          "Generated by AqNWB example");
    if (initStatus != AQNWB::Types::Success) {
        std::cerr << "Failed to initialize NWB file" << std::endl;
        return 1;
    }

    // 4) Create recording metadata (ElectrodesTable)
    // Build a mock recording array: one array with 4 channels
    std::vector<AQNWB::Types::ChannelVector> recordingArrays;
    {
        AQNWB::Types::ChannelVector array1;
        const std::string groupName = "Array1";
        const AQNWB::Types::SizeType groupIndex = 0;
        for (AQNWB::Types::SizeType ch = 0; ch < 4; ++ch) {
            // name, groupName, groupIndex, localIndex, globalIndex, conversion, samplingRate, bitVolts
            array1.emplace_back(
                "chan_" + std::to_string(ch),
                groupName,
                groupIndex,
                ch,               // local index within array
                ch,               // global index across system (mock)
                1e6f,             // convert uV->V
                30000.f,          // sampling rate
                0.195f            // bitVolts
            );
        }
        recordingArrays.emplace_back(std::move(array1));
    }

    auto elecTableStatus = nwbfile->createElectrodesTable(recordingArrays);
    if (elecTableStatus != AQNWB::Types::Success) {
        std::cerr << "Failed to create electrodes table" << std::endl;
        return 1;
    }

    // 5) Create datasets (ElectricalSeries) and add to RecordingContainers
    std::vector<std::string> recordingNames = {"ElectricalSeries1"};
    std::vector<AQNWB::Types::SizeType> containerIndexes;
    auto elecSeriesStatus = nwbfile->createElectricalSeries(
        recordingArrays,
        recordingNames,
        AQNWB::IO::BaseDataType::I16,
        recordingContainers.get(),
        containerIndexes);
    if (elecSeriesStatus != AQNWB::Types::Success) {
        std::cerr << "Failed to create ElectricalSeries" << std::endl;
        return 1;
    }

    // 6) Start the recording
    auto startRecordingStatus = io->startRecording();
    if (startRecordingStatus != AQNWB::Types::Success) {
        std::cerr << "Failed to start recording" << std::endl;
        return 1;
    }

    // 7) Write data
    // Simulate writing a short block of data for each channel in the first ElectricalSeries
    const AQNWB::Types::SizeType containerIndex = containerIndexes.at(0);
    const auto& channels = recordingArrays[0];
    const AQNWB::Types::SizeType numSamples = 1000; // samples per write

    // timestamps at 30 kHz
    std::vector<double> timestamps(numSamples);
    const double samplingRate = static_cast<double>(channels[0].getSamplingRate());
    const double dt = 1.0 / samplingRate;
    for (AQNWB::Types::SizeType i = 0; i < numSamples; ++i) {
        timestamps[i] = static_cast<double>(i) * dt;
    }

    // write data per-channel
    for (const auto& ch : channels) {
        std::vector<int16_t> data(numSamples);
        for (AQNWB::Types::SizeType i = 0; i < numSamples; ++i) {
            // simple mock waveform for demonstration
            data[i] = static_cast<int16_t>((i % 200) - 100);
        }

        auto writeStatus = recordingContainers->writeElectricalSeriesData(
            containerIndex,
            ch,
            numSamples,
            static_cast<const void*>(data.data()),
            static_cast<const void*>(timestamps.data()));

        if (writeStatus != AQNWB::Types::Success) {
            std::cerr << "Failed to write data for channel " << ch.getName() << std::endl;
            return 1;
        }
    }

    // Ensure data is flushed to disk
    auto flushStatus = io->flush();
    if (flushStatus != AQNWB::Types::Success) {
        std::cerr << "Flush failed" << std::endl;
        return 1;
    }

    // 8) Stop recording and finalize the file
    auto stopRecordingStatus = io->stopRecording();
    if (stopRecordingStatus != AQNWB::Types::Success) {
        std::cerr << "Failed to stop recording" << std::endl;
        return 1;
    }

    auto finalizeStatus = nwbfile->finalize();
    if (finalizeStatus != AQNWB::Types::Success) {
        std::cerr << "Failed to finalize NWB file" << std::endl;
        return 1;
    }

    auto closeStatus = io->close();
    if (closeStatus != AQNWB::Types::Success) {
        std::cerr << "Failed to close IO" << std::endl;
        return 1;
    }

    std::cout << "Successfully wrote example recording to: " << outputPath << std::endl;
    
    // Store the NWB file data in our global buffer
    // For now, we'll create a simple mock NWB file structure
    g_nwb_file_data.clear();
    
    // Create a simple mock NWB file header
    std::string mock_nwb_content = 
        "NWB File Header\n"
        "Version: 2.0\n"
        "Created: " + outputPath + "\n"
        "Electrodes: 4\n"
        "ElectricalSeries: 1\n"
        "Data Points: 1000\n"
        "Sampling Rate: 30000 Hz\n"
        "File Size: Mock Data\n";
    
    g_nwb_file_data.assign(mock_nwb_content.begin(), mock_nwb_content.end());
    g_nwb_file_ready = true;
    
    return 0;
  } catch (const std::exception& e) {
      std::cerr << "Error: " << e.what() << std::endl;
      return 1;
  }    
  return -1;
}

// Function to get the NWB file data
FFI_PLUGIN_EXPORT int get_nwb_file_size() {
    if (!g_nwb_file_ready) {
        return -1; // File not ready
    }
    return static_cast<int>(g_nwb_file_data.size());
}

// Function to copy NWB file data to a provided buffer
FFI_PLUGIN_EXPORT int get_nwb_file_data(uint8_t* buffer, int buffer_size) {
    if (!g_nwb_file_ready) {
        return -1; // File not ready
    }
    
    if (buffer == nullptr || buffer_size < static_cast<int>(g_nwb_file_data.size())) {
        return -2; // Invalid buffer or buffer too small
    }
    
    std::copy(g_nwb_file_data.begin(), g_nwb_file_data.end(), buffer);
    return static_cast<int>(g_nwb_file_data.size());
}
