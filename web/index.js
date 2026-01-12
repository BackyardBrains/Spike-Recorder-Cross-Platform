// sh /Users/macbook/Documents/...emscriptenFolder.../emcc --bind -O3 --std=c++20 -x c++ LowPassFilter.cpp HighPassFilter.cpp FilterBase.cpp FilterBase.cpp HeartbeatHelper.cpp NotchPassFilter.cpp Processor.cpp ThresholdProcessor.cpp -s TOTAL_MEMORY=536870912 -s EXPORTED_FUNCTIONS="['_malloc']" -s EXPORTED_RUNTIME_METHODS="['ccall']"

//TODO: Use this command to generate a combined WASM
// emcc --bind -O3 --std=c++20 -x c++ low_pass_filter.cpp high_pass_filter.cpp filter_base.cpp main_entry_file.cpp -s TOTAL_MEMORY=536870912 -s EXPORTED_FUNCTIONS="['_malloc']" -s EXPORTED_RUNTIME_METHODS="['ccall']" -pthread -s PROXY_TO_PTHREAD

var mWorker;
let workerChannel;
var fileHandle;

let recordingVisibleSignalsList = [];
let recordingVisibleChannelCount = 1;

function initializeModule() {
  try {
    mWorker.terminate();
  } catch (e) { }

  workerChannel = new MessageChannel();
  mWorker = new Worker("workerSimulation.js");

  mWorker.onmessage = function (event) {
    if (event.data.message == "INITIALIZE_WASM") {
      // mWorker.postMessage(
      //   {
      //     message: "INITIALIZE_WORKER",
      //     simulationWorkerChannelPort: workerChannel.port1,
      //   },
      //   [workerChannel.port1]
      // );
    } else
    if (event.data.message === "ALLOCATE_DRAWING_DATA_BUFFER") {
      let drawingCountBufferList = event.data.drawingCountBufferList;
      let drawingDataBufferList = event.data.drawingDataBufferList;
      let channelCount = event.data.channelCount;
      let eventPositions = event.data.eventPositions;

      console.log("drawingDataBufferList: ", drawingDataBufferList);
      window.onDrawingBufferAllocated(drawingDataBufferList, drawingCountBufferList, channelCount);
      window.onEventPositionAllocated(eventPositions);
    } else
    if (event.data.message === "SERIAL_DATA_TRANSFER") {
      let frameCount = event.data.frameCount;
      window.onSerialParsedCallback(frameCount);
    } else
    if (event.data.message === "EVENT_FOUND") {
      window.onEventFound(event.data.sampleIndex, event.data.eventLabel);
    } else
    if (event.data.message === "onWebApplyFilter") {
      window.onProcessingDone(event.data.channelIdx);
    } else
    if (event.data.message === "SET_DEFAULT_DEVICE_PARAMETERS") {
      // Share the typed view of allocated buffer with Dart
      // window.onDataBufferAllocated(event.data.dataBuffer, event.data.chIdx);
      window.setDefaultDeviceParameters(event.data.sampleRate, event.data.channelCount);
    } else
    if (event.data.message === "dataBufferAllocation") {
      // Share the typed view of allocated buffer with Dart
      window.onDataBufferAllocated(event.data.dataBuffer, event.data.chIdx);
      // window.setDefaultDeviceParameters()
    } else
    if (event.data.message === "INPUT_MICROPHONE_BUFFER_FINISHED") { 
      window.onPostDisplay(event.data.bufferViews, event.data.bufferCountViews);
      window.onEventPositionCalculated();
    } else
    if (event.data.message === "SET_EXPANSION_BOARD_TYPE") { 
      console.log("event.data.expansionBoardType: ", event.data.expansionBoardType);
      window.setExpansionBoardTypeDart(event.data.expansionBoardType);
    } else
    if (event.data.message === "THRESHOLD_PROCESSED_ARRAY_LENGTH") { 
      window.onThresholdProcessCallback(event.data.thresholdArrayLength);
    } else
    if (event.data.message === "INPUT_SERIAL_BUFFER_FINISHED") {
      // console.log("INPUT_SERIAL_BUFFER_FINISHED: ", event.data.bufferViews, event.data.bufferCountViews);
      // window.onProcessingDone(event.data.channelIdx, event.data.bufferViews);
      window.onProcessingDone(event.data.bufferViews, event.data.bufferCountViews);
      window.onEventPositionCalculated();
    } else
    if (event.data.message === "PROCESS_FFT_MICROPHONE_DATA_FINISHED") {
      //out_window_count, out_window_size, out_fft_data, selectedChannel,channelCounts
      window.onCallbackProcessFft(event.data.out_window_count, event.data.out_window_size, event.data.out_fft_data, event.data.selectedChannel, event.data.channelCounts);
    } else
    if (event.data.message === "INIT_FFT_BUFFER_FINISHED") {
      console.log("INIT_FFT_BUFFER_FINISHED: ", event.data.out_fft_data, event.data.out_window_count, event.data.out_window_size, event.data.out_frequency_counter, event.data.out_fft_vertices, event.data.out_fft_indices, event.data.out_fft_colors, event.data.out_fft_vertex_count, event.data.out_fft_index_count, event.data.out_fft_color_count);
      // List<Float32List> out_fft_data, Int16List out_window_count, Int16List out_window_size, Int16List out_frequency_counter, Int16List inSamples, Int16List inSampleCounts,
      // Float32List out_fft_vertices, Int16List out_fft_indices, Float32List out_fft_colors, Int16List out_fft_vertex_count, Int16List out_fft_index_count, Int16List out_fft_color_count 
  
      window.onSendingFftBuffer(event.data.out_fft_data, event.data.out_window_count, event.data.out_window_size, event.data.out_frequency_counter, //event.data.in_samples_fft, event.data.in_sample_counts_fft
        event.data.out_fft_vertices, event.data.out_fft_indices, event.data.out_fft_colors, event.data.out_fft_vertex_count, event.data.out_fft_index_count, event.data.out_fft_color_count);
      window.onEventPositionCalculated();
    } else
    if (event.data.message === "PROCESS_PREPARE_FFT_DRAWING_FINISHED") { 
      // console.log("PROCESS_PREPARE_FFT_DRAWING_FINISHED: ", event.data.resultFft, event.data.selectedChannelIdx);
      window.onCallbackPrepareFftDrawing(event.data.resultFft, event.data.selectedChannelIdx);
    } else
    if (event.data.message == "NWB_FILE_CREATED") {
      console.log("NWB_FILE_CREATED PATH: ", event.data.result);
      window.onNwbFileCreated(event.data.result);
    } else
    if (event.data.message == "SEEK_NWB_FILE_BUFFER_WEB_CALLBACK_PLAYBACK") {
      console.log("SEEK_NWB_FILE_BUFFER_WEB_CALLBACK RESULT: ", event.data.message);
      window.onSeekNwbFileBufferWebCallbackPlayback(event.data.outConfigBuffer, event.data.arrSampleCount, event.data.arrSamples, event.data.isStartOpeningFileWeb);
      // Note: onSeekNwbFileBufferWebCallback will call onStartOpeningFileWebCallback internally
    } else
    if (event.data.message == "SEEK_NWB_FILE_BUFFER_WEB_CALLBACK") {
      console.log("SEEK_NWB_FILE_BUFFER_WEB_CALLBACK RESULT: ", event.data.message);
      window.onSeekNwbFileBufferWebCallback(event.data.outConfigBuffer, event.data.arrSampleCount, event.data.arrSamples, event.data.isStartOpeningFileWeb);
      // Note: onSeekNwbFileBufferWebCallback will call onStartOpeningFileWebCallback internally
    } else
    if (event.data.message === "MAKE_FILE_PUBLIC_CALLBACK") { 
      let fileName = event.data.fileName;
      let fileData = event.data.fileData;
      let status = event.data.status;
      if (status === "SUCCESS") {
        // Display the file data
        // Create a downloadable blob
        // const blob = new Blob([fileData], { type: 'application/octet-stream' });
        // const url = URL.createObjectURL(blob);
        // const a = document.createElement('a');
        // a.href = url;
        // a.download = fileName + '.nwb';
        // // 5. Append the anchor to the document (required for Firefox, but good practice)
        // document.body.appendChild(a);
        // // 6. Programmatically click the anchor to start the download
        // a.click();
        // // 7. Clean up the temporary URL and anchor element
        // // The revokeObjectURL is crucial to free up memory!
        // window.URL.revokeObjectURL(url);
        // document.body.removeChild(a);      
      } else {
        alert("Failed to record file.");
      }
                      
    }

    
    // Listening to messages
    workerChannel.port2.onmessage = function (event) { };
  };
}

function sendToWebInitHighPassFilter(
  channelCount,
  sampleRate,
  cutOffFrequency,
  q
) {
  // Create an object to hold the message data
  const messageData = {
    message: "webInitHighPassFilter",
    channelCount: channelCount,
    sampleRate: sampleRate,
    cutOffFrequency: cutOffFrequency,
    q: 0.5,
  };
  // Send the message to the web worker
  mWorker.postMessage(messageData);
  // Optionally, log a message after sending
}

function sendToWebInitLowPassFilter(
  channelCount,
  sampleRate,
  cutOffFrequency,
  q
) {
  // Create an object to hold the message data
  const messageData = {
    message: "webInitLowPassFilter",
    channelCount: channelCount,
    sampleRate: sampleRate,
    cutOffFrequency: cutOffFrequency,
    q: 0.5,
  };

  // Send the message to the web worker
  mWorker.postMessage(messageData);
}

function sendToWorkerApplyFilter(
  channelIdx,
  samples,
  toApplyHighPass,
  toApplyLowPass,
  toApplyNotch
) {
  // Create an object to hold the message data
  const messageData = {
    message: "webApplyFilter",
    toApplyHighPass: toApplyHighPass,
    toApplyLowPass: toApplyLowPass,
    toApplyNotch: toApplyNotch,
    channelIdx: channelIdx,
    samples: samples,
    "drawSurfaceWidth": window.innerWidth,
  };

  // Send the message to the web worker
  mWorker.postMessage(messageData);
}


function initializeMicrophoneWeb(channelCount, sampleRate, drawSurfaceWidth) {
  console.log("INITIALIZE SAMPLE RATE", sampleRate);
  mWorker.postMessage({
    "message": "INITIALIZE_MICROPHONE",
    "channelCount": channelCount,
    "sampleRate": sampleRate,
    "drawSurfaceWidth": window.innerWidth,
  });
}

function prepareDisplayMicrophoneDataWeb(drawSurfaceWidth, channelCount, displayTimeMs, startPositionIdx, endPositionIdx, eventLabels, eventPositions) {
  const microphoneData = {
    "message": "DISPLAY_MICROPHONE_DATA",
    "channelCount": channelCount,
    "displayTimeMs": displayTimeMs,
    "drawSurfaceWidth": window.innerWidth,
    "startPositionIdx": startPositionIdx,
    "endPositionIdx": endPositionIdx,
    "eventLabels": eventLabels,
    "eventPositions": eventPositions,

  };
  mWorker.postMessage(microphoneData);
}

function processMicrophoneDataWeb(microphoneDataBuffers, channelIdx, samplesLength, eventLabels, eventPositions) {
  mWorker.postMessage({
    "message": "INPUT_MICROPHONE_BUFFER",
    "microphoneDataBuffers": microphoneDataBuffers,
    "channelIdx": channelIdx,
    "samplesLength": samplesLength,
    "drawSurfaceWidth": window.innerWidth,
    "eventLabels": eventLabels,
    "eventPositions": eventPositions,
  });
  // if (isProcessNow) {
  // } else {
  // }
  //   console.log("microphoneDataBuffer");
  //   console.log(microphoneDataBuffer);
}

function setBandFilterWeb(lowFreq, highFreq) {
  mWorker.postMessage({
    "message": "SET_BAND_FILTER",
    "lowFreq": lowFreq,
    "highFreq": highFreq,
  });
}

function setNotchFilterWeb(centerFreq) {
  mWorker.postMessage({
    "message": "SET_NOTCH_FILTER",
    "centerFreq": centerFreq,
  });
}

function initializeSerialWeb(sampleRate, channelCount, drawSurfaceWidth){
  console.log("Channel Count: ", channelCount, sampleRate);
  if (drawSurfaceWidth === -1) {
    drawSurfaceWidth = window.innerWidth;
  }
  mWorker.postMessage({
    "message": "INITIALIZE_SERIAL",
    "channelCount": parseInt(channelCount),
    "sampleRate": sampleRate,
    "drawSurfaceWidth": drawSurfaceWidth,
  });
}
function processSerialDataWeb(samples, displayTimeMs, deviceType, eventLabels, eventPositions){
  // console.log("samples: ", samples);
  mWorker.postMessage({
    "message": "SEND_SERIAL_DATA_WEB",
    "samples": samples,
    "channelIdx": 0,
    "displayTimeMs": displayTimeMs,
    "deviceType": deviceType,
    // "deviceType": 5,
    "drawSurfaceWidth": window.innerWidth,
    "eventLabels": eventLabels,
    "eventPositions": eventPositions,
  });
}
function displaySerialDataWeb(displayTimeMs, deviceType, deviceWidth, startPositionIdx, endPositionIdx, eventLabels, eventPositions){
  // console.log("eventPositions: ", eventPositions);
  mWorker.postMessage({
    "message": "DISPLAY_SERIAL_DATA_WEB",
    "channelIdx": 0,
    "displayTimeMs": displayTimeMs,
    "deviceType": deviceType,
    "startPositionIdx": startPositionIdx,
    "endPositionIdx": endPositionIdx,
    // "deviceType": 5,
    "drawSurfaceWidth": window.innerWidth,
    "eventLabels": eventLabels,
    "eventPositions": eventPositions,

  });
}

function setChannelFilterEnabled(channel, enabled) {
  mWorker.postMessage({
    "message": "SET_CHANNEL_FILTER_ENABLED",
    "channelIndex": channel,
    "enabled": enabled,
  });
}



/* 
  THRESHOLDING
*/

function initThreshold(channelCount, sampleRate, drawSurfaceWidth) {
  console.log("initThreshold: ", channelCount, sampleRate, drawSurfaceWidth);
  mWorker.postMessage({
    "message": "INIT_THRESHOLD",
    "channelCount": channelCount,
    "sampleRate": sampleRate,
    "drawSurfaceWidth": drawSurfaceWidth,
  });
}

function setAveragedSampleCount(avgSampleCount) {
  console.log("avgSampleCount: ", avgSampleCount);
  mWorker.postMessage({
    "message": "SET_THRESHOLD_AVERAGE_SAMPLE",
    "avgSampleCount": avgSampleCount,
  });
}

function setThreshold(thresholdValue) {
  console.log("setThreshold: ", thresholdValue);
  mWorker.postMessage({
    "message": "SET_THRESHOLD_VALUE",
    "thresholdValue": thresholdValue,
  });
}

function setIsThresholding(isThresholding) {
  console.log("setIsThresholding: ", isThresholding);
  mWorker.postMessage({
    "message": "SET_THRESHOLD_IS_THRESHOLDING",
    "isThresholding": isThresholding,
  });
}

function setThresholdTriggerType(eventThresholdTriggeredType) {
  console.log("setThresholdTriggerType: ", eventThresholdTriggeredType);
  mWorker.postMessage({
    "message": "SET_THRESHOLD_TRIGGER_TYPE",
    "eventThresholdTriggeredType": eventThresholdTriggeredType,
  });
}

function initFft(windowCount, windowSize, channelCount,selectedChannel) {
  return;
  console.log("initFft: ", windowCount, windowSize);
  mWorker.postMessage({
    "message": "INIT_FFT",
    "channelCount": channelCount,
    "selectedChannel": selectedChannel,
    "windowCount": windowCount,
    "windowSize": windowSize,
  });
}

function processFftMicrophoneData(channelCount, selectedChannel, windowCount, windowSize, inSamples, inSampleCounts) {
  mWorker.postMessage({
    "message": "PROCESS_FFT_MICROPHONE_DATA",
    "channelCount": channelCount,
    "selectedChannel": selectedChannel,
    "windowCount": windowCount,
    "windowSize": windowSize,
    "inSamples": inSamples,
    "inSampleCounts": inSampleCounts,
  });
}

// drawBuffer,
// windowCount,
// windowSize,
// targetWindowCount,
// width,
// height

function prepareFftDrawing(drawBuffer, selectedChannelIdx, windowCount, windowSize, targetWindowCount, width, height) {
  mWorker.postMessage({
    "message": "PROCESS_PREPARE_FFT_DRAWING",
    "drawBuffer": drawBuffer,
    "selectedChannelIdx": selectedChannelIdx,
    "windowCount": windowCount,
    "windowSize": windowSize,
    "targetWindowCount": targetWindowCount,
    "width": width,
    "height": height,
  });
}

async function recordNewNwbFile(path) {
  
  const newDate = new Date();
  const newFileName = "spike_recorder"+newDate.getFullYear()+"-"+newDate.getMonth()+"-"+newDate.getDate()+"_"+newDate.getHours()+"."+newDate.getMinutes()+"."+newDate.getSeconds();
  const options = {
    excludeAcceptAllOption:true,
    suggestedName: newFileName,
    types: [
      {
        description: 'Spike-Recorder',
        accept: {
          'application/octet-stream': ['.nwb'],
        },
      },
    ],
  };  
  try{
    fileHandle = null;
    fileHandle = await window.showSaveFilePicker(options);
    console.log("fileHandle: ", fileHandle);
    if (fileHandle == null) {
      window.onNwbFileCreated("--");
      return "File not opened";
    }
  }catch(e){
    console.log("error: ", e);
    if (fileHandle == null) {
      window.onNwbFileCreated("--");
      return "File not opened";
    }
  }

  window.onNwbFileCreated(newFileName);
  
  return newFileName;
}

async function createNwbFile(filePath, sampleRate, channelCount, deviceInfoPointer, deviceManufacturerPointer, visibleSignalsList, visibleChannelCount) {
  // const newDate = new Date();

  // const newFileName = "BYB_Recording_"+newDate.getFullYear()+"-"+newDate.getMonth()+"-"+newDate.getDate()+"_"+newDate.getHours()+"."+newDate.getMinutes()+"."+newDate.getSeconds();
  let cookie = getCookie("RECORDED_NWB_FILE");
  if (cookie !== undefined || cookie == "") {
    cookie = "";
  }
  console.log("visibleChannelCount: ", visibleChannelCount);
  console.log("COOKIE: ", cookie + filePath + ";");
  setCookie("RECORDED_NWB_FILE", cookie + filePath + ";");
  //2022-03-18_15.36.04
  mWorker.postMessage({
    "message": "CREATE_NWB_FILE",
    "filePath": filePath,
    "sampleRate": sampleRate,
    "channelCount": channelCount,
    "deviceInfoPointer": deviceInfoPointer,
    "deviceManufacturerPointer": deviceManufacturerPointer,
    "fileHandle": fileHandle,
    "visibleSignalsList": visibleSignalsList, 
    "visibleChannelCount": visibleChannelCount,
    "recordedFileCookie": cookie
  });
  return "Creating File";
}


function addElectricalSeriesWeb(samples, samplesCount, selectedChannel, channelCount, isFinishRecording) {
  mWorker.postMessage({
    "message": "ADD_ELECTRICAL_SERIES",
    "samples": samples,
    "samplesCount": samplesCount,
    "selectedChannel": selectedChannel,
    "channelCount": channelCount,
    "isFinishRecording": isFinishRecording,
  });
}


async function makeFilePublicWeb(path) {
  if (fileHandle == null) {
    alert("Please create a file first.");
    return;
  }
  mWorker.postMessage({
    "message": "MAKE_FILE_PUBLIC",
    "fileHandle": fileHandle,
    "fileName": path,
  });
}

async function startOpeningFileWeb(filePath, startIdx, endIdx, startChannel, endChannel, isStartOpeningFileWeb = false) {
  console.log("isStartOpeningFileWeb: ", isStartOpeningFileWeb);
  if (isStartOpeningFileWeb) {
    const options = {
      multiple: false,
      types: [
        {
          description: 'Spike-Recorder',
          accept: {
            // 'audio/wav': ['.wav'],
            // 'text/plain': ['.txt'],
            'application/zip': ['.nwb'],
          },
        },
      ],
    };
    try{
      fileHandle = null;
      fileHandle = await window.showOpenFilePicker(options);
      console.log("fileHandle: ", fileHandle);
      if (fileHandle == null) {
        return "File not opened";
      }

      const file = await fileHandle[0].getFile();
      // 3. Access the size property (in bytes)
      const fileSizeInBytes = file.size;      
      if (fileSizeInBytes < 10) {
        return "File can't be opened"
      }
    }catch(e){
      console.log("error: ", e);
      return "File not opened";
    }
  }
  console.log("MWORKER TRY TO POST MESSAGE: ");
  mWorker.postMessage({
    "message": "START_OPENING_FILE_WEB",
    "filePath": fileHandle[0].name,
    "startIdx": startIdx,
    "endIdx": endIdx,
    "startChannel": startChannel,
    "endChannel": endChannel,
    "fileHandle": fileHandle[0],
    "isStartOpeningFileWeb": isStartOpeningFileWeb,
  });
}

async function seekOpeningFileWeb(filePath, startIdx, endIdx, startChannel, endChannel, isStartOpeningFileWeb = false) {
  console.log("isSeekOpeningFileWeb: ", isStartOpeningFileWeb);
  if (isStartOpeningFileWeb) {
    const options = {
      multiple: false,
      types: [
        {
          description: 'Spike-Recorder',
          accept: {
            // 'audio/wav': ['.wav'],
            // 'text/plain': ['.txt'],
            'application/zip': ['.nwb'],
          },
        },
      ],
    };
    try{
      fileHandle = null;
      fileHandle = await window.showOpenFilePicker(options);
      console.log("fileHandle: ", fileHandle);
      if (fileHandle == null) {
        return "File not opened";
      }
    }catch(e){
      console.log("error: ", e);
      if (fileHandle == null) {
        return "File not opened";
      }
    }
  }
  console.log("MWORKER TRY TO POST MESSAGE: ");
  mWorker.postMessage({
    "message": "SEEK_OPENING_FILE_WEB",
    "filePath": fileHandle[0].name,
    "startIdx": startIdx,
    "endIdx": endIdx,
    "startChannel": startChannel,
    "endChannel": endChannel,
    "fileHandle": fileHandle[0],
    "isStartOpeningFileWeb": isStartOpeningFileWeb,
  });
}

async function initWithConfig(config) {
  console.log("initWithConfig INDEX.js: ", config);
  mWorker.postMessage({
    "message": "INIT_WITH_CONFIG",
    "config": config,
  });
}

// async function fillLoadedSamplesToBuffer(config) {
//   mWorker.postMessage({
//     "message": "FILL_LOADED_SAMPLES_TO_BUFFER",
//     "config": config,
//   });
// }

async function processSerialDataWebResult(data, sampleCounts, channelCount, eventLabels, eventPositions) { 
  mWorker.postMessage({
    "message": "PROCESS_SERIAL_DATA_WEB_RESULT",
    "data": data,
    "sampleCounts": sampleCounts,
    "channelCount": channelCount,
    "eventLabels": eventLabels,
    "eventPositions": eventPositions,
  });
}


function setCookie(cname, cvalue, exdays) {
  const d = new Date();
  d.setTime(d.getTime() + (exdays*24*60*60*1000));
  let expires = "expires="+ d.toUTCString();
  document.cookie = cname + "=" + cvalue + ";" + expires + ";path=/";
}

function getCookie(cname) {
  let name = cname + "=";
  let decodedCookie = decodeURIComponent(document.cookie);
  let ca = decodedCookie.split(';');
  for(let i = 0; i <ca.length; i++) {
    let c = ca[i];
    while (c.charAt(0) == ' ') {
      c = c.substring(1);
    }
    if (c.indexOf(name) == 0) {
      return c.substring(name.length, c.length);
    }
  }
  return "";
}


