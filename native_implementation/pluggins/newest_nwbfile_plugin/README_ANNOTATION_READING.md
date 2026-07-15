# Reading Annotation Series from NWB Files

This guide explains how to read annotation series data from NWB (Neurodata Without Borders) files using the `nwbfile_plugin`.

## Overview

Annotation series in NWB files store text-based records about experiments, typically containing:
- **Data**: String annotations (e.g., "stimulus onset", "behavioral event")
- **Timestamps**: When each annotation occurred (in seconds)
- **Metadata**: Description, comments, and other attributes

## Basic Structure

Annotation series are typically stored in NWB files at paths like:
- `/acquisition/recording1` - Annotations for the first recording
- `/acquisition/recording2` - Annotations for the second recording
- `/processing/annotations` - Processed annotations
- `/intervals/annotations` - Interval-based annotations

## Method 1: Using AnnotationSeries Class (Recommended)

This is the most straightforward approach for reading annotation series:

```cpp
#include "nwb/misc/AnnotationSeries.hpp"
#include "io/BaseIO.hpp"

using namespace AQNWB::NWB;
using namespace AQNWB::IO;

// Open the NWB file
std::shared_ptr<BaseIO> io = AQNWB::createIO("HDF5", "your_file.nwb");
io->open(FileMode::ReadOnly);

// Create annotation series object
auto annotationSeries = RegisteredType::create<AnnotationSeries>("/acquisition/recording1", io);

// Read the annotation data
auto dataWrapper = annotationSeries->readData();
if (dataWrapper) {
    auto dataBlock = dataWrapper->values<std::string>();
    
    std::cout << "Found " << dataBlock.data.size() << " annotations:" << std::endl;
    for (size_t i = 0; i < dataBlock.data.size(); ++i) {
        std::cout << "  [" << i << "]: " << dataBlock.data[i] << std::endl;
    }
}

// Read associated timestamps
auto timestampsWrapper = annotationSeries->readTimestamps();
if (timestampsWrapper) {
    auto timestampsBlock = timestampsWrapper->values<double>();
    
    std::cout << "Timestamps:" << std::endl;
    for (size_t i = 0; i < timestampsBlock.data.size(); ++i) {
        std::cout << "  [" << i << "]: " << timestampsBlock.data[i] << " seconds" << std::endl;
    }
}

// Read metadata
auto descriptionWrapper = annotationSeries->readDescription();
if (descriptionWrapper) {
    std::cout << "Description: " << descriptionWrapper->values<std::string>().data[0] << std::endl;
}

io->close();
```

## Method 2: Using DataTyped for Type-Safe Access

For more control and type safety, you can use the `DataTyped` class:

```cpp
#include "nwb/hdmf/base/Data.hpp"

// Create Data object first
auto dataObj = RegisteredType::create<Data>("/acquisition/recording1/data", io);

// Convert to DataTyped for type-safe access
auto dataTyped = DataTyped<std::string>::fromData(*dataObj);

// Read the data
auto typedDataWrapper = dataTyped->readData();
if (typedDataWrapper) {
    auto typedDataBlock = typedDataWrapper->values<std::string>();
    
    std::cout << "Data size: " << typedDataBlock.data.size() << std::endl;
    for (const auto& annotation : typedDataBlock.data) {
        std::cout << "  " << annotation << std::endl;
    }
}
```

## Method 3: Reading Timestamps Separately

You can also read timestamps directly from their dataset:

```cpp
// Create Data object for timestamps
auto timestampsObj = RegisteredType::create<Data>("/acquisition/recording1/timestamps", io);

// Convert to DataTyped for type-safe access
auto timestampsTyped = DataTyped<double>::fromData(*timestampsObj);

// Read the timestamps
auto timestampsWrapper = timestampsTyped->readData();
if (timestampsWrapper) {
    auto timestampsBlock = timestampsWrapper->values<double>();
    
    std::cout << "Timestamps:" << std::endl;
    for (const auto& timestamp : timestampsBlock.data) {
        std::cout << "  " << timestamp << " seconds" << std::endl;
    }
}
```

## Helper Functions

Here are some useful helper functions for reading annotation series:

### Read annotations only:
```cpp
std::vector<std::string> readAnnotationSeries(const std::string& filePath, const std::string& annotationPath) {
    std::vector<std::string> annotations;
    
    try {
        std::shared_ptr<BaseIO> io = AQNWB::createIO("HDF5", filePath);
        io->open(FileMode::ReadOnly);
        
        auto annotationSeries = RegisteredType::create<AnnotationSeries>(annotationPath, io);
        auto dataWrapper = annotationSeries->readData();
        
        if (dataWrapper) {
            auto dataBlock = dataWrapper->values<std::string>();
            annotations = dataBlock.data;
        }
        
        io->close();
    } catch (const std::exception& e) {
        std::cerr << "Error reading annotation series: " << e.what() << std::endl;
    }
    
    return annotations;
}
```

### Read annotations with timestamps:
```cpp
std::pair<std::vector<std::string>, std::vector<double>> readAnnotationSeriesWithTimestamps(
    const std::string& filePath, const std::string& annotationPath) {
    
    std::vector<std::string> annotations;
    std::vector<double> timestamps;
    
    try {
        std::shared_ptr<BaseIO> io = AQNWB::createIO("HDF5", filePath);
        io->open(FileMode::ReadOnly);
        
        auto annotationSeries = RegisteredType::create<AnnotationSeries>(annotationPath, io);
        
        // Read annotation data
        auto dataWrapper = annotationSeries->readData();
        if (dataWrapper) {
            auto dataBlock = dataWrapper->values<std::string>();
            annotations = dataBlock.data;
        }
        
        // Read timestamps
        auto timestampsWrapper = annotationSeries->readTimestamps();
        if (timestampsWrapper) {
            auto timestampsBlock = timestampsWrapper->values<double>();
            timestamps = timestampsBlock.data;
        }
        
        io->close();
    } catch (const std::exception& e) {
        std::cerr << "Error reading annotation series with timestamps: " << e.what() << std::endl;
    }
    
    return {annotations, timestamps};
}
```

## Error Handling

Always wrap your annotation reading code in try-catch blocks:

```cpp
try {
    auto annotationSeries = RegisteredType::create<AnnotationSeries>(path, io);
    auto dataWrapper = annotationSeries->readData();
    
    if (dataWrapper) {
        auto dataBlock = dataWrapper->values<std::string>();
        // Process the data
    } else {
        std::cout << "No data found in annotation series" << std::endl;
    }
} catch (const std::exception& e) {
    std::cerr << "Error reading annotation series: " << e.what() << std::endl;
}
```

## Common Issues and Solutions

### 1. Path not found
If you get an error about the path not existing, try these common paths:
- `/acquisition/recording1`
- `/acquisition/recording2`
- `/acquisition/annotations`
- `/processing/annotations`
- `/intervals/annotations`

### 2. Data type mismatch
Make sure you're using the correct data type:
- Use `values<std::string>()` for annotation data
- Use `values<double>()` for timestamps

### 3. Empty data
Check if the data wrapper is valid before accessing:
```cpp
if (dataWrapper) {
    auto dataBlock = dataWrapper->values<std::string>();
    if (!dataBlock.data.empty()) {
        // Process the data
    }
}
```

## Complete Example

See `example_read_annotations.cpp` for a complete working example that demonstrates all these methods.

## Data Structure

The annotation series data is returned as a `DataBlock<std::string>` with:
- `data`: Vector of annotation strings
- `shape`: Dimensions of the data (typically `[num_annotations]`)

Timestamps are returned as a `DataBlock<double>` with:
- `data`: Vector of timestamp values in seconds
- `shape`: Dimensions of the data (typically `[num_annotations]`)

## Performance Tips

1. **Close files properly**: Always call `io->close()` when done
2. **Use RAII**: Use smart pointers to manage IO objects
3. **Check for null**: Always verify data wrappers before accessing
4. **Batch processing**: For large files, consider reading data in chunks

## Related Classes

- `AnnotationSeries`: Main class for annotation series
- `DataTyped<T>`: Type-safe data access
- `DataBlock<T>`: Container for typed data
- `BaseIO`: Interface for file I/O operations

