#include "nwbfile_processing_plugin.hpp"
#include <iostream>
#include <memory>
#include <string>
#include <vector>
#include <cstdarg>
#include <algorithm>

#include "Utils.hpp"
#include "Channel.hpp"
#include "nwb/NWBFile.hpp"
#include "nwb/misc/AnnotationSeries.hpp"
#include "nwb/RecordingContainers.hpp"
#include "nwb/device/Device.hpp"
#include "nwb/ecephys/ElectricalSeries.hpp"
#include <H5Cpp.h>

#include <string>
#define IS_WIN32 defined(WIN32) || defined(_WIN32) || defined(__WIN32)
void file_log_nwbfile(const char *fmt, ...) {
    va_list args;
    va_start(args, fmt);
#ifdef __ANDROID__
    __android_log_vprint(ANDROID_LOG_VERBOSE, "ndk", fmt, args);
#else
    vprintf(fmt, args);
#endif
    va_end(args);
}

// Global buffer to store NWB file data
std::vector<uint8_t> g_nwb_file_data;
bool g_nwb_file_ready = false;

// Helper function to recursively list HDF5 groups and datasets
void listHDF5Contents(H5::H5File& file, const std::string& groupName = "/", int depth = 0) {
    try {
        std::string indent(depth * 2, ' ');
        std::cout << indent << "📁 Group: " << groupName << std::endl;
        
        H5::Group group = (groupName == "/") ? file.openGroup("/") : file.openGroup(groupName);
        hsize_t numObjs = group.getNumObjs();
        
        for (hsize_t i = 0; i < numObjs; i++) {
            std::string objName = group.getObjnameByIdx(i);
            H5G_obj_t objType = group.getObjTypeByIdx(i);
            std::string fullPath = (groupName == "/") ? "/" + objName : groupName + "/" + objName;
            
            if (objType == H5G_GROUP) {
                if (depth < 3) {  // Limit recursion depth
                    listHDF5Contents(file, fullPath, depth + 1);
                } else {
                    std::cout << indent << "  📁 " << objName << " (group, not expanded)" << std::endl;
                }
            } else if (objType == H5G_DATASET) {
                try {
                    H5::DataSet dataset = file.openDataSet(fullPath);
                    H5::DataSpace dataspace = dataset.getSpace();
                    int rank = dataspace.getSimpleExtentNdims();
                    std::vector<hsize_t> dims(rank);
                    dataspace.getSimpleExtentDims(dims.data(), nullptr);
                    
                    std::cout << indent << "  📊 " << objName << " (dataset, dims: ";
                    for (int j = 0; j < rank; j++) {
                        std::cout << dims[j];
                        if (j < rank - 1) std::cout << "×";
                    }
                    std::cout << ")" << std::endl;
                } catch (const H5::Exception& e) {
                    std::cout << indent << "  📊 " << objName << " (dataset, could not read dimensions)" << std::endl;
                }
            }
        }
    } catch (const H5::Exception& e) {
        std::cout << "  ❌ Error listing contents of " << groupName << ": " << e.getDetailMsg() << std::endl;
    }
}
inline std::vector<AQNWB::Types::ChannelVector> getMockChannelArrays(
    SizeType numChannels = 2,
    SizeType numArrays = 2,
    std::string groupName = "array")
{
  std::vector<AQNWB::Types::ChannelVector> arrays(numArrays);
  for (SizeType i = 0; i < numArrays; i++) {
    std::vector<AQNWB::Channel> chGroup;
    for (SizeType j = 0; j < numChannels; j++) {
      AQNWB::Channel ch("ch" + std::to_string(j),
                 groupName + std::to_string(i),
                 i,
                 j,
                 i * numArrays + j);
      chGroup.push_back(ch);
    }
    arrays[i] = chGroup;
  }
  return arrays;
}

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

// Processing initialization function
std::shared_ptr<AQNWB::IO::BaseIO> io;
std::unique_ptr<AQNWB::NWB::NWBFile> nwbfile;
std::unique_ptr<AQNWB::NWB::RecordingContainers> recordingContainers;
std::vector<AQNWB::Types::ChannelVector> recordingArrays;
std::vector<AQNWB::Types::SizeType> containerIndexes;
std::string outputPath;

FFI_PLUGIN_EXPORT int32_t processing_init(const char* path, int sampleRate, int channelCount, const char* deviceInfo, const char* deviceManufacturer) {
    try {
        H5::Exception::dontPrint();
        std::cout << "AQNWB Recording Workflow Example" << std::endl;
        std::cout << "================================" << std::endl;
    
        // 1) Create the I/O object
        // /Users/macbook/Library/Containers/com.example.nwbapplication/Data/Documents
        // /Users/macbook/Library/Containers/com.example.nwbapplication/Data/Downloads/
        outputPath = path;
        // outputPath = "/Users/macbook/Library/Containers/com.example.nwbapplication/Data/Documents/example_recording_multiple_channels.nwb";
        // std::shared_ptr<AQNWB::IO::BaseIO> io = AQNWB::createIO("HDF5", outputPath);
        io = AQNWB::createIO("HDF5", outputPath);
        auto openStatus = io->open(AQNWB::IO::FileMode::Overwrite);
        
        if (openStatus != AQNWB::Types::Success) {
            std::cerr << "Failed to open IO" << std::endl;
            return 1;
        }

        // 2) Create the RecordingContainers object
        recordingContainers = std::make_unique<AQNWB::NWB::RecordingContainers>();
    
        // 3) Create and initialize the NWBFile
        nwbfile = std::make_unique<AQNWB::NWB::NWBFile>(io);
        auto initStatus = nwbfile->initialize(AQNWB::generateUuid(),
                                                "Example ecephys session",
                                                "Generated by AqNWB example");
        if (initStatus != AQNWB::Types::Success) {
            std::cerr << "Failed to initialize NWB file" << std::endl;
            return 1;
        }

        // 3.5) Add device information (AFTER NWBFile initialization)
        std::cout << "Adding device information..." << std::endl;
        std::unique_ptr<AQNWB::NWB::Device> device = 
            std::make_unique<AQNWB::NWB::Device>("/general/devices/recording_device", io);
        
        // Initialize the device with description and manufacturer
        device->initialize(deviceInfo, deviceManufacturer);
        
        std::cout << "Device information added successfully" << std::endl;
        std::cout << "Init Status: " << initStatus << "  " << channelCount << std::endl;

        // 4) Create recording metadata (ElectrodesTable)
        // Build a mock recording array: one array with 4 channels
        // recordingArrays.clear();
        std::vector<AQNWB::Types::ChannelVector> tempRecordingArrays;
        {
            AQNWB::Types::ChannelVector array1;
            const std::string groupName = "Array1";
            const AQNWB::Types::SizeType groupIndex = 0;
            for (AQNWB::Types::SizeType ch = 0; ch < channelCount; ++ch) {
                // name, groupName, groupIndex, localIndex, globalIndex, conversion, samplingRate, bitVolts
                array1.emplace_back(
                    "chan_" + std::to_string(ch),
                    groupName,
                    groupIndex,
                    ch,               // local index within array
                    ch,               // global index across system (mock)
                    1e6f,             // convert uV->V (correct conversion factor)
                    static_cast<float>(sampleRate),  // sampling rate
                    0.195f            // bitVolts (correct bit volts)
                );
            }
            tempRecordingArrays.emplace_back(std::move(array1));
        }
        recordingArrays = tempRecordingArrays;
        auto elecTableStatus = nwbfile->createElectrodesTable(recordingArrays);
        if (elecTableStatus != AQNWB::Types::Success) {
            std::cerr << "Failed to create electrodes table" << std::endl;
            return 1;
        }
    
        std::cout << "Recording arrays & table created: " << channelCount << std::endl;
        std::vector<std::string> recordingNames = {"ElectricalSeries1"};
        
        // Create ONE ElectricalSeries for all channels (not one per channel)
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
    
        std::cout << "START RECORDING" << 111.0 << std::endl;

        auto startRecordingStatus = io->startRecording();
        if (startRecordingStatus != AQNWB::Types::Success) {
            std::cerr << "Failed to start recording" << std::endl;
            return 1;
        }
    

        return 0;
    } catch (const std::exception& e) {
        std::cerr << "Error: " << e.what() << std::endl;
        return 1;
    }    
    return -1;
}

int mutliplier = 0;
int numSamplesCounter = 0;
FFI_PLUGIN_EXPORT int32_t nwbfile_add_electrical_series(short* inSamples, int* samplesCount, int selectedChannel, int channelCount, int isFinishRecording) {
    // std::cout << "AQNWB nwbfile_add_electrical_series" << std::endl;
    
    // Validate input parameters
    if (!inSamples || !samplesCount || channelCount <= 0) {
        std::cerr << "Invalid input parameters" << std::endl;
        return -1;
    }
    
    // Validate sample counts to prevent buffer overruns
    for (int i = 0; i < channelCount; i++) {
        if (samplesCount[i] <= 0) {
            std::cerr << "Invalid sample count for channel " << i << ": " << samplesCount[i] << std::endl;
            return -1;
        }
    }
    
    short** arrSamples = nullptr;
    try {
        // Allocate memory for channel pointers
        arrSamples = new short*[channelCount];
        
        // Initialize all pointers to nullptr for safe cleanup
        for (int i = 0; i < channelCount; i++) {
            arrSamples[i] = nullptr;
        }
        
        // Allocate memory for each channel
        for (int i = 0; i < channelCount; i++) {
            try {
                arrSamples[i] = new short[samplesCount[i]];
                std::copy(inSamples + i * samplesCount[i], inSamples + (i + 1) * samplesCount[i], arrSamples[i]);
            } catch (const std::bad_alloc& e) {
                std::cerr << "Memory allocation failed for channel " << i << ": " << e.what() << std::endl;
                // Clean up already allocated memory
                for (int j = 0; j < i; j++) {
                    delete[] arrSamples[j];
                }
                delete[] arrSamples;
                return -1;
            }
        }

    // auto elecTableStatus = nwbfile->createElectrodesTable(recordingArrays);
    // if (elecTableStatus != AQNWB::Types::Success) {
    //     std::cerr << "Failed to create electrodes table" << std::endl;
    //     return 1;
    // }
    // std::cout << "AQNWB createdElectrodesTable" << std::endl;

    
    // 6) Start the recording
    // file_log_nwbfile("START RECORDING: %f", 111.0);

    // 7) Write data
    // Simulate writing a short block of data for each channel in the first ElectricalSeries
    const AQNWB::Types::SizeType containerIndex = containerIndexes.at(0);
    const auto& channels = recordingArrays[0];
    // const AQNWB::Types::SizeType numSamples = 1000; // samples per write
    const AQNWB::Types::SizeType numSamples = samplesCount[0]; // samples per write

    // std::cout << "AQNWB NUM SAMPLES " << samplesCount[0] << std::endl;
    // timestamps at 30 kHz
    std::vector<double> timestamps(numSamples );
    const double samplingRate = static_cast<double>(channels[0].getSamplingRate());
    const double dt = 1.0 / samplingRate;
    // mutliplier = 0;
    numSamplesCounter += numSamples;
    mutliplier = numSamplesCounter / samplingRate;
    for (AQNWB::Types::SizeType i = 0; i < numSamples; ++i) {
        timestamps[i] = (numSamplesCounter + i) * dt;
    }
    // file_log_nwbfile("timestamps: %f", timestamps[0]);
    // std::cout << "TIMESTAMPS " << timestamps[0] << std::endl;
    // std::cout << "TIMESTAMPS " << timestamps[1] << std::endl;

        // Write data per-channel (original approach)
        int channelIndex = 0;
        for (const auto& ch : channels) {
            auto writeStatus = recordingContainers->writeElectricalSeriesData(
                containerIndex,
                ch,
                samplesCount[channelIndex],
                static_cast<const void*>(arrSamples[channelIndex]),
                static_cast<const void*>(timestamps.data()));

            if (writeStatus != AQNWB::Types::Success) {
                std::cout << "WRITE ERROR " << samplesCount[channelIndex] << " CHANNEL: " << channelIndex << std::endl;
                std::cerr << "Failed to write data for channel " << ch.getName() << writeStatus << std::endl;
                // Clean up memory before returning
                if (arrSamples != nullptr) {
                    for (int i = 0; i < channelCount; i++) {
                        if (arrSamples[i] != nullptr) {
                            delete[] arrSamples[i];
                        }
                    }
                    delete[] arrSamples;
                }                
                return 1;
            }
            channelIndex++;        
        }

        // Ensure data is flushed to disk
        auto flushStatus = io->flush();
        if (flushStatus != AQNWB::Types::Success) {
            std::cerr << "Flush failed" << std::endl;
            // Clean up memory before returning
            if (arrSamples != nullptr) {
                for (int i = 0; i < channelCount; i++) {
                    if (arrSamples[i] != nullptr) {
                        delete[] arrSamples[i];
                    }
                }
                delete[] arrSamples;
            }
            return 1;
        }

        if (isFinishRecording == 1) {
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
        
            std::cout << "Successfully wrote example recording to: " << outputPath << std::endl;
    
            // Clean up memory
            if (arrSamples != nullptr) {
                for (int i = 0; i < channelCount; i++) {
                    if (arrSamples[i] != nullptr) {
                        delete[] arrSamples[i];
                    }
                }
                delete[] arrSamples;
            }
        
            // Close IO after finalization (matching reference order)
            auto closeStatus = io->close();
            if (closeStatus != AQNWB::Types::Success) {
                std::cerr << "Failed to close IO" << std::endl;
                return 1;
            }
            std::cout << "\n=== IO CLOSED ===" << std::endl;

        } else {
            // Clean up memory for non-finishing calls
            if (arrSamples != nullptr) {
                for (int i = 0; i < channelCount; i++) {
                    if (arrSamples[i] != nullptr) {
                        delete[] arrSamples[i];
                    }
                }
                delete[] arrSamples;
            }
        }
        
    } catch (const std::exception& e) {
        std::cerr << "Error in nwbfile_add_electrical_series: " << e.what() << std::endl;
        // Clean up memory in case of exception
        if (arrSamples != nullptr) {
            for (int i = 0; i < channelCount; i++) {
                if (arrSamples[i] != nullptr) {
                    delete[] arrSamples[i];
                }
            }
            delete[] arrSamples;
        }
        return 1;
    }
    
    return 0; // Success
}


FFI_PLUGIN_EXPORT int32_t nwbfile_read_electrical_series(short* outSamples, int* outSamplesCount, int selectedChannel, int channelCount) {
    std::cout << "AQNWB nwbfile_read_electrical_series" << std::endl;
    
    // outputPath = "/Users/macbook/Library/Containers/com.example.nwbapplication/Data/Documents/example_recording_multiple_channels.nwb";
    // 1. Open the NWB file for reading
    // std::shared_ptr<BaseIO> io = AQNWB::createIO("HDF5", filePath);
    // auto openStatus = io->open(FileMode::ReadOnly);
    // if (openStatus != AQNWB::Types::Success) {
    //     std::cerr << "Failed to open NWB file: " << filePath << std::endl;
    //     return 1;
    // }
    std::string filePath = outputPath;
    std::shared_ptr<AQNWB::IO::BaseIO> io = AQNWB::createIO("HDF5", filePath);
    auto openStatus = io->open(AQNWB::IO::FileMode::ReadOnly);
    if (openStatus != AQNWB::Types::Success) {
        std::cerr << "Failed to open NWB file: " << filePath << std::endl;
        return 1;
    }
    std::cout << "AQNWB open IO successfully" << std::endl;

    // auto nwbFile = AQNWB::NWB::RegisteredType::create<AQNWB::NWB::NWBFile>("/", io);
    // // 2. Create NWBFile object for reading
    // if (!nwbFile) {
    //     std::cerr << "Failed to create NWBFile object" << std::endl;
    //     return 1;
    // }
    // std::cout << "AQNWB open NWBFILE successfully" << std::endl;

    
    // 3. Access the electrical series (typically in /acquisition/)
    // std::string seriesPath = "/acquisition/ElectricalSeries1";
    // auto electricalSeries = AQNWB::NWB::RegisteredType::create<AQNWB::NWB::ElectricalSeries>(seriesPath, io);
    // if (!electricalSeries) {
    //     std::cerr << "ElectricalSeries not found at: " << seriesPath << std::endl;
    //     return 1;
    // }
    // std::cout << "AQNWB open ELECTRICAL SERIES successfully" << std::endl;

    // 4. Read the voltage data using direct HDF5 approach to avoid AQNWB template issues
    std::cout << "Reading electrical series data using direct HDF5 approach..." << std::endl;
    
    try {
        // Use direct HDF5 access to bypass the problematic AQNWB template system
        // std::string dataPath = seriesPath + "/data";
        // std::cout << "Opening HDF5 dataset: " << dataPath << std::endl;
        
        // Get the HDF5 file handle from the IO object
        // This is a workaround to access the underlying HDF5 file
        
        // For now, let's use the direct HDF5 approach we used before
        std::unique_ptr<H5::H5File> h5file;
        try {
            h5file = std::make_unique<H5::H5File>(outputPath, H5F_ACC_RDONLY);
            std::cout << "✅ Opened HDF5 file directly" << std::endl;
        } catch (const H5::FileIException& e) {
            std::cerr << "❌ Failed to open HDF5 file: " << e.getDetailMsg() << std::endl;
            return -1;
        }
        
        // Open the dataset directly
        H5::DataSet dataset;
        try {
            dataset = h5file->openDataSet("/acquisition/ElectricalSeries1/data");
            std::cout << "✅ Opened electrical series dataset" << std::endl;
        } catch (const H5::DataSetIException& e) {
            std::cerr << "❌ Failed to open dataset: " << e.getDetailMsg() << std::endl;
            return -1;
        }
        
        // Get dataset dimensions
        H5::DataSpace dataspace = dataset.getSpace();
        int rank = dataspace.getSimpleExtentNdims();
        // std::vector<hsize_t> dims(rank);
        hsize_t* dims = new hsize_t[rank];
        dataspace.getSimpleExtentDims(dims, nullptr);
        
        std::cout << "📊 Dataset dimensions: ";
        for (int i = 0; i < rank; ++i) {
            std::cout << dims[i];
            if (i < rank - 1) std::cout << " × ";
        }
        std::cout << std::endl;
        
        // Calculate total samples and channels
        hsize_t totalSamples = dims[0];
        hsize_t totalChannels = (rank > 1) ? dims[1] : 1;
        
        std::cout << "📊 Total samples: " << totalSamples << std::endl;
        std::cout << "📊 Total channels: " << totalChannels << std::endl;
        
        // Validate channel selection
        if (selectedChannel >= static_cast<int>(totalChannels)) {
            std::cerr << "❌ Invalid channel: " << selectedChannel << " (max: " << (totalChannels - 1) << ")" << std::endl;
            *outSamplesCount = 0;
            return -1;
        }
        
        // Read data for the selected channel
        std::vector<int16_t> channelData(totalSamples);
        
        if (rank == 1) {
            // 1D data - read all
            dataset.read(channelData.data(), H5::PredType::NATIVE_INT16);
        } else {
            // SINGLE CHANNEL
            // 2D data - read specific channel
            // Define hyperslab to read one channel
            /*
            hsize_t offset[2] = {0, static_cast<hsize_t>(selectedChannel)};
            hsize_t count[2] = {totalSamples, 1};
            dataspace.selectHyperslab(H5S_SELECT_SET, count, offset);
            
            // Define memory space
            hsize_t memDims[1] = {totalSamples};
            H5::DataSpace memSpace(1, memDims);
            
            // Read the data
            dataset.read(channelData.data(), H5::PredType::NATIVE_INT16, memSpace, dataspace);
            */
            // Option 2: Read All Channles at once
            std::vector<int16_t> allData(totalSamples * totalChannels);
            dataset.read(allData.data(), H5::PredType::NATIVE_INT16);
            
            // Extract specific channel
            for (short ch = 0; ch < totalChannels; ++ch) {
                for (size_t i = 0; i < totalSamples; ++i) {
                    channelData[i] = allData[i * totalChannels + ch];
                }
            }

        }
        
        std::cout << "✅ Successfully read " << totalSamples << " samples from channel " << selectedChannel << std::endl;
        
        // Copy data to output buffer
        *outSamplesCount = static_cast<int>(totalSamples);
        for (size_t i = 0; i < totalSamples; ++i) {
            outSamples[i] = channelData[i];
        }
        
        // Print first 10 samples for verification
        std::cout << "🔍 First 10 samples from channel " << selectedChannel << ":" << std::endl;
        // size_t samplesToShow = (totalSamples < 10) ? totalSamples : 10;
        size_t samplesToShow = 7;
        for (size_t i = 0; i < samplesToShow; ++i) {
            std::cout << "  Sample " << i << ": " << outSamples[i] << std::endl;
        }
        
        io->close();
        h5file->close();
        delete[] dims;

        std::cout << "✅ CLOSE FILE " << totalSamples << std::endl;
        
    } catch (const H5::Exception& e) {
        std::cerr << "❌ HDF5 Error: " << e.getDetailMsg() << std::endl;
        *outSamplesCount = 0;
        return -1;
    } catch (const std::exception& e) {
        std::cerr << "❌ General Error: " << e.what() << std::endl;
        *outSamplesCount = 0;
        return -1;
    }
    return 0;


    // 5. Read timestamps (temporarily disabled to fix compilation)
    // std::cout << "Timestamp reading temporarily disabled" << std::endl;
    // auto timestampsWrapper = electricalSeries->readTimestamps();
    // if (timestampsWrapper) {
    //     auto timestampsBlock = timestampsWrapper->values<double>();
    //     std::cout << "\nTimestamp information:" << std::endl;
    //     std::cout << "Number of timestamps: " << timestampsBlock.data.size() << std::endl;
    //     
    //     if (!timestampsBlock.data.empty()) {
    //         std::cout << "First timestamp: " << timestampsBlock.data[0] << " seconds" << std::endl;
    //         std::cout << "Last timestamp: " << timestampsBlock.data.back() << " seconds" << std::endl;
    //         
    //         // Calculate sampling rate
    //         if (timestampsBlock.data.size() > 1) {
    //             double samplingRate = 1.0 / (timestampsBlock.data[1] - timestampsBlock.data[0]);
    //             std::cout << "Estimated sampling rate: " << samplingRate << " Hz" << std::endl;
    //         }
    //     }
    // }
    // std::cout << "AQNWB read readTimestamps successfully" << std::endl;

    // Electrode and conversion information already read above during data extraction

    // 8. Close the file
    // io->close();
    // return 0;


    // io = AQNWB::createIO("HDF5", outputPath);
    // auto openStatus = io->open(AQNWB::IO::FileMode::Overwrite);
    
    // if (openStatus != AQNWB::Types::Success) {
    //     std::cerr << "Failed to open IO" << std::endl;
    //     return 1;
    // }

    // // 2) Create the RecordingContainers object
    // recordingContainers = std::make_unique<AQNWB::NWB::RecordingContainers>();

    // // 3) Create and initialize the NWBFile
    // nwbfile = std::make_unique<AQNWB::NWB::NWBFile>(io);
    // auto initStatus = nwbfile->initialize(AQNWB::generateUuid(),
    //                                         "Example ecephys session",
    //                                         "Generated by AqNWB example");
    // if (initStatus != AQNWB::Types::Success) {
    //     std::cerr << "Failed to initialize NWB file" << std::endl;
    //     return 1;
    // }
    // std::cout << "Init Status: " << initStatus << std::endl;

    // AQNWB::NWB::AcquisitionContainer acquisition = nwbfile.getAcquisition();

    // std::string series_name = "ElectricalSeries1";
    // if (acquisition.hasTimeSeries(series_name)) {
    //     // Retrieve the ElectricalSeries object
    //     AQNWB::NWB::TimeSeries elec_series = acquisition.getTimeSeries(series_name);
    //     AQNWB::NWB::NDArray<float> data_array = elec_series.getData<float>();
        
    //     std::cout << "Successfully read ElectricalSeries: " << series_name << std::endl;
    //     std::cout << "Data dimensions: " << data_array.getDimensions().size() << std::endl;

    //     const float* data_ptr = data_array.getData();
    //     std::cout << "First 10 data points:" << std::endl;
    //     for (size_t i = 0; i < 10 && i < data_array.size(); ++i) {
    //         std::cout << data_ptr[i] << " ";
    //     }
    //     std::cout << std::endl;
    // } else {
    //     std::cerr << "ElectricalSeries with name '" << series_name << "' not found." << std::endl;
    // }
    
    // h5io.close();    

}

// FFI_PLUGIN_EXPORT int32_t processing_init(const char* path) {
//     try {
//       H5::Exception::dontPrint();
//       std::cout << "AQNWB Recording Workflow Example" << std::endl;
//       std::cout << "================================" << std::endl;
  
//       // 1) Create the I/O object
//       // /Users/macbook/Library/Containers/com.example.nwbapplication/Data/Documents
//       // /Users/macbook/Library/Containers/com.example.nwbapplication/Data/Downloads/
//       const std::string outputPath = "/Users/macbook/Library/Containers/com.example.nwbapplication/Data/Documents/example_recording2.nwb";
//       std::shared_ptr<AQNWB::IO::BaseIO> io = AQNWB::createIO("HDF5", outputPath);
//       auto openStatus = io->open(AQNWB::IO::FileMode::Overwrite);
//       if (openStatus != AQNWB::Types::Success) {
//           std::cerr << "Failed to open IO" << std::endl;
//           return 1;
//       }
  
//       // 2) Create the RecordingContainers object
//       std::unique_ptr<AQNWB::NWB::RecordingContainers> recordingContainers =
//           std::make_unique<AQNWB::NWB::RecordingContainers>();
  
//       // 3) Create and initialize the NWBFile
//       std::unique_ptr<AQNWB::NWB::NWBFile> nwbfile = std::make_unique<AQNWB::NWB::NWBFile>(io);
//       auto initStatus = nwbfile->initialize(AQNWB::generateUuid(),
//                                             "Example ecephys session",
//                                             "Generated by AqNWB example");
//       if (initStatus != AQNWB::Types::Success) {
//           std::cerr << "Failed to initialize NWB file" << std::endl;
//           return 1;
//       }

//       // 4) Create recording metadata (ElectrodesTable)
//       // Build a mock recording array: one array with 4 channels
//       std::vector<AQNWB::Types::ChannelVector> recordingArrays;
//       {
//           AQNWB::Types::ChannelVector array1;
//           const std::string groupName = "Array1";
//           const AQNWB::Types::SizeType groupIndex = 0;
//           for (AQNWB::Types::SizeType ch = 0; ch < 4; ++ch) {
//               // name, groupName, groupIndex, localIndex, globalIndex, conversion, samplingRate, bitVolts
//               array1.emplace_back(
//                   "chan_" + std::to_string(ch),
//                   groupName,
//                   groupIndex,
//                   ch,               // local index within array
//                   ch,               // global index across system (mock)
//                   1e6f,             // convert uV->V
//                   30000.f,          // sampling rate
//                   0.195f            // bitVolts
//               );
//           }
//           recordingArrays.emplace_back(std::move(array1));
//       }
        
//         std::vector<AQNWB::Types::ChannelVector> recordingArrays2;
//         {
//             AQNWB::Types::ChannelVector array12;
//             const std::string groupName = "Array2";
//             const AQNWB::Types::SizeType groupIndex = 0;
//             for (AQNWB::Types::SizeType ch = 0; ch < 7; ++ch) {
//                 // name, groupName, groupIndex, localIndex, globalIndex, conversion, samplingRate, bitVolts
//                 array12.emplace_back(
//                     "chan_" + std::to_string(ch),
//                     groupName,
//                     groupIndex,
//                     ch,               // local index within array
//                     ch,               // global index across system (mock)
//                     1e6f,             // convert uV->V
//                     30000.f,          // sampling rate
//                     0.195f            // bitVolts
//                 );
//             }
//             recordingArrays2.emplace_back(std::move(array12));
//         }
  
//       auto elecTableStatus = nwbfile->createElectrodesTable(recordingArrays);
//       if (elecTableStatus != AQNWB::Types::Success) {
//           std::cerr << "Failed to create electrodes table" << std::endl;
//           return 1;
//       }
  
//       // 5) Create datasets (ElectricalSeries) and add to RecordingContainers
// //        std::vector<AQNWB::Types::ChannelVector> mockArrays = getMockChannelArrays();
// //        AQNWB::NWB::ElectricalSeries es = AQNWB::NWB::ElectricalSeries(outputPath, io);
// //        AQNWB::NWB::IO::ArrayDataSetConfig config(
// //            dataType, SizeArray {0, mockArrays[0].size()}, SizeArray {1, 1});
// //        es.initialize(config, mockArrays[0], "no description");
        
        
//       std::vector<std::string> recordingNames = {"ElectricalSeries1"};
//       std::vector<AQNWB::Types::SizeType> containerIndexes;
//       auto elecSeriesStatus = nwbfile->createElectricalSeries(
//           recordingArrays,
//           recordingNames,
//           AQNWB::IO::BaseDataType::I16,
//           recordingContainers.get(),
//           containerIndexes);
//       if (elecSeriesStatus != AQNWB::Types::Success) {
//           std::cerr << "Failed to create ElectricalSeries" << std::endl;
//           return 1;
//       }
      
//       // Create annotation series
//       std::vector<std::string> annotationNames = {"AnnotationSeries1", "AnnotationSeries2", "NewAnnotationSeries"};
//       std::vector<AQNWB::Types::SizeType> annotationContainerIndexes;
//       auto annotationSeriesStatus = nwbfile->createAnnotationSeries(
//           annotationNames,
//           recordingContainers.get(),
//           annotationContainerIndexes);
//       if (annotationSeriesStatus != AQNWB::Types::Success) {
//           std::cerr << "Failed to create AnnotationSeries" << std::endl;
//           return 1;
//       }
      
//       std::cout << "Created annotation series at paths:" << std::endl;
//       for (size_t i = 0; i < annotationNames.size(); ++i) {
//           std::cout << "  " << i << ": /acquisition/" << annotationNames[i] << std::endl;
//       }
  
//     // write annotation data
//     std::vector<std::string> mockAnnotations = {
//         "Start recording", "Subject moved", "End recording"};
//     std::vector<double> mockTimestamps = {0.1, 0.5, 1.0};
//     std::vector<SizeType> positionOffset = {0};
//     SizeType dataShape = mockAnnotations.size();
        
        

//     // write to both annotation series using the correct container indexes
//     recordingContainers->writeAnnotationSeriesData(
//         annotationContainerIndexes[0], dataShape, mockAnnotations, mockTimestamps.data());
//     recordingContainers->writeAnnotationSeriesData(
//         annotationContainerIndexes[1], dataShape, mockAnnotations, mockTimestamps.data());

        
//       // 6) Start the recording
//       auto startRecordingStatus = io->startRecording();
//       if (startRecordingStatus != AQNWB::Types::Success) {
//           std::cerr << "Failed to start recording" << std::endl;
//           return 1;
//       }
  
//       // 7) Write data
//       // Simulate writing a short block of data for each channel in the first ElectricalSeries
//       const AQNWB::Types::SizeType containerIndex = containerIndexes.at(0);
//       const auto& channels = recordingArrays[0];
//       const auto& channels2 = recordingArrays2[0];
//       const AQNWB::Types::SizeType numSamples = 1000; // samples per write
  
//       // timestamps at 30 kHz
//       std::vector<double> timestamps(numSamples);
//       const double samplingRate = static_cast<double>(channels[0].getSamplingRate());
//       const double dt = 1.0 / samplingRate;
//       for (AQNWB::Types::SizeType i = 0; i < numSamples; ++i) {
//           timestamps[i] = static_cast<double>(i) * dt;
//       }
  
//       // write data per-channel
//       for (const auto& ch : channels) {
//           std::vector<int16_t> data(numSamples);
//           for (AQNWB::Types::SizeType i = 0; i < numSamples; ++i) {
//               // simple mock waveform for demonstration
//               data[i] = static_cast<int16_t>((i % 200) - 100);
//           }
  
//           auto writeStatus = recordingContainers->writeElectricalSeriesData(
//               containerIndex,
//               ch,
//               numSamples,
//               static_cast<const void*>(data.data()),
//               static_cast<const void*>(timestamps.data()));
  
//           if (writeStatus != AQNWB::Types::Success) {
//               std::cerr << "Failed to write data for channel " << ch.getName() << std::endl;
//               return 1;
//           }
//       }
  
//       // Add more annotations to existing series BEFORE finalizing
//       std::cout << "\n=== Adding More Annotations ===" << std::endl;
      
//       // Method 1: Add more annotations to existing series
//       try {
//           // Create additional annotation data
//           std::vector<std::string> additionalAnnotations = {
//               "New event occurred", 
//               "Another important moment", 
//               "Final annotation"
//           };
//           std::vector<double> additionalTimestamps = {2.0, 3.5, 5.0};
//           SizeType additionalDataShape = additionalAnnotations.size();
          
//           // Write additional data to the first annotation series
//           auto writeStatus1 = recordingContainers->writeAnnotationSeriesData(
//               annotationContainerIndexes[0], 
//               additionalDataShape, 
//               additionalAnnotations, 
//               additionalTimestamps.data());
          
//           if (writeStatus1 == AQNWB::Types::Success) {
//               std::cout << "✓ Successfully added " << additionalAnnotations.size() 
//                         << " annotations to AnnotationSeries1" << std::endl;
//           } else {
//               std::cout << "✗ Failed to add annotations to AnnotationSeries1" << std::endl;
//           }
          
//           // Write additional data to the second annotation series
//           auto writeStatus2 = recordingContainers->writeAnnotationSeriesData(
//               annotationContainerIndexes[1], 
//               additionalDataShape, 
//               additionalAnnotations, 
//               additionalTimestamps.data());
          
//           if (writeStatus2 == AQNWB::Types::Success) {
//               std::cout << "✓ Successfully added " << additionalAnnotations.size() 
//                         << " annotations to AnnotationSeries2" << std::endl;
//           } else {
//               std::cout << "✗ Failed to add annotations to AnnotationSeries2" << std::endl;
//           }
          
//       } catch (const std::exception& e) {
//           std::cerr << "Error adding annotations: " << e.what() << std::endl;
//       }
      
//       // Add data to the third annotation series (NewAnnotationSeries)
//       /*
//       try {
//           std::cout << "\n=== Adding Data to NewAnnotationSeries ===" << std::endl;
          
//           // Add data to the new annotation series (index 2)
//           std::vector<std::string> newAnnotations = {
//               "First annotation in new series",
//               "Second annotation in new series"
//           };
//           std::vector<double> newTimestamps = {1.5, 4.0};
//           SizeType newDataShape = newAnnotations.size();
          
//           auto newWriteStatus = recordingContainers->writeAnnotationSeriesData(
//               annotationContainerIndexes[2],  // Use index 2 for the third annotation series
//               newDataShape,
//               newAnnotations,
//               newTimestamps.data());
          
//           if (newWriteStatus == AQNWB::Types::Success) {
//               std::cout << "✓ Successfully added " << newAnnotations.size() 
//                         << " annotations to NewAnnotationSeries" << std::endl;
//           } else {
//               std::cout << "✗ Failed to add annotations to NewAnnotationSeries" << std::endl;
//           }
          
//       } catch (const std::exception& e) {
//           std::cerr << "Error adding data to NewAnnotationSeries: " << e.what() << std::endl;
//       }
//       */
      
//       // Ensure data is flushed to disk AFTER adding all annotations
//       auto flushStatus = io->flush();
//       if (flushStatus != AQNWB::Types::Success) {
//           std::cerr << "Flush failed" << std::endl;
//           return 1;
//       }
  
//       // 8) Stop recording and finalize the file
//       auto stopRecordingStatus = io->stopRecording();
//       if (stopRecordingStatus != AQNWB::Types::Success) {
//           std::cerr << "Failed to stop recording" << std::endl;
//           return 1;
//       }
  
//       auto finalizeStatus = nwbfile->finalize();
//       if (finalizeStatus != AQNWB::Types::Success) {
//           std::cerr << "Failed to finalize NWB file" << std::endl;
//           return 1;
//       }

  
//       std::cout << "Successfully wrote example recording to: " << outputPath << std::endl;
        
//       std::shared_ptr<AQNWB::IO::BaseIO> readio = AQNWB::createIO("HDF5", outputPath);
//       readio->open(AQNWB::IO::FileMode::ReadOnly);
//       auto readNWBFile =
//           AQNWB::NWB::RegisteredType::create<AQNWB::NWB::NWBFile>("/", readio);
        
//       // read annotation series
//       std::cout << "Reading annotation series..." << std::endl;
      
//       // Try to read the annotation series we just created
//       std::vector<std::string> annotationPaths = {
//           "/acquisition/AnnotationSeries1",
//           "/acquisition/AnnotationSeries2",
//           "/acquisition/NewAnnotationSeries"
//       };
      
//       for (const auto& annotationPath : annotationPaths) {
//           try {
//               std::cout << "Trying to read annotation series at: " << annotationPath << std::endl;
              
//               // Create annotation series object for reading
//               auto annotationSeries = AQNWB::NWB::RegisteredType::create<AQNWB::NWB::AnnotationSeries>(annotationPath, readio);
              
//               // Read the data from the annotation series
//               auto readDataWrapper = annotationSeries->readData();
//               if (readDataWrapper) {
//                   try {
//                       auto dataBlock = readDataWrapper->values<std::string>();
//                       std::cout << "  ✓ Found annotation series at: " << annotationPath << std::endl;
//                       std::cout << "  Data size: " << dataBlock.data.size() << std::endl;
                      
//                       // Print the annotation data
//                       std::cout << "  Annotations:" << std::endl;
//                       for (size_t i = 0; i < dataBlock.data.size(); ++i) {
//                           std::cout << "    [" << i << "]: " << dataBlock.data[i] << std::endl;
//                       }
                      
//                       // Read associated timestamps
//                       auto timestampsWrapper = annotationSeries->readTimestamps();
//                       if (timestampsWrapper) {
//                           try {
//                               auto timestampsBlock = timestampsWrapper->values<double>();
//                               std::cout << "  Timestamps size: " << timestampsBlock.data.size() << std::endl;
//                               std::cout << "  Timestamps:" << std::endl;
//                               for (size_t i = 0; i < timestampsBlock.data.size(); ++i) {
//                                   std::cout << "    [" << i << "]: " << timestampsBlock.data[i] << " seconds" << std::endl;
//                               }
//                           } catch (const std::exception& e) {
//                               std::cout << "  Warning: Could not read timestamps: " << e.what() << std::endl;
//                           }
//                       }
                      
//                       std::cout << std::endl;
                      
//                   } catch (const std::exception& e) {
//                       std::cout << "  Warning: Could not read data from " << annotationPath << ": " << e.what() << std::endl;
//                   }
//               } else {
//                   std::cout << "  ✗ No data found at: " << annotationPath << std::endl;
//               }
              
//           } catch (const std::exception& e) {
//               std::cout << "  ✗ No annotation series found at: " << annotationPath << std::endl;
//           }
//       }
      
//       // Read all annotation series after adding new ones
//       std::cout << "\n=== Reading All Annotation Series (After Adding New Ones) ===" << std::endl;
      
//       // Updated list of all annotation series paths
//       std::vector<std::string> allAnnotationPaths = {
//           "/acquisition/AnnotationSeries1",
//           "/acquisition/AnnotationSeries2", 
//           "/acquisition/NewAnnotationSeries"
//       };
      
//       for (const auto& annotationPath : allAnnotationPaths) {
//           try {
//               std::cout << "Reading annotation series at: " << annotationPath << std::endl;
              
//               // Create annotation series object for reading
//               auto annotationSeries = AQNWB::NWB::RegisteredType::create<AQNWB::NWB::AnnotationSeries>(annotationPath, readio);
              
//               // Read the data from the annotation series
//               auto readDataWrapper = annotationSeries->readData();
//               if (readDataWrapper) {
//                   try {
//                       auto dataBlock = readDataWrapper->values<std::string>();
//                       std::cout << "  ✓ Found annotation series with " << dataBlock.data.size() << " annotations:" << std::endl;
                      
//                       // Print the annotation data
//                       for (size_t i = 0; i < dataBlock.data.size(); ++i) {
//                           std::cout << "    [" << i << "]: " << dataBlock.data[i] << std::endl;
//                       }
                      
//                       // Read associated timestamps
//                       auto timestampsWrapper = annotationSeries->readTimestamps();
//                       if (timestampsWrapper) {
//                           try {
//                               auto timestampsBlock = timestampsWrapper->values<double>();
//                               std::cout << "  Timestamps:" << std::endl;
//                               for (size_t i = 0; i < timestampsBlock.data.size(); ++i) {
//                                   std::cout << "    [" << i << "]: " << timestampsBlock.data[i] << " seconds" << std::endl;
//                               }
//                           } catch (const std::exception& e) {
//                               std::cout << "  Warning: Could not read timestamps: " << e.what() << std::endl;
//                           }
//                       }
                      
//                       std::cout << std::endl;
                      
//                   } catch (const std::exception& e) {
//                       std::cout << "  Warning: Could not read data from " << annotationPath << ": " << e.what() << std::endl;
//                   }
//               } else {
//                   std::cout << "  ✗ No data found at: " << annotationPath << std::endl;
//               }
              
//           } catch (const std::exception& e) {
//               std::cout << "  ✗ No annotation series found at: " << annotationPath << std::endl;
//           }
//       }
//       // Read the ElectrodesTable
//       auto readElectrodeTable = readNWBFile->readElectrodesTable();
//         auto locationColumn = readElectrodeTable->readLocationColumn();
//         auto locationColumnValues = locationColumn->readData()->values();

//         readElectrodeTable->addElectrodes(channels2);
//         readElectrodeTable->finalize();
// //        readElectrodeTable->addElectrodes(channels2);

//       // read the location data. Note that both the type of the class and
//       // the data values is being set for us, here, VectorDataTyped<std::string>
//         readElectrodeTable = readNWBFile->readElectrodesTable();
//         auto readColNames = readElectrodeTable->readColNames()->values().data;
//         auto locationColumn2 = readElectrodeTable->readGroupNameColumn();
//       auto locationColumnValues2 = locationColumn2->readData()->values();
//       locationColumnValues.data.size();

//       // Store the NWB file data in our global buffer
//       // For now, we'll create a simple mock NWB file structure
//       g_nwb_file_data.clear();
      
//       // Create a simple mock NWB file header
//       std::string mock_nwb_content = 
//           "NWB File WRITE\n"
//           "Version: 2.0\n"
//           "Created: " + outputPath + "\n"
//           "Electrodes: 4\n"
//           "ElectricalSeries: 1\n"
//           "Data Points: 1000\n"
//           "Sampling Rate: 30000 Hz\n"
//           "File Size: Mock Data\n";
      
//       g_nwb_file_data.assign(mock_nwb_content.begin(), mock_nwb_content.end());
//       g_nwb_file_ready = true;
  
//       auto closeStatus = io->close();
//       if (closeStatus != AQNWB::Types::Success) {
//           std::cerr << "Failed to close IO" << std::endl;
//           return 1;
//       }      
//       return 0;
//     } catch (const std::exception& e) {
//         std::cerr << "Error: " << e.what() << std::endl;
//         return 1;
//     }    
//     return -1;
//   }

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

// Debug function to inspect NWB file structure
FFI_PLUGIN_EXPORT int32_t debug_nwb_file_structure(const char* filePath) {
    if (!filePath) {
        std::cerr << "❌ File path is null" << std::endl;
        return -1;
    }
    
    std::cout << "🔍 Inspecting NWB file structure: " << filePath << std::endl;
    
    try {
        H5::H5File file(filePath, H5F_ACC_RDONLY);
        std::cout << "✅ Successfully opened file for inspection" << std::endl;
        
        listHDF5Contents(file);
        
        return 0;
    } catch (const H5::FileIException& e) {
        std::cerr << "❌ Failed to open file: " << e.getDetailMsg() << std::endl;
        return -2;
    } catch (const H5::Exception& e) {
        std::cerr << "❌ HDF5 Error: " << e.getDetailMsg() << std::endl;
        return -3;
    } catch (const std::exception& e) {
        std::cerr << "❌ General Error: " << e.what() << std::endl;
        return -4;
    }
}

FFI_PLUGIN_EXPORT int32_t nwbfile_seek_electrical_series(const char* path, short* outSamples, int* outSamplesCount, int* outConfig, int startTimeStamp, int endTimeStamp, int startChannel, int endChannel) {
    std::cout << "🎯 AQNWB nwbfile_seek_electrical_series (Multi-Channel)" << std::endl;
    std::cout << "   Seeking from sample " << startTimeStamp << " to " << endTimeStamp << std::endl;
    std::cout << "   Channels: " << startChannel << " to " << endChannel << " (inclusive)" << std::endl;

    // Validate input parameters
    if (startTimeStamp < 0 || endTimeStamp < 0 || startTimeStamp >= endTimeStamp) {
        std::cerr << "❌ Invalid timestamp range: start=" << startTimeStamp << ", end=" << endTimeStamp << std::endl;
        *outSamplesCount = 0;
        return -1;
    }
    
    if (startChannel < 0 || endChannel < 0 || startChannel > endChannel) {
        std::cerr << "❌ Invalid channel range: start=" << startChannel << ", end=" << endChannel << std::endl;
        *outSamplesCount = 0;
        return -1;
    }
    
    int numChannelsToRead = endChannel - startChannel + 1;
    std::cout << "   Number of channels to read: " << numChannelsToRead << std::endl;
    
    // outputPath = "/Users/macbook/Library/Containers/com.example.nwbapplication/Data/Documents/example_recording_multiple_channels.nwb";
    outputPath = std::string(path);
    std::string filePath = outputPath;
    
    // Open AQNWB file
    std::shared_ptr<AQNWB::IO::BaseIO> io = AQNWB::createIO("HDF5", filePath);
    auto openStatus = io->open(AQNWB::IO::FileMode::ReadOnly);
    if (openStatus != AQNWB::Types::Success) {
        std::cerr << "Failed to open NWB file: " << filePath << std::endl;
        return 1;
    }
    std::cout << "✅ AQNWB opened successfully" << std::endl;
    
    // Initialize outConfig array with default values
    outConfig[0] = 0;  // sampleRate
    outConfig[1] = 0;  // totalChannel
    outConfig[2] = 0;  // groupName (as integer representation)
    outConfig[3] = 0;  // groupIndex
    outConfig[4] = 0;  // bitVolts (as integer, may need scaling)
    outConfig[5] = 0;  // MaximumSamples
    
    // Extract recording parameters from NWB file using direct HDF5 access
    std::cout << "📋 Extracting recording parameters from NWB file..." << std::endl;
    
    // Open HDF5 file to read metadata directly
    std::unique_ptr<H5::H5File> metadataFile;
    try {
        metadataFile = std::make_unique<H5::H5File>(filePath, H5F_ACC_RDONLY);
        std::cout << "✅ Opened HDF5 file for metadata extraction" << std::endl;

        // Discover the actual ElectricalSeries name
        std::string electricalSeriesName = "";
        try {
            if (H5Lexists(metadataFile->getId(), "/acquisition", H5P_DEFAULT) > 0) {
                H5::Group acquisitionGroup = metadataFile->openGroup("/acquisition");
                hsize_t numObjs = acquisitionGroup.getNumObjs();
                for (hsize_t i = 0; i < numObjs; i++) {
                    std::string objName = acquisitionGroup.getObjnameByIdx(i);
                    H5G_obj_t objType = acquisitionGroup.getObjTypeByIdx(i);
                    if (objType == H5G_GROUP) {
                        // Check if it's an ElectricalSeries by looking for 'data' dataset
                        try {
                            H5::Group testGroup = acquisitionGroup.openGroup(objName);
                            if (H5Lexists(testGroup.getId(), "data", H5P_DEFAULT) > 0) {
                                electricalSeriesName = objName;
                                break;
                            }
                        } catch (...) {
                            continue;
                        }
                    }
                }
            }
        } catch (const H5::Exception& e) {
            std::cout << "⚠️  Could not discover ElectricalSeries: " << e.getDetailMsg() << std::endl;
        }
        if (electricalSeriesName.empty()) {
            electricalSeriesName = "ElectricalSeries1"; // Fallback
            std::cout << "⚠️  Could not find ElectricalSeries, using default: " << electricalSeriesName << std::endl;
        } else {
            std::cout << "✅ Found ElectricalSeries: " << electricalSeriesName << std::endl;
        }

        try{
            std::string devicePath = "/general/devices";
            if (H5Lexists(metadataFile->getId(), devicePath.c_str(), H5P_DEFAULT) > 0) {
                H5::Group devicesGroup = metadataFile->openGroup(devicePath);
                hsize_t numDevices = devicesGroup.getNumObjs();
                std::string deviceName = "";
                // Find first device group
                for (hsize_t i = 0; i < numDevices && deviceName.empty(); i++) {
                    std::string objName = devicesGroup.getObjnameByIdx(i);
                    H5G_obj_t objType = devicesGroup.getObjTypeByIdx(i);
                    if (objType == H5G_GROUP) {
                        deviceName = objName;
                    }
                }
                if (!deviceName.empty()) {
                    H5::Group deviceGroup = devicesGroup.openGroup(deviceName);
                    std::cout << "✅ Device group opened successfully: " << deviceName << std::endl;
            // Read device description
                    std::string deviceDescription = "";
                    try {
                        H5::Attribute descAttr = deviceGroup.openAttribute("description");
                        H5::StrType strType(H5::PredType::C_S1, H5T_VARIABLE);
                        std::string description;
                        descAttr.read(strType, description);
                        deviceDescription = description;
                        std::cout << "📋 Device Description: " << description << std::endl;
                    } catch (const H5::Exception& e) {
                        std::cout << "⚠️  Could not read device description: " << e.getDetailMsg() << std::endl;
                    }
                    
                    // Read device manufacturer
                    try {
                        H5::Attribute manufAttr = deviceGroup.openAttribute("manufacturer");
                        H5::StrType strType(H5::PredType::C_S1, H5T_VARIABLE);
                        std::string manufacturer;
                        manufAttr.read(strType, manufacturer);
                        std::cout << "🏭 Device Manufacturer: " << manufacturer << std::endl;
                    } catch (const H5::Exception& e) {
                        std::cout << "⚠️  Could not read device manufacturer: " << e.getDetailMsg() << std::endl;
                    }
                    
                    // if (description.find("Audio|||") > -1) {
                    int res = deviceDescription.find("Audio|||");
                    if (res != std::string::npos){
                        outConfig[6] = 0;
                        std::cout << "✅ Audio Device Detected " << std::endl;
                    } else{ 
                        outConfig[6] = 1;
                        std::cerr << "✅ Serial Device Detected" << std::endl;
                    }
    
                } else {
                    std::cout << "⚠️  No devices found in /general/devices" << std::endl;
                }
            } else {
                std::cout << "⚠️  /general/devices path does not exist" << std::endl;
            }
        }catch(const H5::Exception& e){
            std::cout << "⚠️  Could not open device group: " << e.getDetailMsg() << std::endl;
        }




        // 1. Read sample rate from various possible locations
        bool sampleRateFound = false;
        
        // Try to read from ElectricalSeries starting_time attribute (rate)
        try {
            H5::Group acquisitionGroup = metadataFile->openGroup("/acquisition");
            H5::Group electricalSeriesGroup = acquisitionGroup.openGroup(electricalSeriesName);
            
            if (electricalSeriesGroup.attrExists("rate")) {
                H5::Attribute rateAttr = electricalSeriesGroup.openAttribute("rate");
                double rate;
                rateAttr.read(H5::PredType::NATIVE_DOUBLE, &rate);
                outConfig[0] = static_cast<int>(rate);
                std::cout << "📊 Sample Rate (from ElectricalSeries): " << outConfig[0] << " Hz" << std::endl;
                sampleRateFound = true;
            }
        } catch (const H5::Exception& e) {
            std::cout << "⚠️  Could not read sample rate from ElectricalSeries: " << e.getDetailMsg() << std::endl;
        }
        
        // Try to read from timestamps dataset
        if (!sampleRateFound) {
            try {
                H5::Group acquisitionGroup = metadataFile->openGroup("/acquisition");
                H5::Group electricalSeriesGroup = acquisitionGroup.openGroup(electricalSeriesName);
                H5::DataSet timestampsDataset = electricalSeriesGroup.openDataSet("timestamps");
                
                // Read first few timestamps to calculate rate
                H5::DataSpace timestampsSpace = timestampsDataset.getSpace();
                hsize_t timestampDims[1];
                timestampsSpace.getSimpleExtentDims(timestampDims, nullptr);
                
                if (timestampDims[0] > 1) {
                    std::vector<double> timestamps(std::min(static_cast<hsize_t>(10), timestampDims[0]));
                    hsize_t offset[1] = {0};
                    hsize_t count[1] = {timestamps.size()};
                    timestampsSpace.selectHyperslab(H5S_SELECT_SET, count, offset);
                    
                    hsize_t memDims[1] = {timestamps.size()};
                    H5::DataSpace memSpace(1, memDims);
                    
                    timestampsDataset.read(timestamps.data(), H5::PredType::NATIVE_DOUBLE, memSpace, timestampsSpace);
                    
                    if (timestamps.size() > 1) {
                        double samplingInterval = timestamps[1] - timestamps[0];
                        outConfig[0] = static_cast<int>(1.0 / samplingInterval);
                        std::cout << "📊 Sample Rate (calculated from timestamps): " << outConfig[0] << " Hz" << std::endl;
                        sampleRateFound = true;
                    }
                }
            } catch (const H5::Exception& e) {
                std::cout << "⚠️  Could not calculate sample rate from timestamps: " << e.getDetailMsg() << std::endl;
            }
        }
        
        if (!sampleRateFound) {
            outConfig[0] = 30000; // Default fallback
            std::cout << "📊 Sample Rate (default fallback): " << outConfig[0] << " Hz" << std::endl;
        }
        
        // 2. Read conversion factor (bitVolts)
        try {
            H5::Group acquisitionGroup = metadataFile->openGroup("/acquisition");
            H5::Group electricalSeriesGroup = acquisitionGroup.openGroup(electricalSeriesName);
            
            if (electricalSeriesGroup.attrExists("conversion")) {
                H5::Attribute conversionAttr = electricalSeriesGroup.openAttribute("conversion");
                double conversion;
                conversionAttr.read(H5::PredType::NATIVE_DOUBLE, &conversion);
                outConfig[4] = static_cast<int>(conversion * 1000000); // Convert to µV
                std::cout << "📊 BitVolts (from conversion): " << outConfig[4] << " µV" << std::endl;
            } else {
                // Try to read from channel_conversion dataset
                try {
                    H5::DataSet channelConversionDataset = electricalSeriesGroup.openDataSet("channel_conversion");
                    std::vector<float> conversions(1);
                    channelConversionDataset.read(conversions.data(), H5::PredType::NATIVE_FLOAT);
                    outConfig[4] = static_cast<int>(conversions[0] * 1000000); // Convert to µV
                    std::cout << "📊 BitVolts (from channel_conversion): " << outConfig[4] << " µV" << std::endl;
                } catch (const H5::Exception& e2) {
                    outConfig[4] = 1000; // Default 1000 µV
                    std::cout << "📊 BitVolts (default): " << outConfig[4] << " µV" << std::endl;
                }
            }
        } catch (const H5::Exception& e) {
            outConfig[4] = 1000; // Default fallback
            std::cout << "📊 BitVolts (default fallback): " << outConfig[4] << " µV" << std::endl;
        }
        
        // 3. Read electrode group information
        try {
            H5::Group generalGroup = metadataFile->openGroup("/general");
            H5::Group extracellularEphysGroup = generalGroup.openGroup("extracellular_ephys");
            
            // Try to read electrode group info
            try {
                // List electrode groups
                std::vector<std::string> groupNames;
                hsize_t numGroups = extracellularEphysGroup.getNumObjs();
                
                for (hsize_t i = 0; i < numGroups; i++) {
                    std::string objName = extracellularEphysGroup.getObjnameByIdx(i);
                    H5G_obj_t objType = extracellularEphysGroup.getObjTypeByIdx(i);
                    
                    if (objType == H5G_GROUP) {
                        groupNames.push_back(objName);
                    }
                }
                
                if (!groupNames.empty()) {
                    // Use first group found
                    std::string firstGroupName = groupNames[0];
                    
                    // Convert group name to integer hash for outConfig[2]
                    std::hash<std::string> hasher;
                    outConfig[2] = static_cast<int>(hasher(firstGroupName) % 1000); // Keep it reasonable
                    outConfig[3] = 0; // Group index
                    
                    std::cout << "📊 Group Name: " << firstGroupName << " (ID: " << outConfig[2] << ")" << std::endl;
                    std::cout << "📊 Group Index: " << outConfig[3] << std::endl;
                } else {
                    outConfig[2] = 1; // Default group name
                    outConfig[3] = 0; // Default group index
                    std::cout << "📊 Group Name (default ID): " << outConfig[2] << std::endl;
                    std::cout << "📊 Group Index (default): " << outConfig[3] << std::endl;
                }
                
            } catch (const H5::Exception& e) {
                outConfig[2] = 1; // Default group name
                outConfig[3] = 0; // Default group index
                std::cout << "📊 Group Name (default ID): " << outConfig[2] << std::endl;
                std::cout << "📊 Group Index (default): " << outConfig[3] << std::endl;
            }
            
        } catch (const H5::Exception& e) {
            outConfig[2] = 1; // Default group name
            outConfig[3] = 0; // Default group index
            std::cout << "📊 Group Name (default ID): " << outConfig[2] << std::endl;
            std::cout << "📊 Group Index (default): " << outConfig[3] << std::endl;
        }
        
        metadataFile->close();
        
    } catch (const H5::Exception& e) {
        std::cout << "⚠️  Exception while reading metadata: " << e.getDetailMsg() << std::endl;
        // Set reasonable defaults
        outConfig[0] = 30000; // 30kHz
        outConfig[1] = 4;     // 4 channels (will be set later from data dimensions)
        outConfig[2] = 1;     // Group 1
        outConfig[3] = 0;     // Group index 0
        outConfig[4] = 1000;  // 1000 µV
    }
    
    // Direct HDF5 approach for partial reading
    std::cout << "📊 Reading partial electrical series data using direct HDF5 approach..." << std::endl;
    
    try {
        // Open HDF5 file directly for efficient partial reading
        std::unique_ptr<H5::H5File> h5file;
        try {
            h5file = std::make_unique<H5::H5File>(filePath, H5F_ACC_RDONLY);
            std::cout << "✅ Opened HDF5 file directly" << std::endl;
        } catch (const H5::FileIException& e) {
            std::cerr << "❌ Failed to open HDF5 file: " << e.getDetailMsg() << std::endl;
            return -1;
        }
        
        // Discover the actual ElectricalSeries name
        std::string electricalSeriesNameForData = "";
        try {
            if (H5Lexists(h5file->getId(), "/acquisition", H5P_DEFAULT) > 0) {
                H5::Group acquisitionGroup = h5file->openGroup("/acquisition");
                hsize_t numObjs = acquisitionGroup.getNumObjs();
                for (hsize_t i = 0; i < numObjs; i++) {
                    std::string objName = acquisitionGroup.getObjnameByIdx(i);
                    H5G_obj_t objType = acquisitionGroup.getObjTypeByIdx(i);
                    if (objType == H5G_GROUP) {
                        // Check if it's an ElectricalSeries by looking for 'data' dataset
                        try {
                            H5::Group testGroup = acquisitionGroup.openGroup(objName);
                            if (H5Lexists(testGroup.getId(), "data", H5P_DEFAULT) > 0) {
                                electricalSeriesNameForData = objName;
                                break;
                            }
                        } catch (...) {
                            continue;
                        }
                    }
                }
            }
        } catch (const H5::Exception& e) {
            std::cerr << "⚠️  Could not discover ElectricalSeries: " << e.getDetailMsg() << std::endl;
        }
        
        if (electricalSeriesNameForData.empty()) {
            electricalSeriesNameForData = "ElectricalSeries1"; // Fallback
            std::cout << "⚠️  Using default ElectricalSeries name: " << electricalSeriesNameForData << std::endl;
        } else {
            std::cout << "✅ Found ElectricalSeries: " << electricalSeriesNameForData << std::endl;
        }
        
        // Open the dataset directly
        H5::DataSet dataset;
        std::string dataPath = "/acquisition/" + electricalSeriesNameForData + "/data";
        try {
            if (H5Lexists(h5file->getId(), dataPath.c_str(), H5P_DEFAULT) <= 0) {
                std::cerr << "❌ Dataset path does not exist: " << dataPath << std::endl;
                return -1;
            }
            dataset = h5file->openDataSet(dataPath);
            std::cout << "✅ Opened electrical series dataset: " << dataPath << std::endl;
        } catch (const H5::DataSetIException& e) {
            std::cerr << "❌ Failed to open dataset: " << e.getDetailMsg() << std::endl;
            return -1;
        }
        
        // Get dataset dimensions
        H5::DataSpace dataspace = dataset.getSpace();
        int rank = dataspace.getSimpleExtentNdims();
        std::vector<hsize_t> dims(rank);
        dataspace.getSimpleExtentDims(dims.data(), nullptr);
        
        std::cout << "📊 Dataset dimensions: ";
        for (int i = 0; i < rank; ++i) {
            std::cout << dims[i];
            if (i < rank - 1) std::cout << " × ";
        }
        std::cout << std::endl;
        
        // Calculate total samples and channels
        hsize_t totalSamples = dims[0];
        hsize_t totalChannels = (rank > 1) ? dims[1] : 1;
        
        // Set total channels in outConfig
        outConfig[1] = static_cast<int>(totalChannels);
        
        // Try to read sample rate from HDF5 attributes
        try {
            // Try to read the rate attribute from the electrical series
            if (dataset.attrExists("rate")) {
                H5::Attribute rateAttr = dataset.openAttribute("rate");
                double rate;
                rateAttr.read(H5::PredType::NATIVE_DOUBLE, &rate);
                outConfig[0] = static_cast<int>(rate);
                std::cout << "📊 Sample Rate (from attribute): " << outConfig[0] << " Hz" << std::endl;
            } else {
                std::cout << "⚠️  Rate attribute not found, keeping default" << std::endl;
            }
        } catch (const H5::Exception& e) {
            std::cout << "⚠️  Could not read rate attribute: " << e.getDetailMsg() << std::endl;
        }
        
        // Try to read conversion factor from HDF5 attributes
        try {
            if (dataset.attrExists("conversion")) {
                H5::Attribute conversionAttr = dataset.openAttribute("conversion");
                double conversion;
                conversionAttr.read(H5::PredType::NATIVE_DOUBLE, &conversion);
                outConfig[4] = static_cast<int>(conversion * 1000000); // Convert to µV
                std::cout << "📊 BitVolts (from attribute): " << outConfig[4] << " µV" << std::endl;
            }
        } catch (const H5::Exception& e) {
            std::cout << "⚠️  Could not read conversion attribute: " << e.getDetailMsg() << std::endl;
        }
        
        std::cout << "📊 Total samples in file: " << totalSamples << std::endl;
        std::cout << "📊 Total channels in file: " << totalChannels << std::endl;
        
        // Set maximum samples length in outConfig[5]
        outConfig[5] = static_cast<int>(totalSamples);
        std::cout << "📊 Maximum Samples Length: " << outConfig[5] << std::endl;
        
        // Validate timestamp range against actual data
        if (startTimeStamp >= static_cast<int>(totalSamples) || endTimeStamp > static_cast<int>(totalSamples)) {
            std::cerr << "❌ Timestamp range exceeds available data!" << std::endl;
            std::cerr << "   Requested: " << startTimeStamp << "-" << endTimeStamp << std::endl;
            std::cerr << "   Available: 0-" << (totalSamples - 1) << std::endl;
            *outSamplesCount = 0;
            return -1;
        }
        
        // Validate channel range
        if (endChannel >= static_cast<int>(totalChannels)) {
            std::cerr << "❌ Invalid channel range: end=" << endChannel << " (max: " << (totalChannels - 1) << ")" << std::endl;
            *outSamplesCount = 0;
            return -1;
        }
        
        // Calculate the number of samples to read
        int samplesToRead = endTimeStamp - startTimeStamp;
        std::cout << "📊 Samples to read: " << samplesToRead << std::endl;
        std::cout << "📊 Channels to read: " << numChannelsToRead << std::endl;
        
        // Read data for multiple channels within the specified time range
        // Data will be stored in interleaved format: [ch0_sample0, ch1_sample0, ..., chN_sample0, ch0_sample1, ch1_sample1, ...]
        std::vector<int16_t> multiChannelData(samplesToRead * numChannelsToRead);
        
        if (rank == 1) {
            // 1D data - read partial range (treat as single channel)
            hsize_t offset[1] = {static_cast<hsize_t>(startTimeStamp)};
            hsize_t count[1] = {static_cast<hsize_t>(samplesToRead)};
            dataspace.selectHyperslab(H5S_SELECT_SET, count, offset);
            
            // Define memory space
            hsize_t memDims[1] = {static_cast<hsize_t>(samplesToRead)};
            H5::DataSpace memSpace(1, memDims);
            
            // Read the data directly into multiChannelData (single channel case)
            dataset.read(multiChannelData.data(), H5::PredType::NATIVE_INT16, memSpace, dataspace);
            
        } else {
            // 2D data - read multiple channels within time range
            // Read all requested channels at once for efficiency
            hsize_t offset[2] = {static_cast<hsize_t>(startTimeStamp), static_cast<hsize_t>(startChannel)};
            hsize_t count[2] = {static_cast<hsize_t>(samplesToRead), static_cast<hsize_t>(numChannelsToRead)};
            dataspace.selectHyperslab(H5S_SELECT_SET, count, offset);
            
            // Define memory space for interleaved data
            hsize_t memDims[2] = {static_cast<hsize_t>(samplesToRead), static_cast<hsize_t>(numChannelsToRead)};
            H5::DataSpace memSpace(2, memDims);
            
            // Read the data in channel-major format (samples x channels)
            std::vector<int16_t> tempData(samplesToRead * numChannelsToRead);
            dataset.read(tempData.data(), H5::PredType::NATIVE_INT16, memSpace, dataspace);
            
            // Keep data in channel-major format
            // tempData is [sample0_ch0, sample0_ch1, ..., sample1_ch0, sample1_ch1, ...]
            // We want [ch0_sample0, ch0_sample1, ..., ch1_sample0, ch1_sample1, ...]
            for (int ch = 0; ch < numChannelsToRead; ch++) {
                for (int sample = 0; sample < samplesToRead; sample++) {
                    int sourceIdx = sample * numChannelsToRead + ch;
                    int destIdx = ch * samplesToRead + sample;
                    multiChannelData[destIdx] = tempData[sourceIdx];
                }
            }
        }
        
        std::cout << "✅ Successfully read " << samplesToRead << " samples from channels " << startChannel << " to " << endChannel << std::endl;
        std::cout << "   Time range: samples " << startTimeStamp << " to " << (endTimeStamp - 1) << std::endl;
        std::cout << "   Total data points: " << (samplesToRead * numChannelsToRead) << std::endl;
        
        // Copy data to output buffer (channel-major format)
        *outSamplesCount = samplesToRead;
        for (int i = 0; i < samplesToRead * numChannelsToRead; ++i) {
            outSamples[i] = multiChannelData[i];
        }
        
        // Print first and last few samples for verification (channel-major format)
        std::cout << "🔍 First 5 samples from seek operation (channel-major format):" << std::endl;
        int samplesToShow = (samplesToRead < 5) ? samplesToRead : 5;
        for (int i = 0; i < samplesToShow; ++i) {
            std::cout << "  Sample " << (startTimeStamp + i) << ": ";
            for (int ch = 0; ch < numChannelsToRead; ch++) {
                int idx = ch * samplesToRead + i;
                std::cout << "Ch" << (startChannel + ch) << "=" << outSamples[idx];
                if (ch < numChannelsToRead - 1) std::cout << ", ";
            }
            std::cout << std::endl;
        }
        
        if (samplesToRead > 5) {
            std::cout << "🔍 Last 5 samples from seek operation (channel-major format):" << std::endl;
            int startIdx = samplesToRead - 5;
            if (startIdx < 0) startIdx = 0;
            for (int i = startIdx; i < samplesToRead; ++i) {
                std::cout << "  Sample " << (startTimeStamp + i) << ": ";
                for (int ch = 0; ch < numChannelsToRead; ch++) {
                    int idx = ch * samplesToRead + i;
                    std::cout << "Ch" << (startChannel + ch) << "=" << outSamples[idx];
                    if (ch < numChannelsToRead - 1) std::cout << ", ";
                }
                std::cout << std::endl;
            }
        }
        
        // Print statistics
        std::cout << "📈 Seek operation summary:" << std::endl;
        std::cout << "   Requested range: " << startTimeStamp << " to " << endTimeStamp << std::endl;
        std::cout << "   Samples returned: " << samplesToRead << std::endl;
        std::cout << "   Channels: " << startChannel << " to " << endChannel << " (" << numChannelsToRead << " channels)" << std::endl;
        std::cout << "   Total data points: " << (samplesToRead * numChannelsToRead) << std::endl;
        
        io->close();
        h5file->close();
        
    } catch (const H5::Exception& e) {
        std::cerr << "❌ HDF5 Error during seek: " << e.getDetailMsg() << std::endl;
        *outSamplesCount = 0;
        return -1;
    } catch (const std::exception& e) {
        std::cerr << "❌ General Error during seek: " << e.what() << std::endl;
        *outSamplesCount = 0;
        return -1;
    }
    
    // Print final configuration summary
    std::cout << "\n📋 Recording Parameters Summary:" << std::endl;
    std::cout << "   Sample Rate: " << outConfig[0] << " Hz" << std::endl;
    std::cout << "   Total Channels: " << outConfig[1] << std::endl;
    std::cout << "   Group Name (ID): " << outConfig[2] << std::endl;
    std::cout << "   Group Index: " << outConfig[3] << std::endl;
    std::cout << "   BitVolts (µV): " << outConfig[4] << std::endl;
    
    std::cout << "✅ Seek operation completed successfully!" << std::endl;
    return 0;
}