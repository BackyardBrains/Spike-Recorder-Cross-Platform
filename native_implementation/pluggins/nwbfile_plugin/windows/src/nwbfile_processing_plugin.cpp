#include "nwbfile_processing_plugin.hpp"

#include <H5Cpp.h>

#include <algorithm>
#include <cstdarg>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <iostream>
#include <memory>
#include <string>
#include <vector>

#include "Channel.hpp"
#include "Utils.hpp"
#include "io/BaseIO.hpp"
#include "io/RecordingObjects.hpp"
#include "io/nwbio_utils.hpp"
#include "nwb/NWBFile.hpp"
#include "nwb/device/Device.hpp"
#include "nwb/ecephys/ElectricalSeries.hpp"
#include "nwb/ecephys/SpikeEventSeries.hpp"
#include "nwb/event/EventsTable.hpp"
#include "nwb/hdmf/table/MeaningsTable.hpp"
#include "nwb/hdmf/table/VectorData.hpp"
#include "nwb/misc/AnnotationSeries.hpp"

#if defined(__ANDROID__)
#include <android/log.h>
#endif

void file_log_nwbfile(const char* fmt, ...)
{
  va_list args;
  va_start(args, fmt);
#ifdef __ANDROID__
  __android_log_vprint(ANDROID_LOG_VERBOSE, "ndk", fmt, args);
#else
  vprintf(fmt, args);
#endif
  va_end(args);
}

namespace {

std::string resolveOutputPath(const char* path)
{
  namespace fs = std::filesystem;
  if (path == nullptr || path[0] == '\0') {
#if defined(__EMSCRIPTEN__)
    return "/nwb/example_recording.nwb";
#else
    return "example_recording.nwb";
#endif
  }
  fs::path input(path);
  std::error_code ec;
  if (fs::is_directory(input, ec) || !input.has_extension()) {
    return (input / "example_recording.nwb").string();
  }
  return input.string();
}

void ensureParentDirectory(const std::string& filePath)
{
  namespace fs = std::filesystem;
  const fs::path parent = fs::path(filePath).parent_path();
  if (!parent.empty()) {
    std::error_code ec;
    fs::create_directories(parent, ec);
  }
}

void listHDF5Contents(H5::H5File& file,
                      const std::string& groupName = "/",
                      int depth = 0)
{
  try {
    std::string indent(depth * 2, ' ');
    std::cout << indent << "Group: " << groupName << std::endl;

    H5::Group group =
        (groupName == "/") ? file.openGroup("/") : file.openGroup(groupName);
    hsize_t numObjs = group.getNumObjs();

    for (hsize_t i = 0; i < numObjs; i++) {
      std::string objName = group.getObjnameByIdx(i);
      H5G_obj_t objType = group.getObjTypeByIdx(i);
      std::string fullPath =
          (groupName == "/") ? "/" + objName : groupName + "/" + objName;

      if (objType == H5G_GROUP) {
        if (depth < 3) {
          listHDF5Contents(file, fullPath, depth + 1);
        } else {
          std::cout << indent << "  " << objName << " (group, not expanded)"
                    << std::endl;
        }
      } else if (objType == H5G_DATASET) {
        try {
          H5::DataSet dataset = file.openDataSet(fullPath);
          H5::DataSpace dataspace = dataset.getSpace();
          int rank = dataspace.getSimpleExtentNdims();
          std::vector<hsize_t> dims(rank);
          dataspace.getSimpleExtentDims(dims.data(), nullptr);
          std::cout << indent << "  " << objName << " (dataset, dims: ";
          for (int j = 0; j < rank; j++) {
            std::cout << dims[j];
            if (j < rank - 1) std::cout << "x";
          }
          std::cout << ")" << std::endl;
        } catch (const H5::Exception&) {
          std::cout << indent << "  " << objName << " (dataset)" << std::endl;
        }
      }
    }
  } catch (const H5::Exception& e) {
    std::cout << "  Error listing " << groupName << ": " << e.getDetailMsg()
              << std::endl;
  }
}

}  // namespace

std::vector<uint8_t> g_nwb_file_data;
bool g_nwb_file_ready = false;

// Persistent recording session state (Spike-Recorder style)
std::shared_ptr<AQNWB::IO::BaseIO> g_io;
std::shared_ptr<AQNWB::NWB::NWBFile> g_nwbfile;
std::shared_ptr<AQNWB::IO::RecordingObjects> g_recordingObjects;
std::vector<AQNWB::Types::ChannelVector> g_recordingArrays;
std::vector<AQNWB::Types::SizeType> g_containerIndexes;
std::vector<int32_t> g_spikeContainerIndexes;
std::vector<int32_t> g_spikeEventCounts;
bool g_recordingStarted = false;
std::string g_outputPath;
AQNWB::Types::SizeType g_numSamplesCounter = 0;

// EventsTable session state (row-based acquisition)
std::shared_ptr<AQNWB::NWB::EventsTable> g_eventsTable;
std::shared_ptr<AQNWB::NWB::MeaningsTable> g_eventMeaningsTable;
AQNWB::Types::SizeType g_eventRowCount = 0;
float g_eventTimestampResolution = 0.001f;

// Snapshot of EventsTable rows loaded from a file during seek/open.
// Used for review/playback because nwbfile_seek_electrical_series always
// closes its temporary AQNWB IO handle at the end of the call, and
// RegisteredType only holds a weak_ptr to that IO — so keeping a live
// EventsTable across seek would crash on the next nwbfile_read_event.
struct CachedNwbEvent {
  float timestampSeconds;
  int32_t eventLabel;
  uint8_t deleted;
};
std::vector<CachedNwbEvent> g_cachedEvents;

// In-session cache for event_type MeaningsTable (source of truth for reads).
struct CachedMeaning {
  int32_t value;
  std::string meaning;
};
std::vector<CachedMeaning> g_cachedMeanings;

namespace {

bool copyCString(char* out, int32_t capacity, const std::string& src)
{
  if (out == nullptr || capacity <= 0) {
    return false;
  }
  const size_t maxCopy = static_cast<size_t>(capacity - 1);
  const size_t n = std::min(src.size(), maxCopy);
  if (n > 0) {
    std::memcpy(out, src.data(), n);
  }
  out[n] = '\0';
  return true;
}

// writeDataBlock always advances the append cursor; restore it after mid-row
// overwrites so subsequent addRow appends stay contiguous.
AQNWB::Types::Status overwriteEventCell(
    const std::shared_ptr<AQNWB::IO::BaseRecordingData>& recordData,
    AQNWB::Types::SizeType rowIndex,
    const AQNWB::IO::BaseDataType& type,
    const void* data)
{
  if (!recordData) {
    return AQNWB::Types::Status::Failure;
  }
  auto& position =
      const_cast<AQNWB::Types::SizeArray&>(recordData->getPosition());
  const AQNWB::Types::SizeType savedPosition =
      position.empty() ? 0 : position[0];
  auto status = recordData->writeDataBlock(
      AQNWB::Types::SizeArray {1},
      AQNWB::Types::SizeArray {rowIndex},
      type,
      data);
  if (!position.empty()) {
    position[0] = savedPosition;
  }
  return status;
}

AQNWB::Types::Status overwriteMeaningString(
    const std::shared_ptr<AQNWB::IO::BaseRecordingData>& recordData,
    AQNWB::Types::SizeType rowIndex,
    const std::string& meaning)
{
  if (!recordData) {
    return AQNWB::Types::Status::Failure;
  }
  auto& position =
      const_cast<AQNWB::Types::SizeArray&>(recordData->getPosition());
  const AQNWB::Types::SizeType savedPosition =
      position.empty() ? 0 : position[0];
  std::vector<std::string> values {meaning};
  auto status = recordData->writeDataBlock(
      AQNWB::Types::SizeArray {1},
      AQNWB::Types::SizeArray {rowIndex},
      AQNWB::IO::BaseDataType::V_STR,
      values);
  if (!position.empty()) {
    position[0] = savedPosition;
  }
  return status;
}

void resetEventsSessionState()
{
  g_eventsTable.reset();
  g_eventMeaningsTable.reset();
  g_eventRowCount = 0;
  g_cachedEvents.clear();
  g_cachedMeanings.clear();
}

void resetSpikeSessionState()
{
  g_spikeContainerIndexes.clear();
  g_spikeEventCounts.clear();
  g_recordingStarted = false;
}

AQNWB::Types::Status ensureRecordingStarted()
{
  if (g_recordingStarted) {
    return AQNWB::Types::Status::Success;
  }
  if (!g_io) {
    return AQNWB::Types::Status::Failure;
  }

  auto startRecordingStatus = g_io->startRecording();
  if (startRecordingStatus != AQNWB::Types::Status::Success) {
    std::cerr << "Failed to start recording" << std::endl;
    return startRecordingStatus;
  }

  if (g_eventMeaningsTable) {
    std::vector<AQNWB::NWB::DynamicTable::RowData> meaningsRows;
    meaningsRows.reserve(10);
    g_cachedMeanings.clear();
    g_cachedMeanings.reserve(10);
    for (int32_t label = 0; label <= 9; ++label) {
      const std::string meaning =
          std::string("event_") + std::to_string(label);
      meaningsRows.push_back({{"value", label}, {"meaning", meaning}});
      g_cachedMeanings.push_back({label, meaning});
    }
    auto meaningsStatus = g_eventMeaningsTable->addRows(meaningsRows);
    if (meaningsStatus != AQNWB::Types::Status::Success) {
      std::cerr << "Failed to write event_type meanings" << std::endl;
      return meaningsStatus;
    }
  }

  g_recordingStarted = true;
  std::cout << "START RECORDING" << std::endl;
  return AQNWB::Types::Status::Success;
}

}  // namespace

FFI_PLUGIN_EXPORT int sum(int a, int b) { return a + b; }

FFI_PLUGIN_EXPORT int sum_long_running(int a, int b)
{
#if _WIN32
  Sleep(5000);
#else
  usleep(5000 * 1000);
#endif
  return a + b;
}

FFI_PLUGIN_EXPORT int32_t processing_init(const char* path,
                                          int sampleRate,
                                          int channelCount,
                                          const char* deviceInfo,
                                          const char* deviceManufacturer)
{
  try {
    H5::Exception::dontPrint();
    std::cout << "AQNWB 0.4.0 Recording Workflow" << std::endl;
    std::cout << "SampleRate: " << sampleRate
              << " ChannelCount: " << channelCount << std::endl;

    g_outputPath = resolveOutputPath(path);
    ensureParentDirectory(g_outputPath);
    g_numSamplesCounter = 0;
    g_containerIndexes.clear();
    g_recordingArrays.clear();
    resetEventsSessionState();
    resetSpikeSessionState();
    g_nwb_file_ready = false;
    g_nwb_file_data.clear();

    std::cout << "Output NWB file: " << g_outputPath << std::endl;

    g_io = AQNWB::createIO("HDF5", g_outputPath);
    auto openStatus = g_io->open(AQNWB::IO::FileMode::Overwrite);
    if (openStatus != AQNWB::Types::Status::Success) {
      std::cerr << "processing_init: Failed to open IO (code 1): "
                << g_outputPath << std::endl;
      return 1;
    }

    g_recordingObjects = g_io->getRecordingObjects();
    g_nwbfile = AQNWB::NWB::NWBFile::create(g_io);
    auto initStatus = g_nwbfile->initialize(
        AQNWB::generateUuid(),
        "Example ecephys session",
        "Generated by AqNWB 0.4.0 / Spike-Recorder workflow");
    if (initStatus != AQNWB::Types::Status::Success) {
      std::cerr << "processing_init: Failed to initialize NWB file (code 2)"
                << std::endl;
      return 2;
    }

    const std::string deviceInfoStr =
        (deviceInfo != nullptr) ? std::string(deviceInfo) : "";
    const std::string deviceManufacturerStr =
        (deviceManufacturer != nullptr) ? std::string(deviceManufacturer) : "";

    auto device = AQNWB::NWB::Device::create(
        "/general/devices/recording_device", g_io);
    if (device == nullptr
        || device->initialize(deviceInfoStr, deviceManufacturerStr)
            != AQNWB::Types::Status::Success) {
      std::cerr << "processing_init: Failed to initialize Device (code 3)"
                << std::endl;
      return 3;
    }
    std::cout << "Device: " << deviceInfoStr << " / " << deviceManufacturerStr
              << std::endl;

    {
      AQNWB::Types::ChannelVector array1;
      const std::string groupName = "Array1";
      for (int ch = 0; ch < channelCount; ++ch) {
        array1.emplace_back("chan_" + std::to_string(ch),
                            groupName,
                            /*groupIndex=*/0,
                            /*localIndex=*/ch,
                            /*globalIndex=*/ch,
                            1e6f,
                            static_cast<float>(sampleRate),
                            0.195f);
      }
      g_recordingArrays.emplace_back(std::move(array1));
    }

    g_spikeContainerIndexes.assign(channelCount, -1);
    g_spikeEventCounts.assign(channelCount, 0);

    auto electrodesTable =
        g_nwbfile->createElectrodesTable(g_recordingArrays, true, 50);
    if (electrodesTable == nullptr) {
      std::cerr << "processing_init: Failed to create electrodes table "
                   "(code 4)"
                << std::endl;
      return 4;
    }

    std::vector<std::string> recordingNames = {"ElectricalSeries1"};
    auto elecSeriesStatus = g_nwbfile->createElectricalSeries(
        g_recordingArrays,
        recordingNames,
        AQNWB::IO::BaseDataType::I16,
        g_containerIndexes);
    if (elecSeriesStatus != AQNWB::Types::Status::Success) {
      std::cerr << "processing_init: Failed to create ElectricalSeries "
                   "(code 5)"
                << std::endl;
      return 5;
    }

    // EventsTable must be created before startRecording() (SWMR).
    // Schema follows AqNWB row-based EventsTable + MeaningsTable workflow:
    // timestamp + event_type (+ soft-delete flag for update/delete while appending).
    g_eventTimestampResolution =
        sampleRate > 0 ? (1.0f / static_cast<float>(sampleRate)) : 0.001f;
    auto eventColumnSpecs = AQNWB::NWB::EventsTable::createDefaultDataSpecs(
        g_eventTimestampResolution,
        -1.0f,  // omit duration
        false,  // no annotation column
        100);
    AQNWB::IO::ArrayDataSetConfig eventTypeConfig(AQNWB::IO::BaseDataType::I32,
                                                  AQNWB::Types::SizeArray {0},
                                                  AQNWB::Types::SizeArray {100});
    eventColumnSpecs.push_back(AQNWB::NWB::VectorData::createDataSpec(
        "event_type",
        eventTypeConfig,
        "Integer code identifying the Spike-Recorder event marker label."));
    AQNWB::IO::ArrayDataSetConfig deletedConfig(AQNWB::IO::BaseDataType::U8,
                                                AQNWB::Types::SizeArray {0},
                                                AQNWB::Types::SizeArray {100});
    eventColumnSpecs.push_back(AQNWB::NWB::VectorData::createDataSpec(
        "deleted",
        deletedConfig,
        "Soft-delete flag: 0 = active event, 1 = deleted."));

    g_eventsTable = g_nwbfile->createEventsTable(
        "markers",
        "Spike-Recorder keyboard / marker events.",
        "Manual event markers entered during acquisition",
        eventColumnSpecs);
    if (!g_eventsTable) {
      std::cerr << "processing_init: Failed to create EventsTable (code 6)"
                << std::endl;
      return 6;
    }

    g_eventMeaningsTable = g_eventsTable->createMeaningsTable("event_type");
    if (!g_eventMeaningsTable) {
      std::cerr << "processing_init: Failed to create event_type "
                   "MeaningsTable (code 7)"
                << std::endl;
      return 7;
    }

    std::cout << "NWB session ready (call nwbfile_create_spike_event_series "
                 "before first data write)" << std::endl;
    return 0;
  } catch (const H5::Exception& e) {
    std::cerr << "processing_init: HDF5 error (code 8): " << e.getDetailMsg()
              << std::endl;
    return 8;
  } catch (const std::exception& e) {
    std::cerr << "processing_init: std::exception (code 9): " << e.what()
              << std::endl;
    return 9;
  } catch (...) {
    std::cerr << "processing_init: Unknown error (code 10)" << std::endl;
    return 10;
  }
}

FFI_PLUGIN_EXPORT int32_t nwbfile_add_electrical_series(short* inSamples,
                                                        int* samplesCount,
                                                        int selectedChannel,
                                                        int channelCount,
                                                        int isFinishRecording)
{
  (void)selectedChannel;
  if (!inSamples || !samplesCount || channelCount <= 0) {
    std::cerr << "Invalid input parameters" << std::endl;
    return -1;
  }
  if (!g_io || !g_recordingObjects || g_containerIndexes.empty()
      || g_recordingArrays.empty()) {
    std::cerr << "Recording session not initialized" << std::endl;
    return -1;
  }

  if (ensureRecordingStarted() != AQNWB::Types::Status::Success) {
    return -1;
  }

  for (int i = 0; i < channelCount; i++) {
    if (samplesCount[i] <= 0) {
      std::cerr << "Invalid sample count for channel " << i << std::endl;
      return -1;
    }
  }

  short** arrSamples = nullptr;
  try {
    arrSamples = new short*[channelCount];
    for (int i = 0; i < channelCount; i++) {
      arrSamples[i] = nullptr;
    }
    for (int i = 0; i < channelCount; i++) {
      arrSamples[i] = new short[samplesCount[i]];
      std::copy(inSamples + i * samplesCount[i],
                inSamples + (i + 1) * samplesCount[i],
                arrSamples[i]);
    }

    const AQNWB::Types::SizeType containerIndex = g_containerIndexes.at(0);
    const auto& channels = g_recordingArrays[0];
    const AQNWB::Types::SizeType numSamples =
        static_cast<AQNWB::Types::SizeType>(samplesCount[0]);

    const AQNWB::Types::SizeType startSample = g_numSamplesCounter;
    g_numSamplesCounter += numSamples;

    std::vector<double> timestamps(numSamples);
    const double samplingRate =
        static_cast<double>(channels[0].getSamplingRate());
    const double dt = 1.0 / samplingRate;
    for (AQNWB::Types::SizeType i = 0; i < numSamples; ++i) {
      timestamps[i] = static_cast<double>(startSample + i) * dt;
    }

    int channelIndex = 0;
    for (const auto& ch : channels) {
      if (channelIndex >= channelCount) break;
      auto writeStatus = AQNWB::IO::writeElectricalSeriesData(
          g_recordingObjects,
          containerIndex,
          ch,
          static_cast<AQNWB::Types::SizeType>(samplesCount[channelIndex]),
          static_cast<const void*>(arrSamples[channelIndex]),
          static_cast<const void*>(timestamps.data()));
      if (writeStatus != AQNWB::Types::Status::Success) {
        std::cerr << "Failed to write channel " << ch.getName() << std::endl;
        for (int i = 0; i < channelCount; i++) delete[] arrSamples[i];
        delete[] arrSamples;
        return 1;
      }
      channelIndex++;
    }

    if (g_io->flush() != AQNWB::Types::Status::Success) {
      std::cerr << "Flush failed" << std::endl;
      for (int i = 0; i < channelCount; i++) delete[] arrSamples[i];
      delete[] arrSamples;
      return 1;
    }

    if (isFinishRecording == 1) {
      if (g_io->stopRecording() != AQNWB::Types::Status::Success) {
        std::cerr << "Failed to stop recording" << std::endl;
        for (int i = 0; i < channelCount; i++) delete[] arrSamples[i];
        delete[] arrSamples;
        return 1;
      }
      std::cout << "Successfully wrote recording to: " << g_outputPath
                << std::endl;
      if (g_io->close() != AQNWB::Types::Status::Success) {
        std::cerr << "Failed to close IO" << std::endl;
        for (int i = 0; i < channelCount; i++) delete[] arrSamples[i];
        delete[] arrSamples;
        return 1;
      }
      g_io.reset();
      g_nwbfile.reset();
      g_recordingObjects.reset();
      resetEventsSessionState();
      resetSpikeSessionState();
      std::cout << "IO CLOSED" << std::endl;
    }

    for (int i = 0; i < channelCount; i++) delete[] arrSamples[i];
    delete[] arrSamples;
    return 0;
  } catch (const H5::Exception& e) {
    std::cerr << "HDF5 error in add: " << e.getDetailMsg() << std::endl;
    if (arrSamples) {
      for (int i = 0; i < channelCount; i++) delete[] arrSamples[i];
      delete[] arrSamples;
    }
    return 1;
  } catch (const std::exception& e) {
    std::cerr << "Error in nwbfile_add_electrical_series: " << e.what()
              << std::endl;
    if (arrSamples) {
      for (int i = 0; i < channelCount; i++) delete[] arrSamples[i];
      delete[] arrSamples;
    }
    return 1;
  }
}

FFI_PLUGIN_EXPORT int32_t nwbfile_create_spike_event_series(int32_t channelIndex)
{
  if (!g_io || !g_nwbfile || g_recordingArrays.empty()) {
    std::cerr << "Recording session not initialized" << std::endl;
    return -1;
  }
  if (channelIndex < 0
      || channelIndex >= static_cast<int32_t>(g_recordingArrays[0].size())) {
    std::cerr << "Invalid channel index for SpikeEventSeries: " << channelIndex
              << std::endl;
    return -1;
  }
  if (g_recordingStarted) {
    std::cerr << "Cannot create SpikeEventSeries after recording has started"
              << std::endl;
    return -1;
  }
  if (channelIndex < static_cast<int32_t>(g_spikeContainerIndexes.size())
      && g_spikeContainerIndexes[static_cast<size_t>(channelIndex)] >= 0) {
    return g_spikeContainerIndexes[static_cast<size_t>(channelIndex)];
  }

  try {
    AQNWB::Types::ChannelVector singleChannel;
    singleChannel.push_back(
        g_recordingArrays[0][static_cast<size_t>(channelIndex)]);

    std::vector<AQNWB::Types::ChannelVector> arrays = {singleChannel};
    std::vector<std::string> names = {
        "SpikeEventSeries_ch" + std::to_string(channelIndex)};
    std::vector<AQNWB::Types::SizeType> containerIndexes;
    auto status = g_nwbfile->createSpikeEventSeries(
        arrays,
        names,
        AQNWB::IO::BaseDataType::F32,
        containerIndexes);
    if (status != AQNWB::Types::Status::Success || containerIndexes.empty()) {
      std::cerr << "Failed to create SpikeEventSeries for channel "
                << channelIndex << std::endl;
      return -1;
    }

    const int32_t containerIndex =
        static_cast<int32_t>(containerIndexes.front());
    g_spikeContainerIndexes[static_cast<size_t>(channelIndex)] = containerIndex;
    std::cout << "Created SpikeEventSeries for channel " << channelIndex
              << " (container " << containerIndex << ")" << std::endl;
    return containerIndex;
  } catch (const std::exception& e) {
    std::cerr << "Error in nwbfile_create_spike_event_series: " << e.what()
              << std::endl;
    return -1;
  } catch (...) {
    std::cerr << "Unknown error in nwbfile_create_spike_event_series"
              << std::endl;
    return -1;
  }
}

FFI_PLUGIN_EXPORT int32_t nwbfile_write_spike_event(int32_t channelIndex,
                                                    float timestampSeconds,
                                                    const float* waveform,
                                                    int32_t numSamples)
{
  if (waveform == nullptr || numSamples <= 0) {
    std::cerr << "Invalid spike waveform parameters" << std::endl;
    return -1;
  }
  if (!g_io || !g_recordingObjects) {
    std::cerr << "Recording session not initialized" << std::endl;
    return -1;
  }
  if (channelIndex < 0
      || channelIndex >= static_cast<int32_t>(g_spikeContainerIndexes.size())) {
    std::cerr << "Invalid channel index for spike write: " << channelIndex
              << std::endl;
    return -1;
  }
  if (g_spikeContainerIndexes[static_cast<size_t>(channelIndex)] < 0) {
    std::cerr << "SpikeEventSeries not created for channel " << channelIndex
              << std::endl;
    return -1;
  }
  if (ensureRecordingStarted() != AQNWB::Types::Status::Success) {
    return -1;
  }

  try {
    const AQNWB::Types::SizeType containerIndex =
        static_cast<AQNWB::Types::SizeType>(
            g_spikeContainerIndexes[static_cast<size_t>(channelIndex)]);
    const double timestamp = static_cast<double>(timestampSeconds);
    auto writeStatus = AQNWB::IO::writeSpikeEventData(
        g_recordingObjects,
        containerIndex,
        static_cast<AQNWB::Types::SizeType>(numSamples),
        1,
        waveform,
        &timestamp);
    if (writeStatus != AQNWB::Types::Status::Success) {
      std::cerr << "Failed to write spike event for channel " << channelIndex
                << std::endl;
      return -1;
    }

    g_spikeEventCounts[static_cast<size_t>(channelIndex)]++;
    if (g_io->flush() != AQNWB::Types::Status::Success) {
      std::cerr << "Failed to flush after spike write" << std::endl;
      return -1;
    }
    return 0;
  } catch (const std::exception& e) {
    std::cerr << "Error in nwbfile_write_spike_event: " << e.what() << std::endl;
    return -1;
  } catch (...) {
    std::cerr << "Unknown error in nwbfile_write_spike_event" << std::endl;
    return -1;
  }
}

FFI_PLUGIN_EXPORT int32_t nwbfile_get_spike_event_count(int32_t channelIndex)
{
  if (channelIndex < 0
      || channelIndex >= static_cast<int32_t>(g_spikeEventCounts.size())) {
    return -1;
  }
  return g_spikeEventCounts[static_cast<size_t>(channelIndex)];
}

FFI_PLUGIN_EXPORT int32_t nwbfile_add_event(float timestampSeconds,
                                            int32_t eventLabel)
{
  if (!g_io || !g_eventsTable) {
    std::cerr << "EventsTable not initialized" << std::endl;
    return -1;
  }
  if (ensureRecordingStarted() != AQNWB::Types::Status::Success) {
    return -1;
  }
  try {
    // Row-based append: each event is one EventsTable row (AqNWB addRow).
    AQNWB::NWB::DynamicTable::RowData row = {
        {"timestamp", timestampSeconds},
        {"event_type", eventLabel},
        {"deleted", static_cast<uint8_t>(0)},
    };
    auto status = g_eventsTable->addRow(row);
    if (status != AQNWB::Types::Status::Success) {
      std::cerr << "Failed to add event row" << std::endl;
      return -1;
    }
    if (g_io->flush() != AQNWB::Types::Status::Success) {
      std::cerr << "Failed to flush after add event" << std::endl;
      return -1;
    }
    const int32_t rowIndex = static_cast<int32_t>(g_eventRowCount);
    g_eventRowCount += 1;
    return rowIndex;
  } catch (const std::exception& e) {
    std::cerr << "Error in nwbfile_add_event: " << e.what() << std::endl;
    return -1;
  }
}

FFI_PLUGIN_EXPORT int32_t nwbfile_update_event(int32_t rowIndex,
                                               float timestampSeconds,
                                               int32_t eventLabel)
{
  if (!g_io || !g_eventsTable) {
    std::cerr << "EventsTable not initialized" << std::endl;
    return -1;
  }
  if (rowIndex < 0
      || static_cast<AQNWB::Types::SizeType>(rowIndex) >= g_eventRowCount) {
    std::cerr << "nwbfile_update_event invalid rowIndex: " << rowIndex
              << std::endl;
    return -1;
  }
  try {
    const AQNWB::Types::SizeType idx =
        static_cast<AQNWB::Types::SizeType>(rowIndex);
    auto timestampCol = g_eventsTable->readTimestampColumn();
    auto eventTypeCol = g_eventsTable->readColumn<int32_t>("event_type");
    auto deletedCol = g_eventsTable->readColumn<uint8_t>("deleted");
    if (!timestampCol || !eventTypeCol || !deletedCol
        || !timestampCol->recordData() || !eventTypeCol->recordData()
        || !deletedCol->recordData()) {
      std::cerr << "Failed to open EventsTable columns for update" << std::endl;
      return -1;
    }

    const uint8_t deleted = 0;
    auto status = overwriteEventCell(timestampCol->recordData(),
                                     idx,
                                     AQNWB::IO::BaseDataType::F32,
                                     &timestampSeconds);
    status = status
        && overwriteEventCell(eventTypeCol->recordData(),
                              idx,
                              AQNWB::IO::BaseDataType::I32,
                              &eventLabel);
    status = status
        && overwriteEventCell(deletedCol->recordData(),
                              idx,
                              AQNWB::IO::BaseDataType::U8,
                              &deleted);
    if (status != AQNWB::Types::Status::Success) {
      std::cerr << "Failed to update event row " << rowIndex << std::endl;
      return -1;
    }
    if (g_io->flush() != AQNWB::Types::Status::Success) {
      std::cerr << "Failed to flush after update event" << std::endl;
      return -1;
    }
    return 0;
  } catch (const std::exception& e) {
    std::cerr << "Error in nwbfile_update_event: " << e.what() << std::endl;
    return -1;
  }
}

FFI_PLUGIN_EXPORT int32_t nwbfile_delete_event(int32_t rowIndex)
{
  if (!g_io || !g_eventsTable) {
    std::cerr << "EventsTable not initialized" << std::endl;
    return -1;
  }
  if (rowIndex < 0
      || static_cast<AQNWB::Types::SizeType>(rowIndex) >= g_eventRowCount) {
    std::cerr << "nwbfile_delete_event invalid rowIndex: " << rowIndex
              << std::endl;
    return -1;
  }
  try {
    // Soft-delete: keep row count / append cursor intact under SWMR.
    auto deletedCol = g_eventsTable->readColumn<uint8_t>("deleted");
    if (!deletedCol || !deletedCol->recordData()) {
      std::cerr << "Failed to open deleted column" << std::endl;
      return -1;
    }
    const uint8_t deleted = 1;
    auto status = overwriteEventCell(deletedCol->recordData(),
                                     static_cast<AQNWB::Types::SizeType>(rowIndex),
                                     AQNWB::IO::BaseDataType::U8,
                                     &deleted);
    if (status != AQNWB::Types::Status::Success) {
      std::cerr << "Failed to soft-delete event row " << rowIndex << std::endl;
      return -1;
    }
    if (g_io->flush() != AQNWB::Types::Status::Success) {
      std::cerr << "Failed to flush after delete event" << std::endl;
      return -1;
    }
    return 0;
  } catch (const std::exception& e) {
    std::cerr << "Error in nwbfile_delete_event: " << e.what() << std::endl;
    return -1;
  }
}

FFI_PLUGIN_EXPORT int32_t nwbfile_get_event_count()
{
  return static_cast<int32_t>(g_eventRowCount);
}

FFI_PLUGIN_EXPORT int32_t nwbfile_set_meaning(int32_t value, const char* meaning)
{
  if (!g_io || !g_eventMeaningsTable) {
    std::cerr << "MeaningsTable not initialized" << std::endl;
    return -1;
  }
  if (meaning == nullptr) {
    std::cerr << "nwbfile_set_meaning: meaning is null" << std::endl;
    return -1;
  }
  try {
    const std::string meaningStr(meaning);

    // Update existing row in place when the value is already registered.
    for (size_t i = 0; i < g_cachedMeanings.size(); ++i) {
      if (g_cachedMeanings[i].value != value) {
        continue;
      }
      auto meaningCol = g_eventMeaningsTable->readMeaningColumn();
      if (!meaningCol || !meaningCol->recordData()) {
        std::cerr << "Failed to open MeaningsTable meaning column" << std::endl;
        return -1;
      }
      auto status = overwriteMeaningString(
          meaningCol->recordData(),
          static_cast<AQNWB::Types::SizeType>(i),
          meaningStr);
      if (status != AQNWB::Types::Status::Success) {
        std::cerr << "Failed to update meaning for value " << value << std::endl;
        return -1;
      }
      if (g_io->flush() != AQNWB::Types::Status::Success) {
        std::cerr << "Failed to flush after update meaning" << std::endl;
        return -1;
      }
      g_cachedMeanings[i].meaning = meaningStr;
      return static_cast<int32_t>(i);
    }

    // Append a new meanings row for an unseen event_type value.
    AQNWB::NWB::DynamicTable::RowData row = {
        {"value", value},
        {"meaning", meaningStr},
    };
    auto status = g_eventMeaningsTable->addRow(row);
    if (status != AQNWB::Types::Status::Success) {
      std::cerr << "Failed to add meaning row for value " << value << std::endl;
      return -1;
    }
    if (g_io->flush() != AQNWB::Types::Status::Success) {
      std::cerr << "Failed to flush after add meaning" << std::endl;
      return -1;
    }
    const int32_t rowIndex = static_cast<int32_t>(g_cachedMeanings.size());
    g_cachedMeanings.push_back({value, meaningStr});
    return rowIndex;
  } catch (const H5::Exception& e) {
    std::cerr << "HDF5 error in nwbfile_set_meaning: " << e.getDetailMsg()
              << std::endl;
    return -1;
  } catch (const std::exception& e) {
    std::cerr << "Error in nwbfile_set_meaning: " << e.what() << std::endl;
    return -1;
  }
}

FFI_PLUGIN_EXPORT int32_t nwbfile_get_meaning_count()
{
  return static_cast<int32_t>(g_cachedMeanings.size());
}

FFI_PLUGIN_EXPORT int32_t nwbfile_read_meaning(int32_t rowIndex,
                                               int32_t* outValue,
                                               char* outMeaning,
                                               int32_t outMeaningCapacity)
{
  if (rowIndex < 0
      || static_cast<size_t>(rowIndex) >= g_cachedMeanings.size()) {
    std::cerr << "nwbfile_read_meaning invalid rowIndex: " << rowIndex
              << std::endl;
    return -1;
  }
  if (outValue == nullptr) {
    return -1;
  }
  const CachedMeaning& row = g_cachedMeanings[static_cast<size_t>(rowIndex)];
  *outValue = row.value;
  if (!copyCString(outMeaning, outMeaningCapacity, row.meaning)) {
    return -1;
  }
  return 0;
}

FFI_PLUGIN_EXPORT int32_t nwbfile_find_meaning(int32_t value,
                                               char* outMeaning,
                                               int32_t outMeaningCapacity)
{
  for (const auto& row : g_cachedMeanings) {
    if (row.value != value) {
      continue;
    }
    if (!copyCString(outMeaning, outMeaningCapacity, row.meaning)) {
      return -1;
    }
    return 0;
  }
  return -1;
}

FFI_PLUGIN_EXPORT int32_t nwbfile_read_event(int32_t rowIndex,
                                             float* outTimestampSeconds,
                                             int32_t* outEventLabel,
                                             uint8_t* outDeleted)
{
  if (rowIndex < 0
      || static_cast<AQNWB::Types::SizeType>(rowIndex) >= g_eventRowCount) {
    std::cerr << "nwbfile_read_event invalid rowIndex: " << rowIndex
              << std::endl;
    return -1;
  }

  // File-review path: events were snapshotted into g_cachedEvents during seek.
  if (!g_cachedEvents.empty()) {
    if (static_cast<size_t>(rowIndex) >= g_cachedEvents.size()) {
      std::cerr << "nwbfile_read_event cache miss for rowIndex: " << rowIndex
                << std::endl;
      return -1;
    }
    const CachedNwbEvent& event = g_cachedEvents[static_cast<size_t>(rowIndex)];
    *outTimestampSeconds = event.timestampSeconds;
    *outEventLabel = event.eventLabel;
    *outDeleted = event.deleted;
    return 0;
  }

  // Live recording path: read from the open EventsTable.
  if (!g_io || !g_eventsTable) {
    std::cerr << "EventsTable not initialized" << std::endl;
    return -1;
  }
  try {
    const AQNWB::Types::SizeType idx =
        static_cast<AQNWB::Types::SizeType>(rowIndex);
    auto timestampCol = g_eventsTable->readTimestampColumn();
    auto eventTypeCol = g_eventsTable->readColumn<int32_t>("event_type");
    auto deletedCol = g_eventsTable->readColumn<uint8_t>("deleted");
    if (!timestampCol || !eventTypeCol || !deletedCol) {
      std::cerr << "Failed to open EventsTable columns for read" << std::endl;
      return -1;
    }

    auto timestampReader = timestampCol->readData();
    auto eventTypeReader = eventTypeCol->readData();
    auto deletedReader = deletedCol->readData();
    if (!timestampReader || !eventTypeReader || !deletedReader) {
      std::cerr << "Failed to create dataset readers for EventsTable columns"
                << std::endl;
      return -1;
    }

    const AQNWB::Types::SizeArray start {idx};
    const AQNWB::Types::SizeArray count {1};
    auto timestampBlock = timestampReader->values(start, count);
    auto eventTypeBlock = eventTypeReader->values(start, count);
    auto deletedBlock = deletedReader->values(start, count);
    if (timestampBlock.data.empty() || eventTypeBlock.data.empty()
        || deletedBlock.data.empty()) {
      std::cerr << "EventsTable read returned no data for row " << rowIndex
                << std::endl;
      return -1;
    }

    *outTimestampSeconds = timestampBlock.data[0];
    *outEventLabel = eventTypeBlock.data[0];
    *outDeleted = deletedBlock.data[0];
    return 0;
  } catch (const std::exception& e) {
    std::cerr << "Error in nwbfile_read_event: " << e.what() << std::endl;
    return -1;
  }
}

FFI_PLUGIN_EXPORT int32_t nwbfile_read_electrical_series(short* outSamples, int* outSamplesCount, int selectedChannel, int channelCount) {
    std::cout << "AQNWB nwbfile_read_electrical_series" << std::endl;
    
    // g_outputPath = "/Users/macbook/Library/Containers/com.example.nwbapplication/Data/Documents/example_recording_multiple_channels.nwb";
    // 1. Open the NWB file for reading
    // std::shared_ptr<BaseIO> io = AQNWB::createIO("HDF5", filePath);
    // auto openStatus = io->open(FileMode::ReadOnly);
    // if (openStatus != AQNWB::Types::Success) {
    //     std::cerr << "Failed to open NWB file: " << filePath << std::endl;
    //     return 1;
    // }
    std::string filePath = g_outputPath;
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
            h5file = std::make_unique<H5::H5File>(g_outputPath, H5F_ACC_RDONLY);
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


    // io = AQNWB::createIO("HDF5", g_outputPath);
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
//       const std::string g_outputPath = "/Users/macbook/Library/Containers/com.example.nwbapplication/Data/Documents/example_recording2.nwb";
//       std::shared_ptr<AQNWB::IO::BaseIO> io = AQNWB::createIO("HDF5", g_outputPath);
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
// //        AQNWB::NWB::ElectricalSeries es = AQNWB::NWB::ElectricalSeries(g_outputPath, io);
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

  
//       std::cout << "Successfully wrote example recording to: " << g_outputPath << std::endl;
        
//       std::shared_ptr<AQNWB::IO::BaseIO> readio = AQNWB::createIO("HDF5", g_outputPath);
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
//           "Created: " + g_outputPath + "\n"
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
    
    // g_outputPath = "/Users/macbook/Library/Containers/com.example.nwbapplication/Data/Documents/example_recording_multiple_channels.nwb";
    g_outputPath = std::string(path);
    std::string filePath = g_outputPath;
    
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
                        // Get the actual datatype from the attribute
                        H5::StrType strType = descAttr.getStrType();
                        // For variable-length strings, HDF5 allocates memory and returns a char*
                        // We need to read into a char* pointer, not directly into std::string
                        char* cstr = nullptr;
                        descAttr.read(strType, &cstr);
                        if (cstr != nullptr) {
                            deviceDescription = std::string(cstr);
                            free(cstr);  // HDF5 allocates the memory, we need to free it
                        }
                        std::cout << "📋 Device Description: " << deviceDescription << std::endl;
                    } catch (const H5::Exception& e) {
                        std::cout << "⚠️  Could not read device description: " << e.getDetailMsg() << std::endl;
                    }
                    
                    // Read device manufacturer
                    try {
                        H5::Attribute manufAttr = deviceGroup.openAttribute("manufacturer");
                        // Get the actual datatype from the attribute
                        H5::StrType strType = manufAttr.getStrType();
                        // For variable-length strings, HDF5 allocates memory and returns a char*
                        // We need to read into a char* pointer, not directly into std::string
                        char* cstr = nullptr;
                        manufAttr.read(strType, &cstr);
                        std::string manufacturer;
                        if (cstr != nullptr) {
                            manufacturer = std::string(cstr);
                            free(cstr);  // HDF5 allocates the memory, we need to free it
                        }
                        std::cout << "🏭 Device Manufacturer: " << manufacturer << std::endl;
                    } catch (const H5::Exception& e) {
                        std::cout << "⚠️  Could not read device manufacturer: " << e.getDetailMsg() << std::endl;
                    }
                    
                    // if (description.find("Audio|||") > -1) {
                    int res = deviceDescription.find("Audio|||");
                    if (res != std::string::npos){
                        outConfig[6] = 0;
                        std::cout << "✅ Audio Device Detected " << deviceDescription << std::endl;
                    } else{ 
                        outConfig[6] = 1;
                        std::cerr << "✅ Serial Device Detected " << deviceDescription << std::endl;
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

        // Snapshot EventsTable rows into g_cachedEvents so that
        // nwbfile_get_event_count()/nwbfile_read_event() work for file
        // review/playback. We cannot keep a live EventsTable here: this
        // function always closes its temporary AQNWB IO at the end, and
        // RegisteredType only holds a weak_ptr to that IO — reusing it
        // across the call would crash on the next read.
        resetEventsSessionState();
        try {
            const std::string eventsTimestampPath = "/events/markers/timestamp";
            const std::string eventsTypePath = "/events/markers/event_type";
            const std::string eventsDeletedPath = "/events/markers/deleted";
            if (H5Lexists(metadataFile->getId(), eventsTimestampPath.c_str(), H5P_DEFAULT) > 0
                && H5Lexists(metadataFile->getId(), eventsTypePath.c_str(), H5P_DEFAULT) > 0
                && H5Lexists(metadataFile->getId(), eventsDeletedPath.c_str(), H5P_DEFAULT) > 0) {
                H5::DataSet timestampDs = metadataFile->openDataSet(eventsTimestampPath);
                H5::DataSet typeDs = metadataFile->openDataSet(eventsTypePath);
                H5::DataSet deletedDs = metadataFile->openDataSet(eventsDeletedPath);

                H5::DataSpace timestampSpace = timestampDs.getSpace();
                hsize_t eventDims[1] = {0};
                timestampSpace.getSimpleExtentDims(eventDims, nullptr);
                const hsize_t eventCount = eventDims[0];

                if (eventCount > 0) {
                    std::vector<float> timestamps(static_cast<size_t>(eventCount));
                    std::vector<int32_t> eventTypes(static_cast<size_t>(eventCount));
                    std::vector<uint8_t> deletedFlags(static_cast<size_t>(eventCount));

                    timestampDs.read(timestamps.data(), H5::PredType::NATIVE_FLOAT);
                    typeDs.read(eventTypes.data(), H5::PredType::NATIVE_INT32);
                    deletedDs.read(deletedFlags.data(), H5::PredType::NATIVE_UINT8);

                    g_cachedEvents.reserve(static_cast<size_t>(eventCount));
                    for (hsize_t i = 0; i < eventCount; ++i) {
                        g_cachedEvents.push_back(CachedNwbEvent {
                            timestamps[static_cast<size_t>(i)],
                            eventTypes[static_cast<size_t>(i)],
                            deletedFlags[static_cast<size_t>(i)],
                        });
                    }
                }
                g_eventRowCount =
                    static_cast<AQNWB::Types::SizeType>(g_cachedEvents.size());
                std::cout << "📌 Cached " << g_eventRowCount
                          << " EventsTable row(s) from " << filePath << std::endl;
            } else {
                std::cout << "ℹ️  No EventsTable found in file (path: "
                          << eventsTimestampPath << ")" << std::endl;
            }
        } catch (const H5::Exception& e) {
            std::cout << "⚠️  Could not load EventsTable: " << e.getDetailMsg()
                      << std::endl;
            g_cachedEvents.clear();
            g_eventRowCount = 0;
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
FFI_PLUGIN_EXPORT void cleanup_nwb_data()
{
  g_nwb_file_data.clear();
  g_nwb_file_data.shrink_to_fit();
  g_nwb_file_ready = false;
}
