/**
 * @file electrical_series_reader.cpp
 * @brief Complete example for reading electrical series data from NWB files
 * 
 * This example demonstrates various methods to read electrical series data
 * from NWB files using the AQNWB library and direct HDF5 access.
 */

#include <iostream>
#include <vector>
#include <memory>
#include <string>
#include <algorithm>

// AQNWB includes
#include "nwb/NWBFile.hpp"
#include "nwb/ecephys/ElectricalSeries.hpp"
#include "io/BaseIO.hpp"
#include "Utils.hpp"

// HDF5 includes for direct access
#include <H5Cpp.h>

using namespace AQNWB::NWB;
using namespace AQNWB::IO;

/**
 * @brief Read electrical series using AQNWB library (recommended approach)
 * 
 * This method provides the most robust and feature-complete way to read
 * electrical series data with proper error handling and metadata access.
 * 
 * @param filePath Path to the NWB file
 * @param seriesName Name of the electrical series (default: "ElectricalSeries1")
 * @return 0 on success, 1 on failure
 */
int readElectricalSeriesAQNWB(const std::string& filePath, 
                              const std::string& seriesName = "ElectricalSeries1") {
    try {
        std::cout << "Reading electrical series using AQNWB library..." << std::endl;
        std::cout << "File: " << filePath << std::endl;
        std::cout << "Series: " << seriesName << std::endl;

        // 1. Open the NWB file for reading
        std::shared_ptr<BaseIO> io = AQNWB::createIO("HDF5", filePath);
        auto openStatus = io->open(FileMode::ReadOnly);
        if (openStatus != AQNWB::Types::Success) {
            std::cerr << "❌ Failed to open NWB file: " << filePath << std::endl;
            return 1;
        }
        std::cout << "✅ File opened successfully" << std::endl;

        // 2. Create NWBFile object for reading
        auto nwbFile = RegisteredType::create<NWBFile>("/", io);
        if (!nwbFile) {
            std::cerr << "❌ Failed to create NWBFile object" << std::endl;
            return 1;
        }

        // 3. Access the electrical series (typically in /acquisition/)
        std::string seriesPath = "/acquisition/" + seriesName;
        auto electricalSeries = RegisteredType::create<ElectricalSeries>(seriesPath, io);
        if (!electricalSeries) {
            std::cerr << "❌ ElectricalSeries not found at: " << seriesPath << std::endl;
            
            // Try to list available series
            std::cout << "💡 Available paths in /acquisition/:" << std::endl;
            // Note: In a real implementation, you'd list the acquisition group contents
            return 1;
        }
        std::cout << "✅ ElectricalSeries found at: " << seriesPath << std::endl;

        // 4. Read the voltage data
        std::cout << "\n--- Reading Voltage Data ---" << std::endl;
        auto dataWrapper = electricalSeries->readData();
        if (dataWrapper) {
            // Get the data as float values (voltage data)
            auto dataBlock = dataWrapper->values<float>();
            
            std::cout << "✅ Successfully read electrical series data!" << std::endl;
            std::cout << "📊 Total data points: " << dataBlock.data.size() << std::endl;
            
            // Calculate statistics
            if (!dataBlock.data.empty()) {
                float minVal = *std::min_element(dataBlock.data.begin(), dataBlock.data.end());
                float maxVal = *std::max_element(dataBlock.data.begin(), dataBlock.data.end());
                
                // Calculate mean
                float sum = 0.0f;
                for (float val : dataBlock.data) {
                    sum += val;
                }
                float mean = sum / dataBlock.data.size();
                
                std::cout << "📈 Data range: " << minVal << " to " << maxVal << " V" << std::endl;
                std::cout << "📈 Mean value: " << mean << " V" << std::endl;
            }
            
            // Print first 10 data points
            std::cout << "\n🔍 First 10 voltage samples:" << std::endl;
            for (size_t i = 0; i < std::min(size_t(10), dataBlock.data.size()); ++i) {
                std::cout << "  Sample " << i << ": " << dataBlock.data[i] << " V" << std::endl;
            }
        } else {
            std::cerr << "❌ Failed to read voltage data" << std::endl;
        }

        // 5. Read timestamps
        std::cout << "\n--- Reading Timestamps ---" << std::endl;
        auto timestampsWrapper = electricalSeries->readTimestamps();
        if (timestampsWrapper) {
            auto timestampsBlock = timestampsWrapper->values<double>();
            std::cout << "✅ Timestamp information:" << std::endl;
            std::cout << "⏰ Number of timestamps: " << timestampsBlock.data.size() << std::endl;
            
            if (!timestampsBlock.data.empty()) {
                std::cout << "⏰ First timestamp: " << timestampsBlock.data[0] << " seconds" << std::endl;
                std::cout << "⏰ Last timestamp: " << timestampsBlock.data.back() << " seconds" << std::endl;
                
                // Calculate duration and sampling rate
                double duration = timestampsBlock.data.back() - timestampsBlock.data[0];
                std::cout << "⏰ Recording duration: " << duration << " seconds" << std::endl;
                
                if (timestampsBlock.data.size() > 1) {
                    double samplingRate = 1.0 / (timestampsBlock.data[1] - timestampsBlock.data[0]);
                    std::cout << "📊 Estimated sampling rate: " << samplingRate << " Hz" << std::endl;
                }
            }
        } else {
            std::cout << "⚠️  No explicit timestamps found, checking for starting_time..." << std::endl;
            // In some NWB files, timestamps are implicit (starting_time + rate)
        }

        // 6. Read electrode information
        std::cout << "\n--- Reading Electrode Information ---" << std::endl;
        auto electrodesWrapper = electricalSeries->readElectrodes();
        if (electrodesWrapper) {
            auto electrodesBlock = electrodesWrapper->values<int>();
            std::cout << "✅ Electrode information:" << std::endl;
            std::cout << "🔌 Number of electrodes: " << electrodesBlock.data.size() << std::endl;
            std::cout << "🔌 Electrode indices: ";
            for (size_t i = 0; i < std::min(size_t(10), electrodesBlock.data.size()); ++i) {
                std::cout << electrodesBlock.data[i] << " ";
            }
            if (electrodesBlock.data.size() > 10) {
                std::cout << "... (" << (electrodesBlock.data.size() - 10) << " more)";
            }
            std::cout << std::endl;
        } else {
            std::cout << "⚠️  No electrode information found" << std::endl;
        }

        // 7. Read channel conversion factors
        std::cout << "\n--- Reading Channel Conversion Factors ---" << std::endl;
        auto conversionWrapper = electricalSeries->readChannelConversion();
        if (conversionWrapper) {
            auto conversionBlock = conversionWrapper->values<float>();
            std::cout << "✅ Channel conversion factors:" << std::endl;
            for (size_t i = 0; i < std::min(size_t(10), conversionBlock.data.size()); ++i) {
                std::cout << "  Channel " << i << ": " << conversionBlock.data[i] << std::endl;
            }
            if (conversionBlock.data.size() > 10) {
                std::cout << "  ... (" << (conversionBlock.data.size() - 10) << " more channels)" << std::endl;
            }
        } else {
            std::cout << "⚠️  No channel conversion factors found" << std::endl;
        }

        // 8. Read data unit
        std::cout << "\n--- Reading Data Unit ---" << std::endl;
        try {
            auto unitWrapper = electricalSeries->readDataUnit();
            if (unitWrapper) {
                auto unit = unitWrapper->values();
                std::cout << "✅ Data unit: " << unit.data << std::endl;
            }
        } catch (const std::exception& e) {
            std::cout << "⚠️  Could not read data unit: " << e.what() << std::endl;
        }

        // 9. Close the file
        io->close();
        std::cout << "\n✅ File closed successfully" << std::endl;
        return 0;

    } catch (const std::exception& e) {
        std::cerr << "❌ Error reading electrical series: " << e.what() << std::endl;
        return 1;
    }
}

/**
 * @brief Read electrical series using direct HDF5 access
 * 
 * This method provides lower-level access to the HDF5 data, useful when
 * you need more control or when working with non-standard NWB files.
 * 
 * @param filePath Path to the NWB file
 * @param seriesName Name of the electrical series
 * @return 0 on success, 1 on failure
 */
int readElectricalSeriesHDF5(const std::string& filePath, 
                             const std::string& seriesName = "ElectricalSeries1") {
    try {
        std::cout << "\nReading electrical series using direct HDF5 access..." << std::endl;

        // 1. Open HDF5 file
        H5::H5File file(filePath, H5F_ACC_RDONLY);
        std::cout << "✅ HDF5 file opened" << std::endl;
        
        // 2. Open the electrical series dataset
        std::string datasetPath = "/acquisition/" + seriesName + "/data";
        H5::DataSet dataset = file.openDataSet(datasetPath);
        std::cout << "✅ Dataset opened: " << datasetPath << std::endl;
        
        // 3. Get dataset dimensions
        H5::DataSpace dataspace = dataset.getSpace();
        int rank = dataspace.getSimpleExtentNdims();
        std::vector<hsize_t> dims(rank);
        dataspace.getSimpleExtentDims(dims.data(), nullptr);
        
        std::cout << "📊 Dataset dimensions (" << rank << "D): ";
        for (int i = 0; i < rank; ++i) {
            std::cout << dims[i];
            if (i < rank - 1) std::cout << " × ";
        }
        std::cout << std::endl;
        
        // 4. Read the data (assuming float type)
        size_t totalElements = 1;
        for (int i = 0; i < rank; ++i) {
            totalElements *= dims[i];
        }
        
        std::cout << "📊 Total elements: " << totalElements << std::endl;
        
        // Read only first 1000 elements for demonstration
        size_t elementsToRead = std::min(totalElements, size_t(1000));
        std::vector<float> data(elementsToRead);
        
        // Create memory space for partial read
        hsize_t memDims[1] = {elementsToRead};
        H5::DataSpace memSpace(1, memDims);
        
        // Select hyperslab in file
        hsize_t offset[2] = {0, 0};
        hsize_t count[2] = {elementsToRead, 1};
        if (rank == 2) {
            count[0] = elementsToRead / dims[1];
            count[1] = dims[1];
        }
        dataspace.selectHyperslab(H5S_SELECT_SET, count, offset);
        
        dataset.read(data.data(), H5::PredType::NATIVE_FLOAT, memSpace, dataspace);
        
        std::cout << "✅ Successfully read " << elementsToRead << " data points" << std::endl;
        
        // 5. Print first few samples
        std::cout << "\n🔍 First 10 samples:" << std::endl;
        for (size_t i = 0; i < std::min(size_t(10), data.size()); ++i) {
            std::cout << "  Sample " << i << ": " << data[i] << std::endl;
        }
        
        // 6. Try to read timestamps
        std::cout << "\n--- Reading Timestamps (HDF5) ---" << std::endl;
        try {
            std::string timestampsPath = "/acquisition/" + seriesName + "/timestamps";
            H5::DataSet timestampsDataset = file.openDataSet(timestampsPath);
            
            H5::DataSpace timestampsSpace = timestampsDataset.getSpace();
            hsize_t timestampsDim;
            timestampsSpace.getSimpleExtentDims(&timestampsDim, nullptr);
            
            // Read first 100 timestamps
            size_t timestampsToRead = std::min(static_cast<size_t>(timestampsDim), size_t(100));
            std::vector<double> timestamps(timestampsToRead);
            
            hsize_t tsMemDims[1] = {timestampsToRead};
            H5::DataSpace tsMemSpace(1, tsMemDims);
            
            hsize_t tsOffset[1] = {0};
            hsize_t tsCount[1] = {timestampsToRead};
            timestampsSpace.selectHyperslab(H5S_SELECT_SET, tsCount, tsOffset);
            
            timestampsDataset.read(timestamps.data(), H5::PredType::NATIVE_DOUBLE, 
                                 tsMemSpace, timestampsSpace);
            
            std::cout << "✅ Timestamps (" << timestampsDim << " total, showing first " 
                      << timestampsToRead << "):" << std::endl;
            std::cout << "⏰ First: " << timestamps[0] << " seconds" << std::endl;
            if (timestamps.size() > 1) {
                std::cout << "⏰ Second: " << timestamps[1] << " seconds" << std::endl;
                double samplingRate = 1.0 / (timestamps[1] - timestamps[0]);
                std::cout << "📊 Sampling rate: " << samplingRate << " Hz" << std::endl;
            }
            
        } catch (const H5::Exception& e) {
            std::cout << "⚠️  No timestamps found, checking for starting_time..." << std::endl;
            
            // Try to read starting_time and rate attributes
            try {
                std::string startingTimePath = "/acquisition/" + seriesName + "/starting_time";
                H5::DataSet startingTimeDataset = file.openDataSet(startingTimePath);
                double startingTime;
                startingTimeDataset.read(&startingTime, H5::PredType::NATIVE_DOUBLE);
                
                // Read rate attribute
                H5::Attribute rateAttr = startingTimeDataset.openAttribute("rate");
                double rate;
                rateAttr.read(H5::PredType::NATIVE_DOUBLE, &rate);
                
                std::cout << "✅ Starting time: " << startingTime << " seconds" << std::endl;
                std::cout << "✅ Sampling rate: " << rate << " Hz" << std::endl;
                
            } catch (const H5::Exception& e2) {
                std::cout << "⚠️  No timing information found" << std::endl;
            }
        }
        
        // 7. Try to read electrode indices
        std::cout << "\n--- Reading Electrodes (HDF5) ---" << std::endl;
        try {
            std::string electrodesPath = "/acquisition/" + seriesName + "/electrodes";
            H5::DataSet electrodesDataset = file.openDataSet(electrodesPath);
            
            H5::DataSpace electrodesSpace = electrodesDataset.getSpace();
            hsize_t electrodesDim;
            electrodesSpace.getSimpleExtentDims(&electrodesDim, nullptr);
            
            std::vector<int> electrodes(electrodesDim);
            electrodesDataset.read(electrodes.data(), H5::PredType::NATIVE_INT);
            
            std::cout << "✅ Electrode indices (" << electrodesDim << " total): ";
            for (size_t i = 0; i < std::min(static_cast<size_t>(electrodesDim), size_t(10)); ++i) {
                std::cout << electrodes[i] << " ";
            }
            if (electrodesDim > 10) {
                std::cout << "... (" << (electrodesDim - 10) << " more)";
            }
            std::cout << std::endl;
            
        } catch (const H5::Exception& e) {
            std::cout << "⚠️  No electrode information found" << std::endl;
        }
        
        file.close();
        std::cout << "\n✅ HDF5 file closed successfully" << std::endl;
        return 0;
        
    } catch (const H5::Exception& e) {
        std::cerr << "❌ HDF5 error: " << e.getDetailMsg() << std::endl;
        return 1;
    }
}

/**
 * @brief Read specific channels and time ranges from electrical series
 * 
 * This method demonstrates how to efficiently read only the data you need,
 * which is important for large datasets.
 * 
 * @param filePath Path to the NWB file
 * @param seriesName Name of the electrical series
 * @param startSample Starting sample index
 * @param numSamples Number of samples to read
 * @param channelIndices Specific channel indices to read (empty = all channels)
 * @return 0 on success, 1 on failure
 */
int readElectricalSeriesPartial(const std::string& filePath, 
                               const std::string& seriesName,
                               int startSample, int numSamples,
                               const std::vector<int>& channelIndices = {}) {
    try {
        std::cout << "\nReading electrical series (partial data)..." << std::endl;
        std::cout << "📊 Samples: " << startSample << " to " << (startSample + numSamples - 1) << std::endl;
        
        // Open file
        H5::H5File file(filePath, H5F_ACC_RDONLY);
        std::string datasetPath = "/acquisition/" + seriesName + "/data";
        H5::DataSet dataset = file.openDataSet(datasetPath);
        
        // Get full dimensions
        H5::DataSpace fileSpace = dataset.getSpace();
        std::vector<hsize_t> dims(2);
        fileSpace.getSimpleExtentDims(dims.data(), nullptr);
        
        hsize_t totalSamples = dims[0];
        hsize_t totalChannels = dims[1];
        
        std::cout << "📊 Full dataset: " << totalSamples << " samples × " 
                  << totalChannels << " channels" << std::endl;
        
        // Validate parameters
        if (startSample < 0 || startSample >= static_cast<int>(totalSamples)) {
            std::cerr << "❌ Invalid start sample: " << startSample << std::endl;
            return 1;
        }
        
        int actualNumSamples = std::min(numSamples, 
                                       static_cast<int>(totalSamples) - startSample);
        
        // Determine which channels to read
        std::vector<int> channelsToRead = channelIndices;
        if (channelsToRead.empty()) {
            // Read all channels
            for (int i = 0; i < static_cast<int>(totalChannels); ++i) {
                channelsToRead.push_back(i);
            }
        }
        
        std::cout << "📊 Reading " << actualNumSamples << " samples from " 
                  << channelsToRead.size() << " channels" << std::endl;
        
        // For simplicity, read all channels then extract the ones we want
        // In a production system, you'd use more sophisticated HDF5 selection
        
        // Define hyperslab for time range
        std::vector<hsize_t> offset = {static_cast<hsize_t>(startSample), 0};
        std::vector<hsize_t> count = {static_cast<hsize_t>(actualNumSamples), totalChannels};
        
        fileSpace.selectHyperslab(H5S_SELECT_SET, count.data(), offset.data());
        
        // Create memory space
        H5::DataSpace memSpace(2, count.data());
        
        // Read the data
        std::vector<float> data(count[0] * count[1]);
        dataset.read(data.data(), H5::PredType::NATIVE_FLOAT, memSpace, fileSpace);
        
        std::cout << "✅ Read " << count[0] << " samples from " << count[1] 
                  << " channels" << std::endl;
        
        // Extract and display specific channels if requested
        if (!channelIndices.empty()) {
            std::cout << "\n🔍 Extracting data for channels: ";
            for (int ch : channelIndices) {
                std::cout << ch << " ";
            }
            std::cout << std::endl;
            
            // Show first 5 samples for each requested channel
            for (size_t sample = 0; sample < std::min(size_t(5), count[0]); ++sample) {
                std::cout << "Sample " << (startSample + sample) << ": ";
                for (int ch : channelIndices) {
                    if (ch >= 0 && ch < static_cast<int>(totalChannels)) {
                        float value = data[sample * totalChannels + ch];
                        std::cout << "Ch" << ch << "=" << value << " ";
                    }
                }
                std::cout << std::endl;
            }
            
            if (count[0] > 5) {
                std::cout << "... (showing first 5 samples only)" << std::endl;
            }
        } else {
            // Show overall statistics
            std::cout << "\n📈 Data statistics:" << std::endl;
            if (!data.empty()) {
                float minVal = *std::min_element(data.begin(), data.end());
                float maxVal = *std::max_element(data.begin(), data.end());
                float sum = 0.0f;
                for (float val : data) {
                    sum += val;
                }
                float mean = sum / data.size();
                
                std::cout << "  Range: " << minVal << " to " << maxVal << " V" << std::endl;
                std::cout << "  Mean: " << mean << " V" << std::endl;
            }
        }
        
        file.close();
        return 0;
        
    } catch (const H5::Exception& e) {
        std::cerr << "❌ HDF5 error: " << e.getDetailMsg() << std::endl;
        return 1;
    }
}

/**
 * @brief Main function demonstrating all reading methods
 */
int main(int argc, char* argv[]) {
    std::string filePath;
    std::string seriesName = "ElectricalSeries1";
    
    // Parse command line arguments
    if (argc < 2) {
        std::cout << "Usage: " << argv[0] << " <nwb_file_path> [series_name]" << std::endl;
        std::cout << "Example: " << argv[0] << " /path/to/recording.nwb ElectricalSeries1" << std::endl;
        
        // Use default path for demonstration
        filePath = "/Users/macbook/Library/Containers/com.example.nwbapplication/Data/Documents/example_recording2.nwb";
        std::cout << "\nUsing default file path: " << filePath << std::endl;
    } else {
        filePath = argv[1];
        if (argc >= 3) {
            seriesName = argv[2];
        }
    }
    
    std::cout << "🚀 Electrical Series Reader Example" << std::endl;
    std::cout << "===================================" << std::endl;
    std::cout << "File: " << filePath << std::endl;
    std::cout << "Series: " << seriesName << std::endl;
    
    // Method 1: Using AQNWB (recommended)
    std::cout << "\n🔬 Method 1: AQNWB Library (Recommended)" << std::endl;
    std::cout << "=========================================" << std::endl;
    int result1 = readElectricalSeriesAQNWB(filePath, seriesName);
    
    // Method 2: Direct HDF5 access
    std::cout << "\n🔬 Method 2: Direct HDF5 Access" << std::endl;
    std::cout << "===============================" << std::endl;
    int result2 = readElectricalSeriesHDF5(filePath, seriesName);
    
    // Method 3: Partial reading
    std::cout << "\n🔬 Method 3: Partial Data Reading" << std::endl;
    std::cout << "=================================" << std::endl;
    std::vector<int> channels = {0, 1, 2};  // Read channels 0, 1, and 2
    int result3 = readElectricalSeriesPartial(filePath, seriesName, 
                                            1000, 100, channels);  // 100 samples starting from sample 1000
    
    // Summary
    std::cout << "\n📋 Summary" << std::endl;
    std::cout << "==========" << std::endl;
    std::cout << "AQNWB method: " << (result1 == 0 ? "✅ Success" : "❌ Failed") << std::endl;
    std::cout << "HDF5 method: " << (result2 == 0 ? "✅ Success" : "❌ Failed") << std::endl;
    std::cout << "Partial method: " << (result3 == 0 ? "✅ Success" : "❌ Failed") << std::endl;
    
    return (result1 == 0 || result2 == 0 || result3 == 0) ? 0 : 1;
}
















