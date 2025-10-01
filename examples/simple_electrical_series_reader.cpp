/**
 * @file simple_electrical_series_reader.cpp
 * @brief Simple, focused example for reading electrical series data
 * 
 * This is a minimal example that demonstrates the core concepts
 * of reading electrical series data from NWB files.
 */

#include <iostream>
#include <vector>
#include <memory>
#include <string>

// AQNWB includes - adjust paths based on your setup
#include "nwb/NWBFile.hpp"
#include "nwb/ecephys/ElectricalSeries.hpp"
#include "io/BaseIO.hpp"

using namespace AQNWB::NWB;
using namespace AQNWB::IO;

/**
 * @brief Simple function to read and display electrical series data
 * 
 * This function demonstrates the basic steps needed to read electrical
 * series data from an NWB file.
 */
void readElectricalSeriesSimple(const std::string& filePath) {
    std::cout << "Reading electrical series from: " << filePath << std::endl;
    
    try {
        // Step 1: Open the NWB file
        std::shared_ptr<BaseIO> io = AQNWB::createIO("HDF5", filePath);
        if (io->open(FileMode::ReadOnly) != AQNWB::Types::Success) {
            std::cerr << "Failed to open file!" << std::endl;
            return;
        }
        
        // Step 2: Create an ElectricalSeries object
        // Most NWB files store electrical series at /acquisition/ElectricalSeries1
        std::string seriesPath = "/acquisition/ElectricalSeries1";
        auto electricalSeries = RegisteredType::create<ElectricalSeries>(seriesPath, io);
        
        if (!electricalSeries) {
            std::cerr << "ElectricalSeries not found at: " << seriesPath << std::endl;
            return;
        }
        
        std::cout << "✅ Found electrical series!" << std::endl;
        
        // Step 3: Read the voltage data
        auto dataWrapper = electricalSeries->readData();
        if (dataWrapper) {
            auto dataBlock = dataWrapper->values<float>();
            std::cout << "📊 Read " << dataBlock.data.size() << " voltage samples" << std::endl;
            
            // Show first few samples
            std::cout << "First 5 samples: ";
            for (size_t i = 0; i < std::min(size_t(5), dataBlock.data.size()); ++i) {
                std::cout << dataBlock.data[i] << " ";
            }
            std::cout << " (volts)" << std::endl;
        }
        
        // Step 4: Read the timestamps
        auto timestampsWrapper = electricalSeries->readTimestamps();
        if (timestampsWrapper) {
            auto timestampsBlock = timestampsWrapper->values<double>();
            std::cout << "⏰ Read " << timestampsBlock.data.size() << " timestamps" << std::endl;
            
            if (timestampsBlock.data.size() >= 2) {
                double samplingRate = 1.0 / (timestampsBlock.data[1] - timestampsBlock.data[0]);
                std::cout << "📊 Sampling rate: " << samplingRate << " Hz" << std::endl;
            }
        }
        
        // Step 5: Read electrode information
        auto electrodesWrapper = electricalSeries->readElectrodes();
        if (electrodesWrapper) {
            auto electrodesBlock = electrodesWrapper->values<int>();
            std::cout << "🔌 Number of electrodes: " << electrodesBlock.data.size() << std::endl;
        }
        
        // Step 6: Close the file
        io->close();
        std::cout << "✅ Done!" << std::endl;
        
    } catch (const std::exception& e) {
        std::cerr << "Error: " << e.what() << std::endl;
    }
}

/**
 * @brief Example of reading specific data ranges
 */
void readElectricalSeriesWithHDF5(const std::string& filePath) {
    std::cout << "\nReading with direct HDF5 access..." << std::endl;
    
    try {
        // Open HDF5 file directly
        #include <H5Cpp.h>
        H5::H5File file(filePath, H5F_ACC_RDONLY);
        
        // Open the data dataset
        H5::DataSet dataset = file.openDataSet("/acquisition/ElectricalSeries1/data");
        
        // Get dimensions
        H5::DataSpace dataspace = dataset.getSpace();
        std::vector<hsize_t> dims(2);
        dataspace.getSimpleExtentDims(dims.data(), nullptr);
        
        std::cout << "📊 Data shape: " << dims[0] << " samples × " << dims[1] << " channels" << std::endl;
        
        // Read first 100 samples from first channel
        std::vector<float> data(100);
        
        // Define what to read (first 100 samples, first channel)
        hsize_t offset[2] = {0, 0};      // Start at sample 0, channel 0
        hsize_t count[2] = {100, 1};     // Read 100 samples, 1 channel
        dataspace.selectHyperslab(H5S_SELECT_SET, count, offset);
        
        // Define memory space
        hsize_t memDims[1] = {100};
        H5::DataSpace memSpace(1, memDims);
        
        // Read the data
        dataset.read(data.data(), H5::PredType::NATIVE_FLOAT, memSpace, dataspace);
        
        std::cout << "📊 Read first 100 samples from channel 0" << std::endl;
        std::cout << "First 5 values: ";
        for (int i = 0; i < 5; ++i) {
            std::cout << data[i] << " ";
        }
        std::cout << std::endl;
        
        file.close();
        
    } catch (const std::exception& e) {
        std::cerr << "HDF5 Error: " << e.what() << std::endl;
    }
}

/**
 * @brief Main function
 */
int main(int argc, char* argv[]) {
    std::string filePath;
    
    if (argc < 2) {
        // Use default path for demonstration
        filePath = "/Users/macbook/Library/Containers/com.example.nwbapplication/Data/Documents/example_recording2.nwb";
        std::cout << "Using default file: " << filePath << std::endl;
        std::cout << "Usage: " << argv[0] << " <path_to_nwb_file>" << std::endl;
    } else {
        filePath = argv[1];
    }
    
    std::cout << "🚀 Simple Electrical Series Reader" << std::endl;
    std::cout << "==================================" << std::endl;
    
    // Method 1: Using AQNWB library
    readElectricalSeriesSimple(filePath);
    
    // Method 2: Direct HDF5 (uncomment if you have HDF5 headers)
    // readElectricalSeriesWithHDF5(filePath);
    
    return 0;
}






